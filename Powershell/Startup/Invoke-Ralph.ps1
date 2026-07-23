#Requires -Version 7.0

<#
.SYNOPSIS
    Implements local-tracker features iteratively with Codex or GitHub Copilot CLI.

.DESCRIPTION
    Runs one bounded agent invocation per iteration. Without TaskFile, the agent
    selects and continues the highest-priority unfinished feature below
    .scratch/<feature>/issues. With TaskFile, only that spec or ticket is handled.

    Progress is shared through .scratch/progress.txt. The agent records completed
    features as "FEATURE_COMPLETE: <slug>" and emits
    "<promise>COMPLETE</promise>" when the entire requested scope is complete.

.EXAMPLE
    Invoke-Ralph.ps1 -Agent codex

.EXAMPLE
    Invoke-Ralph.ps1 -Agent copilot -Iterations 5

.EXAMPLE
    Invoke-Ralph.ps1 -Agent codex -TaskFile .scratch/watch-command/spec.md
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('codex', 'copilot')]
    [string]
    $Agent = 'codex',

    [Parameter()]
    [ValidateRange(1, [int]::MaxValue)]
    [int]
    $Iterations = 1,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $TaskFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NativeText {
    param(
        [Parameter(Mandatory)]
        [string]
        $FilePath,

        [Parameter()]
        [string[]]
        $ArgumentList = @()
    )

    $output = & $FilePath @ArgumentList 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "'$FilePath' failed with exit code $LASTEXITCODE.$([Environment]::NewLine)$message"
    }

    return ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
}

function Invoke-Agent {
    param(
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [string]
        $CommandPath,

        [Parameter(Mandatory)]
        [string]
        $Prompt
    )

    $arguments = switch ($Name) {
        'codex' {
            @(
                'exec',
                '--model', 'gpt-5.6-sol',
                '--config', 'model_reasoning_effort="low"',
                '--sandbox', 'workspace-write',
                $Prompt
            )
        }
        'copilot' {
            @('-p', $Prompt, '--model', 'auto', '-s', '--allow-tool=read,write,shell')
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    & $CommandPath @arguments 2>&1 | ForEach-Object {
        $line = $_.ToString()
        $lines.Add($line)
        Write-Host $line
    }

    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }

    return $lines -join [Environment]::NewLine
}

function Get-NewFeatureCompletion {
    param(
        [Parameter(Mandatory)]
        [string]
        $Before,

        [Parameter(Mandatory)]
        [string]
        $After
    )

    $appendedContent = if ($After.StartsWith($Before, [System.StringComparison]::Ordinal)) {
        $After.Substring($Before.Length)
    }
    else {
        ''
    }
    $completionMatches = [regex]::Matches(
        $appendedContent,
        '(?m)^FEATURE_COMPLETE: ([^\r\n]+)\r?$'
    )

    if ($completionMatches.Count -gt 1) {
        throw 'The iteration appended more than one FEATURE_COMPLETE record.'
    }
    if ($completionMatches.Count -eq 0) {
        return $null
    }

    $slug = $completionMatches[0].Groups[1].Value
    if ($slug -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Unsafe feature slug in FEATURE_COMPLETE record: '$slug'."
    }

    return $slug
}

function Move-CompletedFeature {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [string]
        $Slug
    )

    $source = Join-Path $ScratchDirectory $Slug
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Completed feature directory not found: $source"
    }

    $doneDirectory = Join-Path $ScratchDirectory 'done'
    $destination = Join-Path $doneDirectory $Slug
    if (Test-Path -LiteralPath $destination) {
        throw "Completed feature archive already exists: $destination"
    }

    if (-not (Test-Path -LiteralPath $doneDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $doneDirectory | Out-Null
    }
    Move-Item -LiteralPath $source -Destination $destination
}

$git = Get-Command git -ErrorAction Stop
$agentCommand = Get-Command $Agent -ErrorAction Stop

$repositoryRoot = Invoke-NativeText -FilePath $git.Source -ArgumentList @(
    'rev-parse',
    '--show-toplevel'
)
$repositoryRoot = $repositoryRoot.Trim()

