#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ralphScript = Join-Path $PSScriptRoot '..\Startup\Invoke-Ralph.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'Invoke-Ralph.Tests.' + [guid]::NewGuid().ToString('N')
)
$originalPath = $env:PATH

function Assert-Equal {
    param($Expected, $Actual, [string] $Because)
    if ($Expected -cne $Actual) {
        throw "$Because`nExpected: <$Expected>`nActual:   <$Actual>"
    }
}

function Assert-True {
    param([bool] $Condition, [string] $Because)
    if (-not $Condition) {
        throw $Because
    }
}

function Invoke-Git {
    param([string] $Repository, [string[]] $Arguments)
    $output = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join "`n")"
    }
    return ($output | ForEach-Object { $_.ToString() }) -join "`n"
}

function New-TestRepository {
    param([string] $Name)

    $repository = Join-Path $temporaryRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $repository '.scratch\feature\issues') -Force |
        Out-Null
    Set-Content -LiteralPath (Join-Path $repository '.gitignore') -Value ".scratch/`n"
    Set-Content -LiteralPath (Join-Path $repository 'baseline.txt') -Value "baseline`n"
    Set-Content -LiteralPath (Join-Path $repository '.scratch\progress.txt') -Value @'
feature: previous
changes: previous iteration
'@
    Set-Content -LiteralPath (Join-Path $repository '.scratch\feature\spec.md') -Value '# Spec'
    Set-Content -LiteralPath (Join-Path $repository '.scratch\feature\issues\01.md') -Value '# Ticket'

    Invoke-Git $repository @('init', '--quiet') | Out-Null
    Invoke-Git $repository @('config', 'user.name', 'Ralph Tests') | Out-Null
    Invoke-Git $repository @('config', 'user.email', 'ralph-tests@example.invalid') | Out-Null
    Invoke-Git $repository @('add', '.gitignore', 'baseline.txt') | Out-Null
    Invoke-Git $repository @('commit', '--quiet', '--message', 'baseline') | Out-Null
    return $repository
}

function Invoke-TestCase {
    param(
        [string] $Name,
        [ValidateSet('codex', 'copilot')]
        [string] $Agent = 'codex',
        [int] $ExpectedExitCode = 0,
        [switch] $AutomaticDiscovery,
        [scriptblock] $Arrange
    )

    $repository = New-TestRepository $Name
    $agentDirectory = Join-Path $temporaryRoot "$Name.fake-agent"
    $agentLog = Join-Path $temporaryRoot "$Name.arguments.txt"
    New-Item -ItemType Directory -Path $agentDirectory | Out-Null
    $fakeAgent = @'
param([Parameter(ValueFromRemainingArguments)] [string[]] $AgentArguments)
$ErrorActionPreference = 'Stop'
[System.IO.File]::WriteAllLines($env:RALPH_AGENT_LOG, $AgentArguments)
$root = (& git rev-parse --show-toplevel).Trim()
$progress = Join-Path $root '.scratch\progress.txt'
switch ($env:RALPH_TEST_SCENARIO) {
    'success' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress "changes: stale subject`nchanges:   Exact Subject: Keep CASE, punctuation!   "
        '<promise>COMPLETE</promise>'
    }
    'stale-progress' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        'done'
    }
    'missing-changes' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress 'feature: test'
        'done'
    }
    'empty-changes' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress 'changes:    '
        'done'
    }
    'complete-no-changes' {
        '<promise>COMPLETE</promise>'
    }
    'no-changes' {
        'done'
    }
    'agent-failure' {
        [Console]::Error.WriteLine('controlled agent failure')
        exit 17
    }
    'stage-failure' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress 'changes: stage failure'
        Set-Content (Join-Path $root '.git\index.lock') 'controlled lock'
        'done'
    }
    'commit-failure' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress 'changes: commit failure'
        'done'
    }
    'archive-success' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress "feature: feature`nchanges: archive feature`nFEATURE_COMPLETE: feature"
        'done'
    }
    'promise-without-marker' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress "feature: feature`nchanges: scoped ticket complete"
        '<promise>COMPLETE</promise>'
    }
    'multiple-completions' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress "changes: ambiguous completion`nFEATURE_COMPLETE: feature`nFEATURE_COMPLETE: other"
        'done'
    }
    'missing-active-feature' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress "changes: missing active feature`nFEATURE_COMPLETE: missing"
        'done'
    }
    'existing-archive' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress "changes: archive already exists`nFEATURE_COMPLETE: feature"
        'done'
    }
    'unsafe-completion' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress "changes: unsafe completion`nFEATURE_COMPLETE: ../feature"
        'done'
    }
    'discovery-excludes-done' {
        '<promise>COMPLETE</promise>'
    }
}
'@
    Set-Content -LiteralPath (Join-Path $agentDirectory "$Agent.ps1") -Value $fakeAgent

    if ($Arrange) {
        & $Arrange $repository
    }

    $env:PATH = "$agentDirectory;$originalPath"
    $env:RALPH_AGENT_LOG = $agentLog
    $env:RALPH_TEST_SCENARIO = $Name -replace '^(codex|copilot)-', ''
    try {
        Push-Location -LiteralPath $repository
        $ralphArguments = @('-NoProfile', '-File', $ralphScript, '-Agent', $Agent)
        if (-not $AutomaticDiscovery) {
            $ralphArguments += @(
                '-TaskFile',
                (Join-Path $repository '.scratch\feature\spec.md')
            )
        }
        $output = & pwsh @ralphArguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
        $env:PATH = $originalPath
        Remove-Item Env:RALPH_AGENT_LOG, Env:RALPH_TEST_SCENARIO -ErrorAction SilentlyContinue
    }

    Assert-Equal $ExpectedExitCode $exitCode (
        "$Name returned the wrong exit code.`n" +
        (($output | ForEach-Object { $_.ToString() }) -join "`n")
    )
    [pscustomobject]@{
        Repository = $repository
        Output = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        AgentArguments = if (Test-Path $agentLog) { Get-Content $agentLog } else { @() }
    }
}

