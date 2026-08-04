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

function Set-TestTicket {
    param(
        [string] $Path,
        [string] $Heading,
        [string] $Status = 'ready-for-agent'
    )

    Set-Content -LiteralPath $Path "$Heading`n`nStatus: $Status"
}

function New-TestRepository {
    param(
        [string] $Name,
        [switch] $ExistingProgress,
        [switch] $CompletedTicket,
        [switch] $LegacyTicketFilename,
        [switch] $FinalTicket,
        [switch] $ArchiveCollision,
        [switch] $SecondFeature
    )

    $repository = Join-Path $temporaryRoot $Name
    $issues = Join-Path $repository '.scratch\feature\issues'
    New-Item -ItemType Directory -Path $issues -Force | Out-Null
    Set-Content (Join-Path $repository '.gitignore') ".scratch/`n"
    Set-Content (Join-Path $repository 'baseline.txt') "baseline`n"
    Set-Content (Join-Path $repository '.scratch\feature\spec.md') '# Feature'
    $ticketName = if ($CompletedTicket -or $LegacyTicketFilename) { '01.done.md' } else { '01.md' }
    Set-TestTicket (Join-Path $issues $ticketName) '# Ticket' `
        $(if ($CompletedTicket) { 'done' } else { 'ready-for-agent' })
    if ($LegacyTicketFilename) {
        Set-Content (Join-Path $issues $ticketName) `
            "# Ticket`n`n**Status:** ready-for-agent"
    }
    if (-not $FinalTicket) {
        Set-TestTicket (Join-Path $issues '02.md') '# Later ticket'
    }
    if ($ArchiveCollision) {
        $existingArchive = Join-Path $repository '.scratch\done\feature'
        New-Item -ItemType Directory -Path $existingArchive -Force | Out-Null
        Set-Content (Join-Path $existingArchive 'preserve.txt') 'existing archive'
    }
    if ($SecondFeature) {
        $secondIssues = Join-Path $repository '.scratch\later-feature\issues'
        New-Item -ItemType Directory -Path $secondIssues -Force | Out-Null
        Set-Content (Join-Path $repository '.scratch\later-feature\spec.md') '# Later feature'
        Set-TestTicket (Join-Path $secondIssues '01.md') '# Later ticket'
    }
    if ($ExistingProgress) {
        Set-Content (Join-Path $repository '.scratch\progress.jsonl') (
            '{"feature":"previous","ticket":"00","changes":"done","checks":"passed"}'
        )
    }

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
        [switch] $ExistingProgress,
        [switch] $CompletedTicket,
        [switch] $LegacyTicketFilename,
        [switch] $FinalTicket,
        [switch] $ArchiveCollision,
        [switch] $SecondFeature,
        [switch] $BodyPositionedStatus,
        [ValidateSet('feature', 'automatic')]
        [string] $Scope = 'feature',
        [int] $Iterations = 1,
        [switch] $UseDefaultIterations,
        [string] $Scenario,
        [switch] $ForceInteractive,
        [string] $WorkboardDimensions,
        [string] $Model,
        [string] $Effort
    )

    $repository = New-TestRepository $Name -ExistingProgress:$ExistingProgress `
        -CompletedTicket:$CompletedTicket -LegacyTicketFilename:$LegacyTicketFilename `
        -FinalTicket:$FinalTicket `
        -ArchiveCollision:$ArchiveCollision -SecondFeature:$SecondFeature
    if ($BodyPositionedStatus) {
        Set-Content (Join-Path $repository '.scratch\feature\issues\01.md') @'
# Ticket

```md
Status: ready-for-agent
```

## Work

**Status:** ready-for-agent
'@
    }
    $agentDirectory = Join-Path $temporaryRoot "$Name.agent"
    $argumentLog = Join-Path $temporaryRoot "$Name.args"
    New-Item -ItemType Directory -Path $agentDirectory | Out-Null
    $fakeAgent = @'
param([Parameter(ValueFromRemainingArguments)] [string[]] $AgentArguments)
$ErrorActionPreference = 'Stop'
[System.IO.File]::WriteAllLines($env:RALPH_ARGUMENT_LOG, $AgentArguments)
$root = (& git rev-parse --show-toplevel).Trim()
$progress = Join-Path $root '.scratch\progress.jsonl'
$valid = '{"feature":"feature","ticket":"01","changes":"implemented","checks":"passed"}'

switch ($env:RALPH_SCENARIO) {
    'success' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
    }
    'legacy-filename-success' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress `
            '{"feature":"feature","ticket":"01.done","changes":"implemented","checks":"passed"}'
    }
    'malformed' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress '{bad json'
    }
    'missing-field' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress '{"feature":"feature","ticket":"01","changes":"implemented"}'
    }
    'empty-field' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress '{"feature":"feature","ticket":"01","changes":" ","checks":"passed"}'
    }
    'multiple' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
        Add-Content $progress $valid
    }
    'rewrite' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Set-Content $progress $valid
    }
    'nonexistent-feature' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress '{"feature":"missing","ticket":"01","changes":"implemented","checks":"passed"}'
    }
    'nonexistent-ticket' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress '{"feature":"feature","ticket":"99","changes":"implemented","checks":"passed"}'
    }
    'already-completed' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Set-Content (Join-Path $root '.scratch\feature\issues\01.md') `
            "# Ticket`n`nStatus: closed"
        Add-Content $progress $valid
    }
    'sequential' {
        $next = Get-ChildItem (Join-Path $root '.scratch') -Directory |
            Where-Object { $_.Name -cne 'done' } |
            Sort-Object Name |
            ForEach-Object {
                $ticket = Get-ChildItem (Join-Path $_.FullName 'issues') -File -Filter '*.md' |
                    Where-Object { (Get-Content -Raw $_.FullName) -match '(?im)^Status:\s*ready-for-agent\s*$' } |
                    Sort-Object Name |
                    Select-Object -First 1
                if ($ticket) {
                    [pscustomobject]@{ Feature = $_.Name; Ticket = $ticket.BaseName }
                }
            } |
            Select-Object -First 1
        Set-Content (Join-Path $root "work-$($next.Feature)-$($next.Ticket).txt") 'implemented'
        Add-Content $progress (
            [pscustomobject]@{
                feature = $next.Feature
                ticket = $next.Ticket
                changes = 'implemented'
                checks = 'passed'
            } | ConvertTo-Json -Compress
        )
    }
    'dynamic-feature' {
        $marker = Join-Path $root '.scratch\dynamic-feature-created.marker'
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
            $laterIssues = Join-Path $root '.scratch\later-feature\issues'
            New-Item -ItemType Directory -Path $laterIssues -Force | Out-Null
            Set-Content (Join-Path $root '.scratch\later-feature\spec.md') '# Later feature'
            Set-Content (Join-Path $laterIssues '01.md') "# Later ticket`n`nStatus: ready-for-agent"
            Set-Content $marker 'created'
            Set-Content (Join-Path $root 'work-1.txt') 'implemented'
            Add-Content $progress (
                [pscustomobject]@{
                    feature = 'feature'
                    ticket = '01'
                    changes = 'implemented'
                    checks = 'passed'
                } | ConvertTo-Json -Compress
            )
        }
        else {
            Set-Content (Join-Path $root 'work-2.txt') 'implemented'
            Add-Content $progress (
                [pscustomobject]@{
                    feature = 'later-feature'
                    ticket = '01'
                    changes = 'implemented'
                    checks = 'passed'
                } | ConvertTo-Json -Compress
            )
        }
    }
    'blank-output' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
    }
}

$message = 'iteration finished'
switch ($env:RALPH_SCENARIO) {
    'long-output' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
        $message = 'L' * 200
    }
    'wide-output' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
        $message = '漢' * 400
    }
    'line-ending-lf' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
        $message = "first agent line`n`nsecond agent line`n"
    }
    'line-ending-crlf' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
        $message = "first agent line`r`n`r`nsecond agent line`r`n"
    }
    'line-ending-cr' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
        $message = "first agent line`r`rsecond agent line`r"
    }
    'word-wrap-output' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
        $message = ('alpha ' * 60).TrimEnd()
    }
    'resize-output' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
        $message = @('before resize', ('R' * 100), 'unchanged size')
    }
    'blank-output' {
        $message = @('first line', '', '', '   ', 'second line', '', '', 'third line', '', '')
    }
    'typed-output' {
        Set-Content (Join-Path $root 'work.txt') 'implemented'
        Add-Content $progress $valid
        $message = "`e[31mtyped output `$('T' * 72)`e[0m"
    }
}
if ($AgentArguments -contains '--json') {
    foreach ($agentMessage in @($message)) {
        [pscustomobject]@{
            type = 'item.completed'
            item = [pscustomobject]@{ type = 'agent_message'; text = $agentMessage }
        } | ConvertTo-Json -Compress
    }
}
else {
    $message
}
'@
    foreach ($agentName in 'codex', 'copilot') {
        Set-Content (Join-Path $agentDirectory "$agentName.ps1") $fakeAgent
    }

    $env:PATH = "$agentDirectory;$originalPath"
    $env:RALPH_ARGUMENT_LOG = $argumentLog
    $env:RALPH_SCENARIO = if ($Scenario) {
        $Scenario
    }
    else {
        $Name -replace '^(codex|copilot)-', ''
    }
    if ($ForceInteractive) { $env:RALPH_FORCE_INTERACTIVE = '1' }
    if ($WorkboardDimensions) {
        $env:RALPH_TEST_WORKBOARD_DIMENSIONS = $WorkboardDimensions
    }
    try {
        Push-Location $repository
        $ralphArguments = @('-Agent', $Agent)
        if (-not $UseDefaultIterations) {
            $ralphArguments += @('-Iterations', $Iterations)
        }
        if ($Scope -eq 'feature') {
            $ralphArguments += @('-Feature', 'feature')
        }
        if ($PSBoundParameters.ContainsKey('Model')) {
            $ralphArguments += @('--model', $Model)
        }
        if ($PSBoundParameters.ContainsKey('Effort')) {
            $ralphArguments += @('--effort', $Effort)
        }
        $output = & pwsh -NoProfile -File $ralphScript @ralphArguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
        $env:PATH = $originalPath
        Remove-Item Env:RALPH_ARGUMENT_LOG, Env:RALPH_SCENARIO -ErrorAction SilentlyContinue
        Remove-Item Env:RALPH_FORCE_INTERACTIVE -ErrorAction SilentlyContinue
        Remove-Item Env:RALPH_TEST_WORKBOARD_DIMENSIONS -ErrorAction SilentlyContinue
    }

    Assert-Equal $ExpectedExitCode $exitCode (
        "$Name returned the wrong exit code.`n" +
        (($output | ForEach-Object { $_.ToString() }) -join "`n")
    )
    [pscustomobject]@{
        Repository = $repository
        Output = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        Arguments = @(Get-Content $argumentLog)
    }
}