if ([string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'Could not determine the Git repository root.'
}

Set-Location -LiteralPath $repositoryRoot

$gitStatus = Invoke-NativeText -FilePath $git.Source -ArgumentList @(
    'status',
    '--porcelain'
)
if (-not [string]::IsNullOrWhiteSpace($gitStatus)) {
    throw 'The Git working tree is not clean. Commit or stash all changes before running Invoke-Ralph.'
}

$scratchDirectory = Join-Path $repositoryRoot '.scratch'
if (-not (Test-Path -LiteralPath $scratchDirectory -PathType Container)) {
    throw "Local issue tracker directory not found: $scratchDirectory"
}

$progressFile = Join-Path $scratchDirectory 'progress.txt'
if (-not (Test-Path -LiteralPath $progressFile -PathType Leaf)) {
    New-Item -ItemType File -Path $progressFile | Out-Null
}

$scopeInstruction = if ($PSBoundParameters.ContainsKey('TaskFile')) {
    $resolvedTask = Resolve-Path -LiteralPath $TaskFile -ErrorAction Stop
    $taskPath = [System.IO.Path]::GetRelativePath(
        $repositoryRoot,
        $resolvedTask.Path
    )

    @"
Work only on the explicit task file '$taskPath'.
If it is a spec, complete only that feature. If it is one ticket, complete only
that ticket. Emit <promise>COMPLETE</promise> once this explicit scope is fully
implemented and verified.
"@
}
else {
    $issueDirectories = @(
        Get-ChildItem -LiteralPath $scratchDirectory -Directory |
            Where-Object { $_.Name -cne 'done' } |
            ForEach-Object {
                $issues = Join-Path $_.FullName 'issues'
                if (Test-Path -LiteralPath $issues -PathType Container) {
                    [System.IO.Path]::GetRelativePath($repositoryRoot, $issues)
                }
            }
    )

    if ($issueDirectories.Count -eq 0) {
        throw "No feature issue directories found below $scratchDirectory."
    }

    $issueDirectoryList = $issueDirectories -join [Environment]::NewLine
    @"
Choose the highest-priority unfinished feature from these local issue directories:
$issueDirectoryList

Use the specs, tickets, dependencies, and .scratch/progress.txt to decide priority.
If a feature was started in an earlier iteration, continue it until it is complete
before selecting another feature. When one feature is complete, append exactly
'FEATURE_COMPLETE: <feature-slug>' to .scratch/progress.txt and choose another
unfinished feature in a later iteration.

Emit <promise>COMPLETE</promise> only when every listed feature is fully implemented,
verified, and recorded as complete in .scratch/progress.txt.
"@
}

$prompt = @"
You are implementing work in the Git repository at '$repositoryRoot'.

$scopeInstruction

For this iteration:
1. Read the relevant spec, every ticket for the selected feature, repository
   instructions, and .scratch/progress.txt.
2. Select exactly one unblocked ticket that is not already recorded as completed.
3. Implement only that ticket as an end-to-end, verifiable slice.
4. Determine and run the repository's relevant tests, type checks, linters, or
   build checks. Do not claim completion if a relevant check fails.
5. Append a concise handoff note to .scratch/progress.txt. Record the feature slug,
   ticket, changes, checks and results, and useful context for the next iteration.
6. If all tickets in the selected feature are now implemented and verified, append
   exactly 'FEATURE_COMPLETE: <feature-slug>' to .scratch/progress.txt.
7. Leave staging and committing to Ralph after the iteration succeeds.

Do not work on more than one ticket in this iteration. Do not modify ticket or spec
files merely to track status; progress.txt is the source of truth. Do not stage,
commit, push, rewrite history, reset, clean, discard unrelated work, use destructive
Git commands, or change anything outside this repository.

If the entire requested scope was already complete at the start, do not invent work
or request an empty commit. Ensure progress.txt contains any required feature
completion entry, then emit <promise>COMPLETE</promise>.
"@

Write-Host "Repository: $repositoryRoot"
Write-Host "Agent: $($agentCommand.Name)"
Write-Host "Progress: $progressFile"

for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    Write-Host ''
    Write-Host "Iteration $iteration of $Iterations"
    Write-Host ('-' * 40)

    $progressBeforeIteration = [System.IO.File]::ReadAllText($progressFile)
    $result = Invoke-Agent -Name $Agent -CommandPath $agentCommand.Source -Prompt $prompt
    $scopeComplete = $result.Contains(
        '<promise>COMPLETE</promise>',
        [System.StringComparison]::Ordinal
    )
    $progressAfterIteration = [System.IO.File]::ReadAllText($progressFile)
    $progressChanged = -not [string]::Equals(
        $progressBeforeIteration,
        $progressAfterIteration,
        [System.StringComparison]::Ordinal
    )
    $gitStatus = Invoke-NativeText -FilePath $git.Source -ArgumentList @(
        'status',
        '--porcelain',
        '--untracked-files=all'
    )
    $hasChanges = $progressChanged -or -not [string]::IsNullOrWhiteSpace($gitStatus)

    if (-not $hasChanges) {
        if (-not $scopeComplete) {
            throw 'The agent completed successfully but produced no changes.'
        }

        Write-Host 'Requested scope complete.'
        exit 0
    }

    if (-not $progressChanged) {
        throw 'The agent changed the repository without updating .scratch/progress.txt.'
    }

    $changeEntriesBefore = [regex]::Matches(
        $progressBeforeIteration,
        '(?m)^changes: (.*)$'
    )
    $changeEntries = [regex]::Matches(
        $progressAfterIteration,
        '(?m)^changes: (.*)$'
    )
    if ($changeEntries.Count -eq 0) {
        throw "The updated progress file does not contain a 'changes: ' entry."
    }

    $finalChangeValue = $changeEntries[$changeEntries.Count - 1].Groups[1].Value
    $hasNewChangeEntry = $changeEntries.Count -ne $changeEntriesBefore.Count
    if (-not $hasNewChangeEntry -and $changeEntriesBefore.Count -gt 0) {
        $previousChangeValue = $changeEntriesBefore[
            $changeEntriesBefore.Count - 1
        ].Groups[1].Value
        $hasNewChangeEntry = $finalChangeValue -cne $previousChangeValue
    }
    if (-not $hasNewChangeEntry) {
        throw "The updated progress file reuses a stale 'changes: ' entry."
    }

    $commitSubject = $finalChangeValue.Trim()
    if ([string]::IsNullOrWhiteSpace($commitSubject)) {
        throw "The final 'changes: ' value in the progress file is empty."
    }

    $completedFeature = Get-NewFeatureCompletion `
        -Before $progressBeforeIteration `
        -After $progressAfterIteration
    if ($null -ne $completedFeature) {
        Move-CompletedFeature -ScratchDirectory $scratchDirectory -Slug $completedFeature
    }

    Invoke-NativeText -FilePath $git.Source -ArgumentList @('add', '--all') | Out-Null
    Invoke-NativeText -FilePath $git.Source -ArgumentList @(
        'add',
        '--force',
        '--',
        $progressFile
    ) | Out-Null
    Invoke-NativeText -FilePath $git.Source -ArgumentList @(
        'commit',
        '--message',
        $commitSubject
    ) | Out-Null

    if ($scopeComplete) {
        Write-Host 'Requested scope complete.'
        exit 0
    }
}

Write-Host "Reached the iteration limit ($Iterations)."
exit 0