try {
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

    foreach ($agent in 'codex', 'copilot') {
        $result = Invoke-TestCase "$agent-success" -Agent $agent
        Assert-Equal 2 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
            "$agent should create one iteration commit."
        Assert-Equal 'Exact Subject: Keep CASE, punctuation!' (
            Invoke-Git $result.Repository @('log', '-1', '--format=%s')
        ) "$agent should use the trimmed final changes value verbatim."
        $paths = Invoke-Git $result.Repository @('show', '--pretty=', '--name-only', 'HEAD')
        Assert-True ($paths -match '(?m)^work\.txt$') 'The implementation file was not committed.'
        Assert-True ($paths -match '(?m)^\.scratch/progress\.txt$') `
            'The ignored progress file was not committed.'
        Assert-Equal '' (Invoke-Git $result.Repository @('status', '--porcelain')) `
            'A successful iteration should leave a clean tree.'
        $prompt = $result.AgentArguments -join "`n"
        Assert-True ($prompt -match 'Do not stage,' -and $prompt -match 'commit, push') `
            "$agent was not told to avoid staging and committing."
        Assert-True ($prompt -notmatch 'Create one Git commit') `
            "$agent was still instructed to create a commit."
    }

    $result = Invoke-TestCase 'stale-progress' -ExpectedExitCode 1
    Assert-True ($result.Output -match 'without updating .scratch/progress.txt') `
        'A stale progress file should be rejected.'
    Assert-Equal '' (Invoke-Git $result.Repository @('diff', '--cached', '--name-only')) `
        'Validation must happen before staging.'
    Assert-Equal 1 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
        'Stale progress must not create a commit.'

    foreach ($scenario in 'missing-changes', 'empty-changes') {
        $result = Invoke-TestCase $scenario -ExpectedExitCode 1
        Assert-Equal '' (Invoke-Git $result.Repository @('diff', '--cached', '--name-only')) `
            "$scenario must fail before staging."
        Assert-Equal 1 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
            "$scenario must not create a commit."
    }

    $result = Invoke-TestCase 'complete-no-changes'
    Assert-Equal 1 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
        'Completion without changes must not create an empty commit.'

    $result = Invoke-TestCase 'no-changes' -ExpectedExitCode 1
    Assert-True ($result.Output -match 'produced no changes') `
        'No changes without completion should fail clearly.'

    $result = Invoke-TestCase 'agent-failure' -ExpectedExitCode 1
    Assert-True ($result.Output -match 'controlled agent failure') `
        'Agent diagnostics should remain visible.'
    Assert-Equal 1 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
        'Agent failure must not create a commit.'

    $result = Invoke-TestCase 'stage-failure' -ExpectedExitCode 1
    Assert-True ($result.Output -match 'index.lock') 'The Git staging diagnostic was not surfaced.'
    Assert-True (Test-Path (Join-Path $result.Repository '.git\index.lock')) `
        'Ralph should preserve staging failure state.'
    Assert-True (Test-Path (Join-Path $result.Repository 'work.txt')) `
        'Ralph should preserve working-tree changes after staging failure.'

    $result = Invoke-TestCase 'commit-failure' -ExpectedExitCode 1 -Arrange {
        param($repository)
        Invoke-Git $repository @('config', 'user.name', '') | Out-Null
        Invoke-Git $repository @('config', 'user.email', '') | Out-Null
    }
    Assert-True ($result.Output -match 'empty ident|Author identity unknown') `
        "The Git commit diagnostic was not surfaced.`n$($result.Output)"
    Assert-True (
        -not [string]::IsNullOrWhiteSpace(
            (Invoke-Git $result.Repository @('diff', '--cached', '--name-only'))
        )
    ) 'Ralph should preserve staged state after commit failure.'
    Assert-True ($result.Output -notmatch 'Requested scope complete') `
        'Ralph reported completion after a failed commit.'

    $result = Invoke-TestCase 'archive-success' -Arrange {
        param($repository)
        New-Item -ItemType Directory -Path (
            Join-Path $repository '.scratch\unfinished\issues'
        ) -Force | Out-Null
        Set-Content -LiteralPath (
            Join-Path $repository '.scratch\feature\notes.txt'
        ) -Value 'feature-local content'
    }
    $archive = Join-Path $result.Repository '.scratch\done\feature'
    Assert-True (Test-Path -LiteralPath $archive -PathType Container) `
        'A newly completed feature was not moved into the done area.'
    Assert-True (-not (Test-Path -LiteralPath (
        Join-Path $result.Repository '.scratch\feature'
    ))) 'The completed feature remained active.'
    Assert-True (Test-Path -LiteralPath (Join-Path $archive 'spec.md') -PathType Leaf) `
        'Archival did not preserve the feature specification.'
    Assert-True (Test-Path -LiteralPath (Join-Path $archive 'issues\01.md') -PathType Leaf) `
        'Archival did not preserve the feature tickets.'
    Assert-True (Test-Path -LiteralPath (Join-Path $archive 'notes.txt') -PathType Leaf) `
        'Archival did not preserve other feature-local content.'
    Assert-True (Test-Path -LiteralPath (
        Join-Path $result.Repository '.scratch\unfinished'
    ) -PathType Container) 'Archival moved an unfinished feature.'

    $result = Invoke-TestCase 'promise-without-marker'
    Assert-True (Test-Path -LiteralPath (
        Join-Path $result.Repository '.scratch\feature'
    ) -PathType Container) 'A completion promise incorrectly archived the active feature.'
    Assert-True (-not (Test-Path -LiteralPath (
        Join-Path $result.Repository '.scratch\done'
    ))) 'A completion promise incorrectly created the done area.'

    foreach ($scenario in 'multiple-completions', 'missing-active-feature', 'unsafe-completion') {
        $result = Invoke-TestCase $scenario -ExpectedExitCode 1
        Assert-True (Test-Path -LiteralPath (
            Join-Path $result.Repository '.scratch\feature'
        ) -PathType Container) "$scenario moved an active feature before validation completed."
        Assert-Equal 1 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
            "$scenario must not create a commit."
    }

    $result = Invoke-TestCase 'existing-archive' -ExpectedExitCode 1 -Arrange {
        param($repository)
        New-Item -ItemType Directory -Path (
            Join-Path $repository '.scratch\done\feature'
        ) -Force | Out-Null
        Set-Content -LiteralPath (
            Join-Path $repository '.scratch\done\feature\existing.txt'
        ) -Value 'preserve'
    }
    Assert-True (Test-Path -LiteralPath (
        Join-Path $result.Repository '.scratch\feature'
    ) -PathType Container) 'An existing archive destination caused the source to move.'
    Assert-True (Test-Path -LiteralPath (
        Join-Path $result.Repository '.scratch\done\feature\existing.txt'
    ) -PathType Leaf) 'An existing archive destination was overwritten.'
    Assert-Equal 1 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
        'An existing archive destination must not create a commit.'

    $result = Invoke-TestCase 'discovery-excludes-done' -AutomaticDiscovery -Arrange {
        param($repository)
        New-Item -ItemType Directory -Path (
            Join-Path $repository '.scratch\done\archived\issues'
        ) -Force | Out-Null
    }
    $prompt = $result.AgentArguments -join "`n"
    Assert-True ($prompt -match [regex]::Escape('.scratch\feature\issues')) `
        'Automatic discovery did not include the active feature.'
    Assert-True ($prompt -notmatch [regex]::Escape('.scratch\done')) `
        'Automatic discovery included the done area.'

    Write-Host 'PASS: Invoke-Ralph end-to-end tests'
}
finally {
    $env:PATH = $originalPath
    if (Test-Path $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