try {
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

    foreach ($agent in 'codex', 'copilot') {
        $result = Invoke-TestCase "$agent-success" -Agent $agent
        Assert-Equal 'ralph: feature/01' (
            Invoke-Git $result.Repository @('log', '-1', '--format=%s')
        ) "$agent should use the deterministic tracker commit subject."
        Assert-Equal 2 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
            "$agent should create one iteration commit."
        Assert-True (Test-Path (
            Join-Path $result.Repository '.scratch\feature\issues\01.md'
        )) "$agent did not mark the ticket complete."
        Assert-True ((Get-Content -Raw (
            Join-Path $result.Repository '.scratch\feature\issues\01.md'
        )) -match '(?m)^Status: done\r?$') "$agent did not transition the ticket status."
        $paths = Invoke-Git $result.Repository @('show', '--pretty=', '--name-only', 'HEAD')
        Assert-True ($paths -match '(?m)^work\.txt$') 'Implementation was not committed.'
        Assert-True ($paths -match '(?m)^\.scratch/progress\.jsonl$') `
            'The ignored JSONL handoff was not committed.'
        Assert-True ($paths -match '(?m)^\.scratch/feature/issues/01\.md$') `
            'The Ralph-owned ticket status transition was not committed.'
        $record = Get-Content (
            Join-Path $result.Repository '.scratch\progress.jsonl'
        ) | Select-Object -Last 1 | ConvertFrom-Json
        Assert-Equal 'implemented' $record.changes 'The JSONL handoff was not preserved.'
        Assert-Equal '' (Invoke-Git $result.Repository @('status', '--porcelain')) `
            'Success should leave a clean worktree.'
        $prompt = $result.Arguments -join "`n"
        Assert-True ($prompt -match 'progress\.jsonl' -and $prompt -match '"feature"') `
            'The agent did not receive the JSONL handoff contract.'
        Assert-True ($prompt -match 'Do not modify ticket status') `
            'The prompt did not reserve ticket-state mutation for Ralph.'
        $expectedSummary = if ($agent -ceq 'codex') {
            'Agent: codex / gpt-5\.6-terra \(medium\)'
        }
        else {
            'Agent: copilot / auto'
        }
        Assert-True ($result.Output -match $expectedSummary) `
            "$agent did not report its consolidated agent summary."
        Assert-True ($result.Output -notmatch '(?m)^Model:') `
            "$agent emitted a standalone model line that should have been removed."
        Assert-True ($result.Output -notmatch 'Open tickets:') `
            "$agent emitted a standalone open-ticket line that should have been removed."
        $expectedModel = if ($agent -ceq 'codex') { 'gpt-5.6-terra' } else { 'auto' }
        Assert-True ($result.Arguments -contains '--model') `
            "$agent did not receive its default model option."
        Assert-Equal $expectedModel (
            $result.Arguments[($result.Arguments.IndexOf('--model') + 1)]
        ) "$agent did not receive its existing default model."
        if ($agent -ceq 'codex') {
            Assert-True ($result.Arguments -contains '--config') `
                'Codex did not receive its default reasoning-effort configuration.'
            Assert-True ($result.Arguments -contains 'model_reasoning_effort="medium"') `
                'Codex did not receive its existing default reasoning effort.'
        }
        else {
            Assert-True ($result.Arguments -notcontains '--effort') `
                'Copilot received an effort option when none was supplied.'
        }
    }

    foreach ($agent in 'codex', 'copilot') {
        $model = "test-$agent-model"
        $effort = "test-$agent-effort"
        $result = Invoke-TestCase "$agent-custom-options" -Agent $agent `
            -Model $model -Effort $effort -Scenario success
        Assert-True ($result.Arguments -contains '--model') `
            "$agent did not receive its custom model option."
        Assert-Equal $model (
            $result.Arguments[($result.Arguments.IndexOf('--model') + 1)]
        ) "$agent did not receive its custom model."
        if ($agent -ceq 'codex') {
            Assert-True ($result.Arguments -contains "model_reasoning_effort=`"$effort`"") `
                'Codex did not receive its custom reasoning-effort configuration.'
        }
        else {
            Assert-True ($result.Arguments -contains '--effort') `
                'Copilot did not receive its custom effort option.'
            Assert-Equal $effort (
                $result.Arguments[($result.Arguments.IndexOf('--effort') + 1)]
            ) 'Copilot did not receive its custom effort.'
        }
        Assert-True (
            $result.Output -match [regex]::Escape(
                "Agent: $agent / $model ($effort)"
            )
        ) "$agent did not report its custom effective configuration."
    }

    foreach ($option in 'model', 'effort') {
        $emptyOptionRepository = New-TestRepository "empty-$option"
        $emptyOptionLog = Join-Path $temporaryRoot "empty-$option.args"
        $env:RALPH_ARGUMENT_LOG = $emptyOptionLog
        Push-Location $emptyOptionRepository
        try {
            $emptyOptionOutput = & pwsh -NoProfile -File $ralphScript `
                -Agent codex "--$option" '' 2>&1
            $emptyOptionExitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
            Remove-Item Env:RALPH_ARGUMENT_LOG -ErrorAction SilentlyContinue
        }
        Assert-Equal 1 $emptyOptionExitCode "An empty --$option value should fail."
        Assert-True (
            (($emptyOptionOutput | ForEach-Object ToString) -join "`n") -match $option
        ) "An empty --$option value did not report parameter validation."
        Assert-True (-not (Test-Path -LiteralPath $emptyOptionLog)) `
            "An empty --$option value invoked an agent."
    }

    $bodyPositionedResult = Invoke-TestCase 'body-positioned-status' `
        -BodyPositionedStatus -Scenario success
    $bodyPositionedTicket = Get-Content -Raw (
        Join-Path $bodyPositionedResult.Repository '.scratch\feature\issues\01.md'
    )
    Assert-True ($bodyPositionedTicket -match '(?m)^```md\r?\nStatus: ready-for-agent\r?\n```\r?$') `
        'Completion changed a Status example inside a fenced code block.'
    Assert-True ($bodyPositionedTicket -match '(?m)^\*\*Status:\*\* done\r?$') `
        'Completion did not update the body-positioned Status declaration in place.'

    $result = Invoke-TestCase 'legacy-filename-success' -LegacyTicketFilename `
        -Scenario legacy-filename-success
    Assert-True (Test-Path (
        Join-Path $result.Repository '.scratch\feature\issues\01.done.md'
    )) 'A legacy-looking ticket filename was changed during completion.'
    Assert-True ((Get-Content -Raw (
        Join-Path $result.Repository '.scratch\feature\issues\01.done.md'
    )) -match '(?m)^\*\*Status:\*\* done\r?$') `
        'A ready legacy-looking ticket did not transition to done while preserving label style.'

    $result = Invoke-TestCase 'default-iterations' -Scenario sequential `
        -UseDefaultIterations
    Assert-True ($result.Output -match 'Iteration 1 of 32') `
        'An omitted iteration limit did not default to 32.'
    Assert-True ($result.Output -notmatch 'Open tickets:') `
        'The default-limit run emitted a standalone open-ticket line.'

    $result = Invoke-TestCase 'explicit-iterations' -Scenario sequential `
        -Iterations 7
    Assert-True ($result.Output -match 'Iteration 1 of 7') `
        'An explicit iteration limit was not preserved.'

    $result = Invoke-TestCase 'existing-progress-success' -ExistingProgress -Scenario success
    $records = @(Get-Content (Join-Path $result.Repository '.scratch\progress.jsonl'))
    Assert-Equal 2 $records.Count 'A valid record was not appended to existing history.'

    foreach ($case in @(
        @('malformed', 'not valid JSON'),
        @('missing-field', "requires a non-empty string 'checks'"),
        @('empty-field', "requires a non-empty string 'changes'"),
        @('multiple', 'exactly one JSONL record'),
        @('rewrite', 'must only append'),
        @('nonexistent-feature', 'does not match requested feature'),
        @('nonexistent-ticket', 'Unfinished tracker ticket not found')
    )) {
        $result = Invoke-TestCase $case[0] -ExpectedExitCode 1 -ExistingProgress
        Assert-True ($result.Output -match [regex]::Escape($case[1])) `
            "$($case[0]) did not report the expected validation failure."
        Assert-Equal 1 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
            "$($case[0]) must not create a commit."
        Assert-Equal '' (Invoke-Git $result.Repository @('diff', '--cached', '--name-only')) `
            "$($case[0]) must fail before staging."
    }

    $result = Invoke-TestCase 'already-completed' -ExpectedExitCode 1 `
        -ExistingProgress
    Assert-True ($result.Output -match 'already completed') `
        'An already-completed ticket was not rejected.'
    Assert-Equal 1 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
        'An already-completed ticket must not create a commit.'

    $result = Invoke-TestCase 'final-ticket' -FinalTicket -Scenario success
    Assert-Equal 'ralph: feature/01, FEATURE completed' (
        Invoke-Git $result.Repository @('log', '-1', '--format=%s')
    ) 'The final-ticket commit subject did not identify feature completion.'
    Assert-True (-not (Test-Path (
        Join-Path $result.Repository '.scratch\feature'
    ))) 'The completed feature remained active.'
    Assert-True (Test-Path (
        Join-Path $result.Repository '.scratch\done\feature\spec.md'
    )) 'The archived feature did not preserve its specification.'
    Assert-True (Test-Path (
        Join-Path $result.Repository '.scratch\done\feature\issues\01.md'
    )) 'The archived feature did not preserve its completed ticket.'
    $paths = Invoke-Git $result.Repository @('show', '--pretty=', '--name-only', 'HEAD')
    Assert-True ($paths -match '(?m)^\.scratch/done/feature/spec\.md$') `
        'The archived specification was not committed.'
    Assert-True ($paths -match '(?m)^\.scratch/done/feature/issues/01\.md$') `
        'The archived ticket history was not committed.'

    $result = Invoke-TestCase 'archive-collision' -FinalTicket -ArchiveCollision `
        -Scenario success
    Assert-True (Test-Path (
        Join-Path $result.Repository '.scratch\done\feature\preserve.txt'
    )) 'An existing archive was overwritten.'
    Assert-True (Test-Path (
        Join-Path $result.Repository '.scratch\done\feature-2\spec.md'
    )) 'The collision archive did not use the next numeric suffix.'
    Assert-Equal 'ralph: feature/01, FEATURE completed' (
        Invoke-Git $result.Repository @('log', '-1', '--format=%s')
    ) 'Archive suffixing changed the original feature identity in the commit.'
    $record = Get-Content (
        Join-Path $result.Repository '.scratch\progress.jsonl'
    ) | Select-Object -Last 1 | ConvertFrom-Json
    Assert-Equal 'feature' $record.feature `
        'Archive suffixing changed the original feature identity in the log.'

    $result = Invoke-TestCase 'feature-scope' -Scenario sequential -Iterations 3
    Assert-True (Test-Path (
        Join-Path $result.Repository '.scratch\done\feature\issues\02.md'
    )) 'Feature scope did not continue through archival.'
    Assert-Equal 3 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
        'Feature scope should commit both unfinished tickets.'
    Assert-True (($result.Arguments -join "`n") -notmatch '<promise>COMPLETE</promise>') `
        'The feature prompt retained the completion-promise protocol.'
    Assert-True (($result.Arguments -join "`n") -match "selected feature 'feature'") `
        'The feature prompt did not identify the selected feature by folder name.'

    $parameterRepository = New-TestRepository 'feature-parameter'
    New-Item -ItemType Directory -Path (
        Join-Path $parameterRepository '.scratch\no-spec\issues'
    ) -Force | Out-Null
    New-Item -ItemType Directory -Path (
        Join-Path $parameterRepository '.scratch\done\archived\issues'
    ) -Force | Out-Null
    Set-Content (Join-Path $parameterRepository '.scratch\done\archived\spec.md') '# Archived'
    $command = Get-Command $ralphScript
    Assert-True ($command.Parameters.ContainsKey('Feature')) `
        'The Ralph command does not expose -Feature.'
    Assert-True (-not $command.Parameters.ContainsKey('TaskFile')) `
        'The removed -TaskFile parameter remains public.'
    $completer = @(
        $command.Parameters.Feature.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
    )[0]
    Push-Location $parameterRepository
    try {
        $completionNames = @(
            & $completer.ScriptBlock 'Invoke-Ralph.ps1' 'Feature' '' $null @{} |
                ForEach-Object { $_.CompletionText }
        )
    }
    finally {
        Pop-Location
    }
    Assert-Equal 'feature' ($completionNames -join ',') `
        'Feature completion included archived, nested, or specification-free folders.'

    Assert-True ($command.Parameters.ContainsKey('Archive')) `
        'The Ralph command does not expose -Archive.'
    $archiveCompleter = @(
        $command.Parameters.Archive.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
    )[0]
    Push-Location $parameterRepository
    try {
        $archiveCompletionNames = @(
            & $archiveCompleter.ScriptBlock 'Invoke-Ralph.ps1' 'Archive' '' $null @{} |
                ForEach-Object { $_.CompletionText }
        )
    }
    finally {
        Pop-Location
    }
    Assert-Equal 'feature' ($archiveCompletionNames -join ',') `
        'Archive completion included archived, nested, or specification-free folders.'

    foreach ($invalidFeature in @(
        '.scratch/feature/spec.md',
        'archived',
        'no-spec'
    )) {
        Push-Location $parameterRepository
        try {
            $invalidOutput = & pwsh -NoProfile -File $ralphScript `
                -Feature $invalidFeature 2>&1
            $invalidExitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        Assert-Equal 1 $invalidExitCode `
            "Invalid feature '$invalidFeature' should be rejected."
        Assert-True ((($invalidOutput | ForEach-Object ToString) -join "`n") -match 'Feature') `
            "Invalid feature '$invalidFeature' did not report feature validation."
    }

    foreach ($invalidArchive in @(
        '.scratch/feature/spec.md',
        'archived',
        'no-spec'
    )) {
        Push-Location $parameterRepository
        try {
            $invalidOutput = & pwsh -NoProfile -File $ralphScript `
                -Archive $invalidArchive 2>&1
            $invalidExitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        Assert-Equal 1 $invalidExitCode `
            "Invalid archive '$invalidArchive' should be rejected."
        Assert-True ((($invalidOutput | ForEach-Object ToString) -join "`n") -match 'Archive') `
            "Invalid archive '$invalidArchive' did not report archive validation."
    }

    $manualArchiveRepository = New-TestRepository 'manual-archive' -ExistingProgress
    $manualArchiveProgressPath = Join-Path $manualArchiveRepository '.scratch\progress.jsonl'
    [byte[]] $manualArchiveProgressBefore = [System.IO.File]::ReadAllBytes(
        $manualArchiveProgressPath
    )
    Push-Location $manualArchiveRepository
    try {
        $manualArchiveOutput = & pwsh -NoProfile -File $ralphScript -Archive feature 2>&1
        $manualArchiveExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $manualArchiveText = ($manualArchiveOutput | ForEach-Object { $_.ToString() }) -join "`n"
    Assert-Equal 0 $manualArchiveExitCode "Manual archive failed.`n$manualArchiveText"
    Assert-True ($manualArchiveText -match [regex]::Escape("Archived feature 'feature' to:")) `
        'Manual archive did not report its destination.'
    Assert-True (-not (Test-Path (
        Join-Path $manualArchiveRepository '.scratch\feature'
    ))) 'Manual archive retained the active feature.'
    Assert-True (Test-Path (
        Join-Path $manualArchiveRepository '.scratch\done\feature\spec.md'
    )) 'Manual archive did not preserve its specification.'
    Assert-True (Test-Path (
        Join-Path $manualArchiveRepository '.scratch\done\feature\issues\02.md'
    )) 'Manual archive did not preserve unfinished tickets.'
    Assert-True ((Get-Content -Raw (
        Join-Path $manualArchiveRepository '.scratch\done\feature\issues\01.md'
    )) -match 'ready-for-agent') 'Manual archive changed an unfinished ticket status.'
    [byte[]] $manualArchiveProgressAfter = [System.IO.File]::ReadAllBytes(
        $manualArchiveProgressPath
    )
    Assert-Equal ([Convert]::ToBase64String($manualArchiveProgressBefore)) (
        [Convert]::ToBase64String($manualArchiveProgressAfter)
    ) 'Manual archive invoked an agent or changed tracker progress.'
    Assert-Equal 1 (Invoke-Git $manualArchiveRepository @(
        'rev-list', '--all', '--count'
    )) 'Manual archive created a commit.'

    $manualCollisionRepository = New-TestRepository 'manual-archive-collision' `
        -ArchiveCollision
    Push-Location $manualCollisionRepository
    try {
        $manualCollisionOutput = & pwsh -NoProfile -File $ralphScript `
            -Archive feature 2>&1
        $manualCollisionExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    Assert-Equal 0 $manualCollisionExitCode (
        "Manual collision archive failed.`n" +
        (($manualCollisionOutput | ForEach-Object { $_.ToString() }) -join "`n")
    )
    Assert-True (Test-Path (
        Join-Path $manualCollisionRepository '.scratch\done\feature\preserve.txt'
    )) 'Manual archive overwrote an existing archive.'
    Assert-True (Test-Path (
        Join-Path $manualCollisionRepository '.scratch\done\feature-2\spec.md'
    )) 'Manual archive did not use the next numeric collision suffix.'

    foreach ($incompatible in @(
        @{ Arguments = @('-List'); Name = 'List' },
        @{ Arguments = @('-Cleanup'); Name = 'Cleanup' },
        @{ Arguments = @('-Agent', 'copilot'); Name = 'Agent' },
        @{ Arguments = @('-Iterations', '2'); Name = 'Iterations' },
        @{ Arguments = @('-Feature', 'feature'); Name = 'Feature' }
    )) {
        $incompatibleRepository = New-TestRepository "manual-archive-$($incompatible.Name)"
        Push-Location $incompatibleRepository
        try {
            $incompatibleOutput = & pwsh -NoProfile -File $ralphScript -Archive feature `
                @($incompatible.Arguments) 2>&1
            $incompatibleExitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        $incompatibleText = (
            $incompatibleOutput | ForEach-Object { $_.ToString() }
        ) -join "`n"
        Assert-Equal 1 $incompatibleExitCode (
            "-Archive with $($incompatible.Name) should fail.`n$incompatibleText"
        )
        Assert-True (
            $incompatibleText -match [regex]::Escape(
                "-Archive cannot be combined with: $($incompatible.Name)."
            )
        ) "-Archive did not clearly reject $($incompatible.Name)."
    }

    $result = Invoke-TestCase 'automatic-scope' -Scope automatic -Scenario sequential `
        -Iterations 5 -SecondFeature
    Assert-True (Test-Path (
        Join-Path $result.Repository '.scratch\done\feature\spec.md'
    )) 'Automatic scope did not archive the first active feature.'
    Assert-True (Test-Path (
        Join-Path $result.Repository '.scratch\done\later-feature\spec.md'
    )) 'Automatic scope did not continue to the next active feature.'
    Assert-Equal 4 (Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD')) `
        'Automatic scope should commit all three unfinished tickets.'
    Assert-True ($result.Output -match 'Requested scope complete') `
        'Automatic scope did not finish from active tracker state.'
    Assert-True ($result.Output -notmatch 'Open tickets:') `
        'Automatic scope emitted a standalone open-ticket line.'
    $lastAutomaticPrompt = $result.Arguments -join "`n"
    Assert-True ($lastAutomaticPrompt -match '\.scratch[\\/]later-feature[\\/]issues') `
        'Automatic discovery omitted the remaining active feature.'
    Assert-True ($lastAutomaticPrompt -notmatch '(?m)^\.scratch[\\/]feature[\\/]issues$') `
        'Automatic discovery retained an archived feature in a later prompt.'

    $listRepository = Join-Path $temporaryRoot 'list'
    New-Item -ItemType Directory -Path (
        Join-Path $listRepository '.scratch\alpha-feature\issues'
    ) -Force | Out-Null
    New-Item -ItemType Directory -Path (
        Join-Path $listRepository '.scratch\zeta-feature\issues'
    ) -Force | Out-Null
    New-Item -ItemType Directory -Path (
        Join-Path $listRepository '.scratch\done\archived-feature\issues'
    ) -Force | Out-Null
    Set-Content (Join-Path $listRepository '.scratch\alpha-feature\spec.md') `
        '# Alpha display name'
    Set-Content (Join-Path $listRepository '.scratch\zeta-feature\spec.md') `
        '# Zeta display name'
    Set-TestTicket (
        Join-Path $listRepository '.scratch\alpha-feature\issues\10-later.md'
    ) '# Tenth ticket'
    Set-TestTicket (
        Join-Path $listRepository '.scratch\alpha-feature\issues\2-sooner.md'
    ) '# Second ticket'
    Set-TestTicket (
        Join-Path $listRepository '.scratch\alpha-feature\issues\01-finished.done.md'
    ) '# Finished ticket' 'done'
    Set-TestTicket (
        Join-Path $listRepository '.scratch\zeta-feature\issues\01-zeta.md'
    ) '# Zeta ticket'
    Set-Content (
        Join-Path $listRepository '.scratch\done\archived-feature\spec.md'
    ) '# Must not appear'
    Set-Content (Join-Path $listRepository '.gitignore') ".scratch/`n"
    Set-Content (Join-Path $listRepository 'baseline.txt') 'baseline'
    Invoke-Git $listRepository @('init', '--quiet') | Out-Null
    $resolvedListRepository = Invoke-Git $listRepository @(
        'rev-parse',
        '--show-toplevel'
    )
    Push-Location $listRepository
    try {
        $listOutput = & pwsh -NoProfile -File $ralphScript -List 2>&1
        $listExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $listText = ($listOutput | ForEach-Object { $_.ToString() }) -join "`n"
    $listText = $listText -replace "$([char]27)\[[0-9;]*m", ''
    Assert-Equal 0 $listExitCode "List mode failed.`n$listText"
    Assert-True ($listText -notmatch '\s*(active|open|complete)\b') `
        'List mode emitted a retired tracker status pill.'
    Assert-True ($listText -match 'Alpha display name.*alpha-feature') `
        'List mode omitted the feature heading or stable slug.'
    Assert-True ($listText -match '\[ \] Second ticket') `
        'List mode omitted an unfinished ticket heading.'
    Assert-True ($listText -match '\[✓\] Finished ticket') `
        'List mode did not mark the completed ticket.'
    Assert-True ($listText -notmatch '2-sooner\.md|10-later\.md|01-finished\.done\.md') `
        'List mode exposed ticket filenames.'
    Assert-True (
        $listText.IndexOf('Alpha display name') -lt $listText.IndexOf('Zeta display name')
    ) 'List mode did not sort features by slug.'
    Assert-True (
        $listText.IndexOf('Finished ticket') -lt $listText.IndexOf('Second ticket') -and
        $listText.IndexOf('Second ticket') -lt $listText.IndexOf('Tenth ticket')
    ) 'List mode did not preserve natural ticket order regardless of completion state.'
    Assert-True ($listText -notmatch 'Must not appear|archived-feature') `
        'List mode included an archived feature.'
    Assert-True ($listText -match '├─|└─') `
        'List mode omitted the readable terminal hierarchy.'
    Assert-True ($listText -match (
        'Repository:\s+' + [regex]::Escape($resolvedListRepository)
    )) 'List mode did not display the resolved repository-root path.'
    Assert-True ($listText -notmatch 'Iteration:') `
        'List mode emitted irrelevant iteration metadata.'
    Assert-True ($listText -notmatch 'Progress:') `
        'List mode emitted a standalone Progress: metadata row that should have been removed.'
    Assert-True ($listText -notmatch '(?m)^Agent:') `
        'List mode emitted a standalone Agent: metadata row that should have been removed.'

    $statusRepository = Join-Path $temporaryRoot 'ticket-status-list'
    $statusIssues = Join-Path $statusRepository '.scratch\status-feature\issues'
    New-Item -ItemType Directory -Path $statusIssues -Force | Out-Null
    Set-Content (Join-Path $statusRepository '.scratch\status-feature\spec.md') `
        '# Ticket status feature'
    Set-Content (Join-Path $statusIssues '01-ordinary.done.md') `
        "# Ordinary legacy filename`n`nStatus: ready-for-agent"
    Set-Content (Join-Path $statusIssues '02-bold.md') `
        "# Bold terminal`n`n**STATUS:** DONE"
    Set-Content (Join-Path $statusIssues '03-list.md') `
        "# List terminal`n`n- Status: closed"
    Set-Content (Join-Path $statusIssues '04-quote.md') `
        "# Quote ready`n`n> Status: READY-FOR-AGENT"
    Set-Content (Join-Path $statusIssues '05-body-positioned.md') @"
# Body-positioned status

## Work

Status-like prose must not be treated as a declaration.

**Status:** ready-for-agent
"@
    Invoke-Git $statusRepository @('init', '--quiet') | Out-Null
    Push-Location $statusRepository
    try {
        $statusOutput = & pwsh -NoProfile -File $ralphScript -List 2>&1
        $statusExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $statusText = ($statusOutput | ForEach-Object ToString) -join "`n"
    $statusText = $statusText -replace "$([char]27)\[[0-9;]*m", ''
    Assert-Equal 0 $statusExitCode "Status-aware list failed.`n$statusText"
    Assert-True ($statusText -match '\[ \] Ordinary legacy filename') `
        'A .done.md filename was incorrectly treated as terminal.'
    Assert-True ($statusText -match '\[✓\] Bold terminal') `
        'Bold, case-insensitive done metadata was not terminal.'
    Assert-True ($statusText -match '\[✓\] List terminal') `
        'List-prefixed closed metadata was not terminal.'
    Assert-True ($statusText -match '\[ \] Quote ready') `
        'Quote-prefixed ready metadata was not unfinished.'
    Assert-True ($statusText -match '\[ \] Body-positioned status') `
        'A valid status after ordinary ticket content was not recognized.'

    foreach ($invalidStatusCase in @(
        @{ Name = 'missing'; Content = "# Missing status"; Error = 'missing' },
        @{ Name = 'duplicate'; Content = "# Duplicate`n`nStatus: done`nStatus: closed"; Error = 'exactly one' },
        @{ Name = 'malformed'; Content = "# Malformed`n`nStatus = done"; Error = 'malformed' },
        @{ Name = 'unsupported'; Content = "# Unsupported`n`nStatus: in-progress"; Error = 'unsupported' },
        @{ Name = 'fenced-only'; Content = "# Fenced only`n`n" + '```md' + "`nStatus: done`n" + '```'; Error = 'missing' }
    )) {
        $invalidRepository = Join-Path $temporaryRoot "status-$($invalidStatusCase.Name)"
        $invalidIssues = Join-Path $invalidRepository '.scratch\feature\issues'
        New-Item -ItemType Directory -Path $invalidIssues -Force | Out-Null
        Set-Content (Join-Path $invalidRepository '.scratch\feature\spec.md') '# Feature'
        Set-Content (Join-Path $invalidIssues '01.md') $invalidStatusCase.Content
        Invoke-Git $invalidRepository @('init', '--quiet') | Out-Null
        Push-Location $invalidRepository
        try {
            $invalidOutput = & pwsh -NoProfile -File $ralphScript -List 2>&1
            $invalidExitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        $invalidText = ($invalidOutput | ForEach-Object ToString) -join "`n"
        Assert-Equal 1 $invalidExitCode `
            "$($invalidStatusCase.Name) ticket status should fail.`n$invalidText"
        Assert-True ($invalidText -match $invalidStatusCase.Error) `
            "$($invalidStatusCase.Name) ticket status did not report the expected error."
    }

    $partialListRepository = Join-Path $temporaryRoot 'partial-list'
    New-Item -ItemType Directory -Path (
        Join-Path $partialListRepository '.scratch\missing-everything'
    ) -Force | Out-Null
    New-Item -ItemType Directory -Path (
        Join-Path $partialListRepository '.scratch\partial\issues'
    ) -Force | Out-Null
    Set-Content (Join-Path $partialListRepository '.scratch\partial\spec.md') `
        'Specification without a heading'
    Set-Content (
        Join-Path $partialListRepository '.scratch\partial\issues\01.md'
    ) "Status: ready-for-agent`n`nTicket without a heading"
    Set-Content (Join-Path $partialListRepository '.gitignore') ".scratch/`n"
    Set-Content (Join-Path $partialListRepository 'dirty.txt') 'initial'
    Invoke-Git $partialListRepository @('init', '--quiet') | Out-Null
    Set-Content (Join-Path $partialListRepository 'dirty.txt') 'unstaged change'
    try {
        Push-Location $partialListRepository
        $partialListOutput = & pwsh -NoProfile -File $ralphScript -List 2>&1
        $partialListExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $partialListText = (
        $partialListOutput | ForEach-Object { $_.ToString() }
    ) -join "`n"
    $partialListText = $partialListText -replace "$([char]27)\[[0-9;]*m", ''
    Assert-Equal 0 $partialListExitCode (
        "Partial list mode failed without an agent or clean worktree.`n$partialListText"
    )
    Assert-True ($partialListText -match 'missing-everything.*missing-everything') `
        'List mode did not fall back for a missing specification and issue directory.'
    Assert-True ($partialListText -match '└─ no tickets') `
        'List mode did not render the missing issue-directory fallback.'
    Assert-True ($partialListText -match 'partial.*partial') `
        'List mode did not fall back for a specification without a heading.'
    Assert-True ($partialListText -match '\[ \] 01\b') `
        'List mode did not fall back for a ticket without a heading.'
    Assert-True ($partialListText -notmatch '01\.md') `
        'List mode exposed a ticket filename in fallback output.'
    Assert-Equal 'unstaged change' (
        Get-Content (Join-Path $partialListRepository 'dirty.txt') -Raw
    ).Trim() 'List mode changed dirty working-tree content.'
    Assert-True (-not (Test-Path (
        Join-Path $partialListRepository '.scratch\progress.jsonl'
    ))) 'List mode created tracker state.'
    Assert-Equal '0' (Invoke-Git $partialListRepository @(
        'rev-list', '--all', '--count'
    )) `
        'List mode created a commit.'

    Push-Location $listRepository
    try {
        $cleanupFeatureOutput = & pwsh -NoProfile -File $ralphScript `
            -Cleanup -Feature alpha-feature 2>&1
        $cleanupFeatureExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $cleanupFeatureText = (
        $cleanupFeatureOutput | ForEach-Object { $_.ToString() }
    ) -join "`n"
    Assert-Equal 1 $cleanupFeatureExitCode `
        "-Cleanup with Feature should fail.`n$cleanupFeatureText"
    Assert-True (
        $cleanupFeatureText -match [regex]::Escape(
            '-Cleanup cannot be combined with: Feature.'
        )
    ) '-Cleanup did not clearly reject Feature.'

    $emptyListRepository = Join-Path $temporaryRoot 'empty-list'
    New-Item -ItemType Directory -Path (
        Join-Path $emptyListRepository '.scratch\done\archived'
    ) -Force | Out-Null
    Set-Content (Join-Path $emptyListRepository 'baseline.txt') 'baseline'
    Invoke-Git $emptyListRepository @('init', '--quiet') | Out-Null
    Push-Location $emptyListRepository
    try {
        $emptyListOutput = & pwsh -NoProfile -File $ralphScript -List 2>&1
        $emptyListExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $emptyListText = ($emptyListOutput | ForEach-Object { $_.ToString() }) -join "`n"
    $emptyListText = $emptyListText -replace "$([char]27)\[[0-9;]*m", ''
    Assert-Equal 0 $emptyListExitCode "Empty list mode failed.`n$emptyListText"
    Assert-True ($emptyListText -match 'No active features\.') `
        'List mode omitted its successful empty-state message.'

    foreach ($incompatible in @(
        @{ Arguments = @('-Cleanup'); Name = 'Cleanup' },
        @{ Arguments = @('-Agent', 'copilot'); Name = 'Agent' },
        @{ Arguments = @('-Iterations', '2'); Name = 'Iterations' },
        @{
            Arguments = @(
                '-Feature',
                'alpha-feature'
            )
            Name = 'Feature'
        }
    )) {
        Push-Location $listRepository
        try {
            $incompatibleOutput = & pwsh -NoProfile -File $ralphScript -List `
                @($incompatible.Arguments) 2>&1
            $incompatibleExitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        $incompatibleText = (
            $incompatibleOutput | ForEach-Object { $_.ToString() }
        ) -join "`n"
        Assert-Equal 1 $incompatibleExitCode (
            "-List with $($incompatible.Name) should fail.`n$incompatibleText"
        )
        Assert-True (
            $incompatibleText -match [regex]::Escape(
                "-List cannot be combined with: $($incompatible.Name)."
            )
        ) "-List did not clearly reject $($incompatible.Name)."
    }

    $cleanupRepository = New-TestRepository 'cleanup' -ExistingProgress `
        -ArchiveCollision
    $progressPath = Join-Path $cleanupRepository '.scratch\progress.jsonl'
    [byte[]] $beforeCleanup = [System.IO.File]::ReadAllBytes($progressPath)
    Push-Location $cleanupRepository
    try {
        $cleanupOutput = & pwsh -NoProfile -File $ralphScript -Cleanup 2>&1
        $cleanupExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    Assert-Equal 0 $cleanupExitCode (
        "Cleanup failed.`n" + (($cleanupOutput | ForEach-Object { $_.ToString() }) -join "`n")
    )
    Assert-True (-not (Test-Path (
        Join-Path $cleanupRepository '.scratch\done\feature'
    ))) 'Cleanup retained an archived feature directory.'
    Assert-True (Test-Path (
        Join-Path $cleanupRepository '.scratch\feature'
    )) 'Cleanup removed active feature work.'
    [byte[]] $afterCleanup = [System.IO.File]::ReadAllBytes($progressPath)
    Assert-Equal ([Convert]::ToBase64String($beforeCleanup)) (
        [Convert]::ToBase64String($afterCleanup)
    ) 'Cleanup changed the append-only JSONL audit log.'

    # Non-interactive safety: redirected output must not emit cursor-control sequences
    # that would corrupt a log or pipe.
    $result = Invoke-TestCase 'noninteractive-safe' -Scenario success
    $rawOutput = $result.Output
    Assert-True ($rawOutput -notmatch "`e\[2J") `
        'Non-interactive run emitted a clear-screen sequence.'
    Assert-True ($rawOutput -notmatch "`e\[\d+;\d+r") `
        'Non-interactive run emitted a scroll-region setup sequence.'
    Assert-True ($rawOutput -notmatch "`e\[\?25l") `
        'Non-interactive run emitted a cursor-hide sequence.'
    Assert-True ($rawOutput -notmatch "`e\[\?25h") `
        'Non-interactive run emitted a cursor-show sequence.'

    # Interactive workboard: RALPH_FORCE_INTERACTIVE=1 simulates an ANSI-capable terminal.
    # The tracker must be drawn and the scroll region restored on exit.
    $result = Invoke-TestCase 'interactive-workboard' -ForceInteractive -Scenario success
    $rawInteractive = $result.Output
    Assert-True ($rawInteractive -match 'Ralph tracker') `
        'Interactive run did not draw the tracker workboard.'
    Assert-True (
        $rawInteractive.IndexOf('Ralph tracker') -lt $rawInteractive.IndexOf('Iteration 1')
    ) 'Interactive run drew the tracker after iteration output, not before.'
    Assert-True ($rawInteractive -match "`e\[2J") `
        'Interactive run did not clear the screen before the workboard.'
    Assert-True ($rawInteractive -match "`e\[r") `
        'Interactive run did not restore the scroll region on exit.'
    # Panel structure: tracker must be inside a full-width rounded panel.
    Assert-True ($rawInteractive -match [regex]::Escape('╭')) `
        'Interactive run did not draw the rounded panel top-left corner.'
    Assert-True ($rawInteractive -match [regex]::Escape('╰')) `
        'Interactive run did not draw the rounded panel bottom-left corner.'
    Assert-True ($rawInteractive -match 'Agent output') `
        'Interactive run did not draw the Agent output panel label.'
    Assert-True ($rawInteractive -match "`e\[2m") `
        'Interactive run did not use dim styling for panel borders.'
    Assert-True (([regex]::Matches($rawInteractive, [regex]::Escape('╭')).Count -ge 2)) `
        'Interactive run did not draw two rounded panel top borders.'
    Assert-True (([regex]::Matches($rawInteractive, [regex]::Escape('╰')).Count -ge 2)) `
        'Interactive run did not draw two rounded panel bottom borders.'
    Assert-True ($rawInteractive -notmatch '\s*(active|open|complete)\b') `
        'Interactive run emitted a retired tracker status pill.'
    Assert-True ($rawInteractive -match 'Repository:' -and $rawInteractive -match 'Iteration:' -and
        $rawInteractive -match '1 of 1') `
        'Interactive run did not render tracker metadata rows.'
    Assert-True ($rawInteractive -notmatch 'Progress:') `
        'Interactive run emitted a standalone Progress: metadata row.'
    Assert-True ($rawInteractive -match (
        'Repository:.*\x1b\[2;38;5;8mcodex / gpt-5\.6-terra \(medium\)'
    )) 'Interactive run did not render the dim agent summary on the repository row.'
    # "Ralph tracker" label appears within the top border, content rows below it.
    Assert-True (
        $rawInteractive.IndexOf('╭') -lt $rawInteractive.IndexOf('Ralph tracker')
    ) 'Panel top-left corner must precede the Ralph tracker label.'
    Assert-True (
        $rawInteractive.IndexOf('Ralph tracker') -lt $rawInteractive.IndexOf('╰')
    ) 'Ralph tracker label must precede the panel bottom-left corner.'
    Assert-True (
        $rawInteractive.IndexOf('Ralph tracker') -lt $rawInteractive.IndexOf('Agent output')
    ) 'Agent output panel must render below the tracker panel.'
    Assert-True (
        $rawInteractive.IndexOf('Repository:') -lt $rawInteractive.IndexOf('Agent output')
    ) 'Session metadata should render inside the tracker panel.'
    Assert-True ($rawInteractive -notmatch 'Ralph tracker\s+\d+ active feature') `
        'Interactive run retained the duplicate body title in the tracker.'
    Assert-True (
        $rawInteractive.IndexOf('╰') -lt $rawInteractive.IndexOf('Iteration 1')
    ) 'Panel bottom border must precede iteration output.'
    # Cursor lifecycle: workboard must hide the cursor on entry and show it on exit,
    # and cursor-show must appear after the scroll-region restore sequence.
    Assert-True ($rawInteractive -match "`e\[\?25l") `
        'Interactive run did not hide the cursor when the workboard started.'
    Assert-True ($rawInteractive -match "`e\[\?25h") `
        'Interactive run did not show the cursor after workboard teardown.'
    Assert-True (
        $rawInteractive.IndexOf("`e[?25l") -lt $rawInteractive.IndexOf("`e[?25h")
    ) 'Interactive run: cursor-hide must precede cursor-show.'
    Assert-True (
        $rawInteractive.LastIndexOf("`e[r") -lt $rawInteractive.IndexOf("`e[?25h")
    ) 'Interactive run: cursor-show must appear after the scroll-region restore.'

    # Interactive workboard cleanup on failure: terminal must be restored even when
    # the agent produces a validation error.
    $failResult = Invoke-TestCase 'interactive-workboard-failure' `
        -ForceInteractive -Scenario malformed -ExpectedExitCode 1
    Assert-True ($failResult.Output -match "`e\[r") `
        'Interactive run did not restore the scroll region after a failure.'
    Assert-True ($failResult.Output -match "`e\[\?25h") `
        'Interactive run did not make the cursor visible after a failure.'

    # Startup-feature retention: a feature that was active at the start of the run
    # must remain visible as completed in the workboard after it is archived, rather
    # than disappearing from the fixed header.
    $retainResult = Invoke-TestCase 'interactive-retained' `
        -ForceInteractive -FinalTicket -Scenario success
    $rawRetain = $retainResult.Output
    # The update draw (after ticket completion and archival) must include the
    # completed-ticket glyph; the enter draw showed an unfinished ticket, so this
    # glyph can only originate from the post-completion Update-RalphWorkboard call.
    Assert-True ($rawRetain -match [regex]::Escape('[' + [char]0x2713 + ']')) `
        'Retained startup feature: completed ticket marker should appear in the workboard update.'
    # The tracker header must be emitted at least twice: once at Enter, once at Update.
    Assert-True (([regex]::Matches($rawRetain, 'Ralph tracker')).Count -ge 2) `
        'Retained startup feature: tracker should be drawn at least twice (enter and update).'

    # A feature-scoped workboard must not render unrelated active features, and
    # must retain the selected feature after it archives.
    $selectedResult = Invoke-TestCase 'interactive-selected-feature' `
        -ForceInteractive -FinalTicket -SecondFeature -Scenario success
    $rawSelected = $selectedResult.Output
    Assert-True ($rawSelected -match '\(feature\)') `
        'Selected-feature workboard did not render the selected feature.'
    Assert-True ($rawSelected -notmatch 'Later feature|later-feature') `
        'Selected-feature workboard rendered an unrelated active feature.'
    Assert-True ($rawSelected -match [regex]::Escape('[' + [char]0x2713 + ']')) `
        'Selected feature was not retained as completed after archival.'

    # Dynamic feature handling: when a new feature appears mid-run, the tracker
    # must rebuild if header height grows, and non-startup features must disappear
    # after they complete while startup features remain retained.
    $dynamicResult = Invoke-TestCase 'interactive-dynamic-feature' `
        -ForceInteractive -FinalTicket -Scope automatic -Iterations 4 `
        -Scenario dynamic-feature
    $rawDynamic = $dynamicResult.Output
    Assert-True ($rawDynamic -match 'Later feature') `
        'Dynamic feature: newly introduced active feature did not appear in the live tracker.'
    Assert-True (([regex]::Matches($rawDynamic, "`e\[2J")).Count -ge 2) `
        'Dynamic feature: header-height increase did not trigger a safe workboard rebuild.'
    Assert-True (([regex]::Matches($rawDynamic, 'Agent output')).Count -ge 2) `
        'Dynamic feature: tracker-height update did not redraw the adjacent Agent output panel.'
    $lastTrackerIndex = $rawDynamic.LastIndexOf('Ralph tracker')
    Assert-True ($lastTrackerIndex -ge 0) `
        'Dynamic feature: no tracker draw was captured.'
    $finalTracker = $rawDynamic.Substring($lastTrackerIndex)
    Assert-True ($finalTracker -match '\(feature\)') `
        'Dynamic feature: startup feature was not retained after archival.'
    Assert-True ($finalTracker -notmatch 'later-feature') `
        'Dynamic feature: non-startup feature remained after completion and archival.'
    Assert-True (
        $finalTracker -match 'Repository:' -and
        $finalTracker -match 'Iteration:'
    ) 'Dynamic feature: tracker redraw lost session metadata rows.'

    # Framed agent output: side borders, iteration heading/divider, and agent messages.
    $result = Invoke-TestCase 'interactive-framed-output' -ForceInteractive -Scenario success
    $rawFramed = $result.Output
    # Vertical side borders must appear in message rows (not just top/bottom frame corners).
    Assert-True ($rawFramed -match "│.*iteration finished") `
        'Interactive run did not render agent message with side borders.'
    Assert-True ($rawFramed -match "│.*Iteration 1") `
        'Interactive run did not render iteration heading inside the Agent output frame.'
    Assert-True ($rawFramed -match "│.*─") `
        'Interactive run did not render a divider row inside the Agent output frame.'

    # Typed agent rows must preserve ANSI ordering and framing for both stream
    # formats. Compare against non-interactive output so the fixed visible-cell
    # cadence remains observable without depending on process startup time.
    foreach ($agent in 'codex', 'copilot') {
        $nonInteractiveStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $nonInteractiveTyped = Invoke-TestCase "noninteractive-typed-output-$agent" `
            -Agent $agent -Scenario typed-output
        $nonInteractiveStopwatch.Stop()

        $interactiveStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $interactiveTyped = Invoke-TestCase "interactive-typed-output-$agent" `
            -Agent $agent -ForceInteractive -Scenario typed-output
        $interactiveStopwatch.Stop()

        $rawTyped = $interactiveTyped.Output
        $styleStartIndex = $rawTyped.IndexOf("`e[31mtyped output ")
        $styleResetIndex = $rawTyped.IndexOf("`e[0m", $styleStartIndex)
        Assert-True ($styleStartIndex -ge 0 -and $styleResetIndex -gt $styleStartIndex) `
            "$agent typed-output: ANSI styling was not emitted in order."
        $visibleTyped = $rawTyped -replace "`e\[[0-?]*[ -/]*[@-~]", ''
        Assert-True ($visibleTyped -match '│ typed output' -and $visibleTyped -match '│ T+') `
            "$agent typed-output: agent text was not emitted inside framed rows."
        Assert-True (([regex]::Matches($visibleTyped, '│[^╭╰]+│')).Count -ge 2) `
            "$agent typed-output: long agent text did not retain wrapped framed rows."
        Assert-True (
            ($interactiveStopwatch.ElapsedMilliseconds - $nonInteractiveStopwatch.ElapsedMilliseconds) -ge 400
        ) "$agent typed-output: visible characters were not paced in the interactive panel."
    }

    # Agent output must retain a single blank separator while dropping leading and
    # repeated blank lines, regardless of the CLI's message framing.
    foreach ($agent in 'codex', 'copilot') {
        $blankOutputResult = Invoke-TestCase "blank-output-$agent" `
            -Agent $agent -Scenario blank-output
        $agentOutput = $blankOutputResult.Output
        $firstLineIndex = $agentOutput.IndexOf('first line')
        $thirdLineIndex = $agentOutput.IndexOf('third line')
        Assert-True ($firstLineIndex -ge 0 -and $thirdLineIndex -gt $firstLineIndex) `
            "$agent blank-output: expected agent text was not emitted."
        $agentOutputSection = $agentOutput.Substring(
            $firstLineIndex,
            $thirdLineIndex - $firstLineIndex + 'third line'.Length
        )
        Assert-True ($agentOutputSection -match "first line`r?`n`r?`nsecond line") `
            "$agent blank-output: a single blank separator was not retained."
        Assert-True ($agentOutputSection -notmatch "`r?`n[ `t]*`r?`n[ `t]*`r?`n") `
            "$agent blank-output: repeated blank lines were not trimmed."
    }

    # Streamed output resize recovery: the row observing a width change must follow
    # a full redraw, use the new wrapping width, and unchanged dimensions must not
    # cause another redraw.
    $widthResizeResult = Invoke-TestCase 'interactive-width-resize' `
        -ForceInteractive -Scenario resize-output `
        -WorkboardDimensions '120x24;60x24;60x24'
    $rawWidthResize = $widthResizeResult.Output
    Assert-Equal 2 ([regex]::Matches($rawWidthResize, "`e\[2J").Count) `
        'Width resize should cause exactly one workboard rebuild.'
    $widthRedrawIndex = $rawWidthResize.LastIndexOf("`e[2J")
    $resizedRowIndex = $rawWidthResize.IndexOf('RRRR', $widthRedrawIndex)
    Assert-True ($resizedRowIndex -gt $widthRedrawIndex) `
        'Width resize emitted the triggering row before the refreshed frame.'
    $resizedOutput = $rawWidthResize.Substring($resizedRowIndex)
    Assert-True (([regex]::Matches($resizedOutput, '│[^\r\n]*R[^\r\n]*│')).Count -ge 2) `
        'Width resize did not wrap the triggering row to the refreshed inner width.'

    # A height-only change must likewise rebuild the fixed panels and install a
    # scroll region using the refreshed terminal height.
    $heightResizeResult = Invoke-TestCase 'interactive-height-resize' `
        -ForceInteractive -Scenario resize-output `
        -WorkboardDimensions '120x24;120x18;120x18'
    $rawHeightResize = $heightResizeResult.Output
    Assert-Equal 2 ([regex]::Matches($rawHeightResize, "`e\[2J").Count) `
        'Height resize should cause exactly one workboard rebuild.'
    $heightRedrawIndex = $rawHeightResize.LastIndexOf("`e[2J")
    Assert-True ($rawHeightResize.IndexOf('RRRR', $heightRedrawIndex) -gt $heightRedrawIndex) `
        'Height resize emitted the triggering row before the refreshed frame.'
    Assert-True ($rawHeightResize.Substring($heightRedrawIndex) -match "`e\[\d+;17r") `
        'Height resize did not refresh the Agent output scroll region.'

    # A temporarily undersized terminal must retain the last valid layout. Once a
    # later streamed row observes usable dimensions, Ralph should rebuild and emit
    # that row inside the recovered frame.
    $undersizedResizeResult = Invoke-TestCase 'interactive-undersized-resize' `
        -ForceInteractive -Scenario resize-output `
        -WorkboardDimensions '120x24;120x5;80x24'
    $rawUndersizedResize = $undersizedResizeResult.Output
    Assert-Equal 2 ([regex]::Matches($rawUndersizedResize, "`e\[2J").Count) `
        'Undersized resize should defer redraw until dimensions become usable.'
    Assert-True ($rawUndersizedResize -notmatch "`e\[\d+;4r") `
        'Undersized resize emitted an invalid or overlapping scroll region.'
    $recoveryRedrawIndex = $rawUndersizedResize.LastIndexOf("`e[2J")
    $recoveredRowIndex = $rawUndersizedResize.IndexOf(
        'unchanged size',
        $recoveryRedrawIndex
    )
    Assert-True ($recoveredRowIndex -gt $recoveryRedrawIndex) `
        'Recovered resize emitted the triggering row before rebuilding the frame.'
    Assert-True ($rawUndersizedResize.Substring($recoveryRedrawIndex) -match "`e\[\d+;23r") `
        'Recovered resize did not restore a valid Agent output scroll region.'

    # Long-output wrapping: content longer than the inner width must be split across rows.
    $longResult = Invoke-TestCase 'interactive-long-output' -ForceInteractive `
        -Scenario long-output
    $rawLong = $longResult.Output
    Assert-True ($rawLong -match 'LLLL') `
        'Long-output: content was lost from the framed output.'
    # Wrapped lines each end with the right-side border; multiple │ rows must appear.
    $borderRows = [regex]::Matches($rawLong, '│[^╭╰]+│')
    Assert-True ($borderRows.Count -ge 2) `
        'Long-output: content was not wrapped into multiple framed rows with right borders.'

    # Explicit LF, CRLF, and CR boundaries must create independent framed rows,
    # including the interior blank line and the transport-appended trailing row.
    foreach ($scenario in 'line-ending-lf', 'line-ending-crlf', 'line-ending-cr') {
        $lineEndingResult = Invoke-TestCase "interactive-$scenario" -ForceInteractive `
            -Agent codex -Scenario $scenario
        $visibleLineEndingOutput = $lineEndingResult.Output -replace "`e\[[0-?]*[ -/]*[@-~]", ''
        Assert-True (
            $visibleLineEndingOutput -match (
                '│ first agent line[ ]*│\r?\n│[ ]+│\r?\n│ second agent line[ ]*│'
            )
        ) "${scenario}: multiline content was not rendered as independently framed rows."
        Assert-True (
            $visibleLineEndingOutput -match '│ second agent line[ ]*│\r?\n│[ ]+│'
        ) "${scenario}: the trailing delimiter did not render a framed blank row."
    }

    # Prose should break between complete words instead of splitting a normal token.
    $wordWrapResult = Invoke-TestCase 'interactive-word-wrap-output' -ForceInteractive `
        -Agent codex -Scenario word-wrap-output -WorkboardDimensions '40x24'
    $visibleWordWrapRows = @(
        ($wordWrapResult.Output -replace "`e\[[0-?]*[ -/]*[@-~]", '') -split '\r?\n' |
            Where-Object { $_ -match '│.*alpha.*│' }
    )
    Assert-True ($visibleWordWrapRows.Count -ge 2) `
        'Word-wrap: normal prose was not wrapped into multiple framed rows.'
    Assert-True (
        @($visibleWordWrapRows | Where-Object { $_ -match 'alph[ ]+│' }).Count -eq 0
    ) 'Word-wrap: a normal word was split at the right border.'

    # Wide-character wrapping: CJK glyphs (display width 2) must still wrap and keep borders aligned.
    $wideResult = Invoke-TestCase 'interactive-wide-output' -ForceInteractive `
        -Agent copilot -Scenario wide-output
    $rawWide = $wideResult.Output
    Assert-True ($rawWide -match '漢') `
        'Wide-output: wide glyph content was not emitted by the interactive run.'
    $wideFramedRows = [regex]::Matches($rawWide, '│[^╭╰]*漢[^╭╰]*│')
    Assert-True ($wideFramedRows.Count -ge 1) `
        'Wide-output: display-cell-width output did not preserve a framed row with both side borders.'

    # Successful completion should compact the frame so the final border is redrawn after completion.
    $compactResult = Invoke-TestCase 'interactive-compact-completion' -ForceInteractive `
        -FinalTicket -Scenario success
    $rawCompact = $compactResult.Output
    $completeIndex = $rawCompact.LastIndexOf('Requested scope complete.')
    Assert-True ($completeIndex -ge 0) `
        'Compact completion: expected completion message was not emitted.'
    $finalBottomIndex = $rawCompact.LastIndexOf('╰')
    Assert-True ($finalBottomIndex -gt $completeIndex) `
        'Compact completion: bottom border was not redrawn after completion.'
    $completionLineEnd = $rawCompact.IndexOf("`n", $completeIndex)
    if ($completionLineEnd -lt 0) { $completionLineEnd = $completeIndex }
    $betweenCompletionAndBorder = $rawCompact.Substring(
        $completionLineEnd,
        $finalBottomIndex - $completionLineEnd
    )
    Assert-True ($betweenCompletionAndBorder -notmatch '│\s*│') `
        'Compact completion: a blank framed row remained between completion and bottom border.'

    # Terminal cleanup: after exit, cursor must be positioned below the Agent output frame.
    $exitResult = Invoke-TestCase 'interactive-exit-placement' -ForceInteractive `
        -Scenario success
    $rawExit = $exitResult.Output
    $restoreIdx = $rawExit.LastIndexOf("`e[r")
    Assert-True ($restoreIdx -ge 0) `
        'Interactive exit: scroll region was not restored.'
    $afterRestore = $rawExit.Substring($restoreIdx)
    Assert-True ($afterRestore -match "`e\[\d+;1H") `
        'Interactive exit: cursor was not positioned below the Agent output frame.'

    # Capped iteration denominator: with more configured iterations than open tickets, the
    # displayed denominator must reflect actual scoped work (CompletedIterations + openTickets)
    # rather than the configured ceiling.
    # 2 tickets (no FinalTicket), Iterations=5 → at enter: min(5, 0+2)=2 → tracker "Iteration: 1 of 2"
    $cappedResult = Invoke-TestCase 'interactive-capped-denominator' `
        -ForceInteractive -Iterations 5 -Scenario sequential
    $rawCapped = $cappedResult.Output -replace "`e\[[0-9;]*m", ''
    Assert-True ($rawCapped -match 'Iteration:\s+1 of 2') `
        'Interactive run did not cap the iteration denominator to actual scoped work.'
    Assert-True ($rawCapped -notmatch 'Iteration:\s+1 of 5') `
        'Interactive run used the configured ceiling in the tracker denominator.'

    # Automatic-scope capped denominator: counts open tickets across all active features.
    # feature(2 tickets) + later-feature(1 ticket) = 3 total, Iterations=4
    # At enter: min(4, 0+3)=3 → tracker "Iteration: 1 of 3"
    $autoCapResult = Invoke-TestCase 'interactive-auto-capped' `
        -ForceInteractive -Scope automatic -SecondFeature -Iterations 4 -Scenario sequential
    $rawAutoCap = $autoCapResult.Output -replace "`e\[[0-9;]*m", ''
    $initialAutoTracker = $rawAutoCap.Substring(0, $rawAutoCap.IndexOf('Agent output'))
    Assert-True ($initialAutoTracker -match 'Iteration:\s+1 of 3') `
        'Automatic-scope interactive run did not cap the iteration denominator to open ticket count.'
    Assert-True ($initialAutoTracker -notmatch 'Iteration:\s+1 of 4') `
        'Automatic-scope interactive run used the configured ceiling in the tracker denominator.'

    Write-Host 'PASS: Invoke-Ralph tracker-state tests'
}
finally {
    $env:PATH = $originalPath
    if (Test-Path $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
