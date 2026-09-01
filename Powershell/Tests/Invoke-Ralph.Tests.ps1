#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Internal' -Tag 'Internal' {
    BeforeAll {
        $ralphPath = (Get-Item -LiteralPath (
            Join-Path $PSScriptRoot '..\Startup\Invoke-Ralph.ps1'
        )).FullName
        $quotedRalphPath = $ralphPath.Replace("'", "''")
        $importScript = [scriptblock]::Create(". '$quotedRalphPath'")
        $script:ralphModule = New-Module -Name (
            'Invoke-Ralph.TestImport.' + [guid]::NewGuid().ToString('N')
        ) -ScriptBlock $importScript

        function ConvertFrom-RalphTerminalOutput {
            param(
                [Parameter(Mandatory)][string] $Output,
                [Parameter(Mandatory)][int] $Width,
                [Parameter(Mandatory)][int] $Height
            )

            $cells = [char[,]]::new($Height, $Width)
            for ($row = 0; $row -lt $Height; $row++) {
                for ($column = 0; $column -lt $Width; $column++) {
                    $cells[$row, $column] = ' '
                }
            }

            $cursorX = 0; $cursorY = 0; $savedX = 0; $savedY = 0
            $scrollTop = 0; $scrollBottom = $Height - 1; $pendingWrap = $false
            $index = 0
            while ($index -lt $Output.Length) {
                $character = $Output[$index]
                if ($character -eq [char]27 -and $index + 1 -lt $Output.Length) {
                    if ($Output[$index + 1] -eq '[') {
                        $end = $index + 2
                        while ($end -lt $Output.Length -and $Output[$end] -notmatch '[@-~]') { $end++ }
                        if ($end -ge $Output.Length) { break }
                        $parameters = $Output.Substring($index + 2, $end - $index - 2)
                        $command = $Output[$end]
                        $numbers = @($parameters -replace '^\?', '' -split ';' | ForEach-Object {
                                if ($_) { [int]$_ } else { 0 }
                            })
                        switch ($command) {
                            'H' { $cursorY = [Math]::Max(0, ($numbers[0] -as [int]) - 1); $cursorX = [Math]::Max(0, ($numbers[1] -as [int]) - 1); $pendingWrap = $false }
                            'f' { $cursorY = [Math]::Max(0, ($numbers[0] -as [int]) - 1); $cursorX = [Math]::Max(0, ($numbers[1] -as [int]) - 1); $pendingWrap = $false }
                            'J' { if ($numbers[0] -eq 2) { for ($row = 0; $row -lt $Height; $row++) { for ($column = 0; $column -lt $Width; $column++) { $cells[$row, $column] = ' ' } } } }
                            'r' { if ($parameters) { $scrollTop = $numbers[0] - 1; $scrollBottom = $numbers[1] - 1 } else { $scrollTop = 0; $scrollBottom = $Height - 1 }; $pendingWrap = $false }
                            's' { $savedX = $cursorX; $savedY = $cursorY }
                            'u' { $cursorX = $savedX; $cursorY = $savedY; $pendingWrap = $false }
                        }
                        $index = $end + 1
                        continue
                    }
                    if ($Output[$index + 1] -eq ']') {
                        $end = $Output.IndexOf([string][char]27 + '\', $index + 2, [System.StringComparison]::Ordinal)
                        $index = if ($end -lt 0) { $Output.Length } else { $end + 2 }
                        continue
                    }
                }

                if ($character -eq "`r") { $cursorX = 0; $pendingWrap = $false }
                elseif ($character -eq "`n") {
                    if ($cursorY -eq $scrollBottom) {
                        for ($row = $scrollTop; $row -lt $scrollBottom; $row++) {
                            for ($column = 0; $column -lt $Width; $column++) { $cells[$row, $column] = $cells[($row + 1), $column] }
                        }
                        for ($column = 0; $column -lt $Width; $column++) { $cells[$scrollBottom, $column] = ' ' }
                    }
                    else { $cursorY = [Math]::Min($Height - 1, $cursorY + 1) }
                    $pendingWrap = $false
                }
                elseif ([int]$character -ge 32) {
                    if ($pendingWrap) {
                        $cursorX = 0
                        if ($cursorY -eq $scrollBottom) {
                            for ($row = $scrollTop; $row -lt $scrollBottom; $row++) {
                                for ($column = 0; $column -lt $Width; $column++) { $cells[$row, $column] = $cells[($row + 1), $column] }
                            }
                            for ($column = 0; $column -lt $Width; $column++) { $cells[$scrollBottom, $column] = ' ' }
                        }
                        else { $cursorY = [Math]::Min($Height - 1, $cursorY + 1) }
                        $pendingWrap = $false
                    }
                    $cells[$cursorY, $cursorX] = $character
                    if ($cursorX -eq $Width - 1) { $pendingWrap = $true } else { $cursorX++ }
                }
                $index++
            }

            [pscustomobject]@{
                Cells = $cells
                Snapshot = (@(for ($row = 0; $row -lt $Height; $row++) {
                            -join @(for ($column = 0; $column -lt $Width; $column++) { $cells[$row, $column] })
                        }) -join "`n")
            }
        }
    }

    AfterAll {
        if ($script:ralphModule) {
            Remove-Module -ModuleInfo $script:ralphModule -Force -ErrorAction SilentlyContinue
        }
    }

    It 'imports Ralph internals without starting the command body' {
        $nativeText = & $script:ralphModule { Get-Command Invoke-NativeText }
        $progressReader = & $script:ralphModule { Get-Command Get-NewProgressEntry }
        $invocationResolver = & $script:ralphModule { Get-Command Resolve-RalphInvocation }
        $repositoryState = & $script:ralphModule {
            Get-Variable -Name repositoryRoot -ErrorAction SilentlyContinue
        }

        $nativeText.Name | Should -Be 'Invoke-NativeText'
        $progressReader.Name | Should -Be 'Get-NewProgressEntry'
        $invocationResolver.Name | Should -Be 'Resolve-RalphInvocation'
        $repositoryState | Should -BeNullOrEmpty
    }

    It 'forwards agent output before the process exits' {
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
        $received = [System.Collections.Generic.List[object]]::new()
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        $result = & $script:ralphModule {
            param($PowerShellPath, $Received, $Stopwatch)
            Invoke-AgentProcess -CommandPath $PowerShellPath -ArgumentList @(
                '-NoProfile', '-Command',
                "Write-Output 'first'; Start-Sleep -Milliseconds 1500; Write-Output 'second'"
            ) -OnOutputLine {
                param($Line)
                $Received.Add([pscustomobject]@{
                        Line = $Line
                        Milliseconds = $Stopwatch.ElapsedMilliseconds
                    })
            }
        } $pwsh $received $stopwatch

        $result.ExitCode | Should -Be 0
        $received.Line | Should -Be @('first', 'second')
        $received[0].Milliseconds | Should -BeLessThan 1200
    }

    It 'ignores agent events without a type under strict mode' {
        $event = [pscustomobject]@{
            item = [pscustomobject]@{ type = 'agent_message'; text = 'hello' }
        }
        $seen = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $result = $null

        {
            $result = & $script:ralphModule {
                param($InputEvent, $SeenMessageIds)
                Set-StrictMode -Version Latest
                ConvertTo-NormalizedAgentMessage -Name codex -Event $InputEvent `
                    -SeenMessageIds $SeenMessageIds
            } $event $seen
        } | Should -Not -Throw

        $result | Should -BeNullOrEmpty
    }

    It 'resolves Ralph invocation modes and effective configuration in process' -TestCases @(
        @{
            Name = 'automatic defaults'
            Bound = @{}
            List = $false; Cleanup = $false; Archive = ''; Agent = 'codex'; Model = ''; Effort = ''; Feature = ''
            Mode = 'Run'; Scope = 'automatic'; EffectiveModel = 'gpt-5.6-luna'; EffectiveEffort = 'medium'
        },
        @{
            Name = 'feature scope'
            Bound = @{ Feature = 'feature' }
            List = $false; Cleanup = $false; Archive = ''; Agent = 'copilot'; Model = ''; Effort = ''; Feature = 'feature'
            Mode = 'Run'; Scope = 'feature'; EffectiveModel = 'gpt-5.6-luna'; EffectiveEffort = 'medium'
        },
        @{
            Name = 'archive mode'
            Bound = @{ Archive = 'feature' }
            List = $false; Cleanup = $false; Archive = 'feature'; Agent = 'codex'; Model = ''; Effort = ''; Feature = ''
            Mode = 'Archive'; Scope = 'automatic'; EffectiveModel = 'gpt-5.6-luna'; EffectiveEffort = 'medium'
        },
        @{
            Name = 'list mode'
            Bound = @{ List = $true }
            List = $true; Cleanup = $false; Archive = ''; Agent = 'codex'; Model = ''; Effort = ''; Feature = ''
            Mode = 'List'; Scope = 'automatic'; EffectiveModel = 'gpt-5.6-luna'; EffectiveEffort = 'medium'
        },
        @{
            Name = 'cleanup mode'
            Bound = @{ Cleanup = $true }
            List = $false; Cleanup = $true; Archive = ''; Agent = 'codex'; Model = ''; Effort = ''; Feature = ''
            Mode = 'Cleanup'; Scope = 'automatic'; EffectiveModel = 'gpt-5.6-luna'; EffectiveEffort = 'medium'
        },
        @{
            Name = 'custom Codex configuration'
            Bound = @{ Agent = 'codex'; Model = 'custom-model'; Effort = 'high' }
            List = $false; Cleanup = $false; Archive = ''; Agent = 'codex'; Model = 'custom-model'; Effort = 'high'; Feature = ''
            Mode = 'Run'; Scope = 'automatic'; EffectiveModel = 'custom-model'; EffectiveEffort = 'high'
        },
        @{
            Name = 'custom Copilot configuration'
            Bound = @{ Agent = 'copilot'; Model = 'custom-model'; Effort = 'low' }
            List = $false; Cleanup = $false; Archive = ''; Agent = 'copilot'; Model = 'custom-model'; Effort = 'low'; Feature = ''
            Mode = 'Run'; Scope = 'automatic'; EffectiveModel = 'custom-model'; EffectiveEffort = 'low'
        }
    ) {
        param($Name, $Bound, $List, $Cleanup, $Archive, $Agent, $Model, $Effort, $Feature,
            $Mode, $Scope, $EffectiveModel, $EffectiveEffort)

        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Invocation.' + [guid]::NewGuid().ToString('N')
        )
        $scratch = Join-Path $fixture '.scratch'
        try {
            New-Item -ItemType Directory -Path (Join-Path $scratch 'feature') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $scratch 'feature\spec.md') -Value '# Feature'

            $result = & $script:ralphModule {
                param($Scratch, $Parameters, $IsList, $IsCleanup, $ArchiveName, $AgentName,
                    $ModelName, $EffortName, $FeatureName)
                Resolve-RalphInvocation -ScratchDirectory $Scratch -BoundParameters $Parameters `
                    -List:$IsList -Cleanup:$IsCleanup -Archive $ArchiveName -Agent $AgentName `
                    -Model $ModelName -Effort $EffortName -Feature $FeatureName
            } $scratch $Bound $List $Cleanup $Archive $Agent $Model $Effort $Feature

            $result.Mode | Should -Be $Mode
            $result.Scope | Should -Be $Scope
            $result.Agent.Name | Should -Be $Agent
            $result.Agent.Model | Should -Be $EffectiveModel
            $result.Agent.Effort | Should -Be $EffectiveEffort
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects invalid Ralph invocation options and tracker identities in process' -TestCases @(
        @{ Name = 'empty model'; Bound = @{ Model = '' }; List = $false; Cleanup = $false; Archive = ''; Feature = ''; Error = '-Model must be a non-empty value.' },
        @{ Name = 'empty effort'; Bound = @{ Effort = '' }; List = $false; Cleanup = $false; Archive = ''; Feature = ''; Error = '-Effort must be a non-empty value.' },
        @{ Name = 'list feature'; Bound = @{ List = $true; Feature = 'feature' }; List = $true; Cleanup = $false; Archive = ''; Feature = 'feature'; Error = '-List cannot be combined with: Feature.' },
        @{ Name = 'archive cleanup'; Bound = @{ Archive = 'feature'; Cleanup = $true }; List = $false; Cleanup = $true; Archive = 'feature'; Feature = ''; Error = '-Archive cannot be combined with: Cleanup.' },
        @{ Name = 'nested feature'; Bound = @{ Feature = 'feature\spec.md' }; List = $false; Cleanup = $false; Archive = ''; Feature = 'feature\spec.md'; Error = 'Feature must name a direct active tracker folder containing spec.md: feature\spec.md' },
        @{ Name = 'archived feature'; Bound = @{ Feature = 'archived' }; List = $false; Cleanup = $false; Archive = ''; Feature = 'archived'; Error = 'Feature must name a direct active tracker folder containing spec.md: archived' },
        @{ Name = 'missing archive'; Bound = @{ Archive = 'missing' }; List = $false; Cleanup = $false; Archive = 'missing'; Feature = ''; Error = 'Archive must name a direct active tracker folder containing spec.md: missing' }
    ) {
        param($Name, $Bound, $List, $Cleanup, $Archive, $Feature, $Error)

        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Invocation.' + [guid]::NewGuid().ToString('N')
        )
        $scratch = Join-Path $fixture '.scratch'
        try {
            New-Item -ItemType Directory -Path (Join-Path $scratch 'feature') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $scratch 'done\archived') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $scratch 'feature\spec.md') -Value '# Feature'
            Set-Content -LiteralPath (Join-Path $scratch 'done\archived\spec.md') -Value '# Archived'

            {
                & $script:ralphModule {
                    param($Scratch, $Parameters, $IsList, $IsCleanup, $ArchiveName, $FeatureName)
                    Resolve-RalphInvocation -ScratchDirectory $Scratch -BoundParameters $Parameters `
                        -List:$IsList -Cleanup:$IsCleanup -Archive $ArchiveName -Agent codex `
                        -Model '' -Effort '' -Feature $FeatureName
                } $scratch $Bound $List $Cleanup $Archive $Feature
            } | Should -Throw "*$Error*"
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'plans typed terminal output without writing or sleeping' {
        $escape = [string][char]27
        $plan = & $script:ralphModule {
            param($text)
            Get-TypedAgentOutputPlan -Content $text -ContentWidth 4 -InnerWidth 6
        } "${escape}[31mA漢B${escape}]0;title${escape}`\${escape}[0m"

        @($plan | ForEach-Object Kind) | Should -Be @(
            'Write', 'Write', 'Write', 'Write', 'Pause', 'Write', 'Pause', 'Write', 'Write', 'WriteLine'
        )
        @($plan | Where-Object Kind -eq 'Pause').Count | Should -Be 2
        @($plan | Where-Object Kind -eq 'Pause' | ForEach-Object Duration) | Should -Be @(8, 8)
        ($plan | Where-Object Kind -eq 'Write').Text -join '' | Should -Match (
            [regex]::Escape("${escape}[31mA漢B${escape}]0;title${escape}`\${escape}[0m")
        )
        ($plan | Where-Object Kind -eq 'WriteLine').Text | Should -Match '│'
    }

    It 'keeps renderer wrapping, Markdown, blank rows, and line boundaries deterministic' {
        $escape = [string][char]27
        $result = & $script:ralphModule {
            $longRows = Split-AgentOutputContent -Content ('L' * 20) -InnerWidth 8
            $wordRows = Split-AgentOutputContent -Content 'alpha beta gamma' -InnerWidth 10
            $wideRows = Split-AgentOutputContent -Content ('漢' * 8) -InnerWidth 6
            $lineRows = Split-AgentOutputContent -Content "first`r`n`rsecond`nthird" -InnerWidth 20
            $markdown = ConvertTo-RalphMarkdown -Markdown '# Heading with **bold**' -Interactive
            [pscustomobject]@{
                LongWidths = @($longRows | ForEach-Object Width)
                WordRows = @($wordRows | ForEach-Object Text)
                WideWidths = @($wideRows | ForEach-Object Width)
                LineRows = @($lineRows | ForEach-Object Text)
                Markdown = $markdown
            }
        }

        $result.LongWidths.Count | Should -BeGreaterThan 1
        @($result.LongWidths | Where-Object { $_ -gt 8 }).Count | Should -Be 0
        ($result.WordRows -join ' ') | Should -Be 'alpha beta gamma'
        @($result.WordRows | Where-Object { $_ -match 'alph$|bet$|gamm$' }).Count | Should -Be 0
        @($result.WideWidths | Where-Object { $_ -gt 6 }).Count | Should -Be 0
        $result.LineRows | Should -Be @('first', '', 'second', 'third')
        $result.Markdown | Should -Match ([regex]::Escape("${escape}[1;7m"))
        $result.Markdown | Should -Match ([regex]::Escape("${escape}[1mbold"))
    }

    It 'validates appended progress records in process' -TestCases @(
        @{ Name = 'valid append'; Before = ''; After = '{"feature":"feature","ticket":"01","changes":"implemented","checks":"passed"}' + "`n"; Error = ''; Ticket = '01' },
        @{ Name = 'valid unterminated append'; Before = ''; After = '{"feature":"feature","ticket":"01","changes":"implemented","checks":"passed"}'; Error = ''; Ticket = '01' },
        @{ Name = 'existing history'; Before = '{"feature":"previous","ticket":"00","changes":"done","checks":"passed"}' + "`n"; After = '{"feature":"previous","ticket":"00","changes":"done","checks":"passed"}' + "`n" + '{"feature":"feature","ticket":"01","changes":"implemented","checks":"passed"}' + "`n"; Error = ''; Ticket = '01' },
        @{ Name = 'malformed JSON'; Before = ''; After = '{bad json' + "`n"; Error = 'not valid JSON'; Ticket = '' },
        @{ Name = 'missing field'; Before = ''; After = '{"feature":"feature","ticket":"01","changes":"implemented"}' + "`n"; Error = "requires a non-empty string 'checks'"; Ticket = '' },
        @{ Name = 'empty field'; Before = ''; After = '{"feature":"feature","ticket":"01","changes":" ","checks":"passed"}' + "`n"; Error = "requires a non-empty string 'changes'"; Ticket = '' },
        @{ Name = 'multiple records'; Before = ''; After = '{"feature":"feature","ticket":"01","changes":"implemented","checks":"passed"}' + "`n" + '{"feature":"feature","ticket":"02","changes":"implemented","checks":"passed"}' + "`n"; Error = 'exactly one JSONL record'; Ticket = '' },
        @{ Name = 'rewrite'; Before = '{"feature":"previous","ticket":"00","changes":"done","checks":"passed"}' + "`n"; After = '{"feature":"feature","ticket":"01","changes":"implemented","checks":"passed"}' + "`n"; Error = 'must only append'; Ticket = '' },
        @{ Name = 'missing prior newline'; Before = '{"feature":"previous","ticket":"00","changes":"done","checks":"passed"}'; After = '{"feature":"previous","ticket":"00","changes":"done","checks":"passed"}{"feature":"feature","ticket":"01","changes":"implemented","checks":"passed"}' + "`n"; Error = 'must end with a newline'; Ticket = '' }
    ) {
        param($Name, $Before, $After, $Error, $Ticket)

        if ($Error) {
            {
                & $script:ralphModule {
                    param($BeforeText, $AfterText)
                    Get-NewProgressEntry -Before $BeforeText -After $AfterText
                } $Before $After
            } | Should -Throw "*$Error*"
        }
        else {
            $entry = & $script:ralphModule {
                param($BeforeText, $AfterText)
                Get-NewProgressEntry -Before $BeforeText -After $AfterText
            } $Before $After
            $entry.ticket | Should -Be $Ticket
        }
    }

    It 'repairs only a missing progress history terminator in process' -TestCases @(
        @{ Name = 'empty history'; Before = [byte[]]@(); After = [byte[]]@(); Changed = $false },
        @{ Name = 'LF terminated history'; Before = [Text.Encoding]::UTF8.GetBytes("one`n"); After = [Text.Encoding]::UTF8.GetBytes("one`n"); Changed = $false },
        @{ Name = 'CRLF terminated history'; Before = [Text.Encoding]::UTF8.GetBytes("one`r`n"); After = [Text.Encoding]::UTF8.GetBytes("one`r`n"); Changed = $false },
        @{ Name = 'unterminated history'; Before = [Text.Encoding]::UTF8.GetBytes('one'); After = [Text.Encoding]::UTF8.GetBytes("one`n"); Changed = $true }
    ) {
        param($Name, $Before, $After, $Changed)

        $path = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Progress.' + [guid]::NewGuid().ToString('N') + '.jsonl'
        )
        try {
            [System.IO.File]::WriteAllBytes($path, $Before)

            $actualChanged = & $script:ralphModule {
                param($ProgressPath)
                Repair-ProgressHistoryTerminator -Path $ProgressPath
            } $path

            $actualChanged | Should -Be $Changed
            [System.IO.File]::ReadAllBytes($path) | Should -Be $After
            & $script:ralphModule {
                param($ProgressPath)
                Repair-ProgressHistoryTerminator -Path $ProgressPath
            } $path | Should -BeFalse
            [System.IO.File]::ReadAllBytes($path) | Should -Be $After
        }
        finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'interprets tracker status declarations in process' -TestCases @(
        @{ Name = 'ready status'; Content = "# Ticket`n`nStatus: ready-for-agent"; Status = 'ready-for-agent'; Error = '' },
        @{ Name = 'bold case variant'; Content = "# Ticket`n`n**STATUS:** DONE"; Status = 'done'; Error = '' },
        @{ Name = 'list closed status'; Content = "# Ticket`n`n- Status: closed"; Status = 'closed'; Error = '' },
        @{ Name = 'quote ready status'; Content = "# Ticket`n`n> Status: READY-FOR-AGENT"; Status = 'ready-for-agent'; Error = '' },
        @{ Name = 'body positioned status'; Content = "# Ticket`n`nText before metadata.`n`n**Status:** ready-for-agent"; Status = 'ready-for-agent'; Error = '' },
        @{ Name = 'missing status'; Content = '# Ticket'; Status = ''; Error = 'missing Status' },
        @{ Name = 'duplicate status'; Content = "# Ticket`n`nStatus: done`nStatus: closed"; Status = ''; Error = 'exactly one Status' },
        @{ Name = 'malformed status'; Content = "# Ticket`n`nStatus = done"; Status = ''; Error = 'malformed Status' },
        @{ Name = 'unsupported status'; Content = "# Ticket`n`nStatus: in-progress"; Status = ''; Error = 'unsupported Status' },
        @{ Name = 'fenced example'; Content = "# Ticket`n`n" + '```md' + "`nStatus: done`n" + '```'; Status = ''; Error = 'missing Status' },
        @{ Name = 'fenced and body status'; Content = "# Ticket`n`n" + '```md' + "`nStatus: done`n" + '```' + "`n`nStatus: ready-for-agent"; Status = 'ready-for-agent'; Error = '' }
    ) {
        param($Name, $Content, $Status, $Error)

        $path = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Status.' + [guid]::NewGuid().ToString('N') + '.md'
        )
        try {
            Set-Content -LiteralPath $path -Value $Content -NoNewline
            if ($Error) {
                {
                    & $script:ralphModule {
                        param($TicketPath)
                        Get-TrackerTicketStatus -Path $TicketPath
                    } $path
                } | Should -Throw "*$Error*"
            }
            else {
                $actual = & $script:ralphModule {
                    param($TicketPath)
                    Get-TrackerTicketStatus -Path $TicketPath
                } $path
                $actual | Should -Be $Status
            }
        }
        finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reconciles completed dependency closures in process' -TestCases @(
        @{ Name = 'direct done dependency'; SeedStatus = 'done'; Dependencies = '01 — First'; Expected = @('01', '02') },
        @{ Name = 'direct closed dependency'; SeedStatus = 'closed'; Dependencies = '01 — First'; Expected = @('01', '02') },
        @{ Name = 'sentence punctuation after dependency title'; SeedStatus = 'done'; Dependencies = '01 — First.'; Expected = @('01', '02') },
        @{ Name = 'duplicate dependency references'; SeedStatus = 'done'; Dependencies = '01 — First; 01 — First'; Expected = @('01', '02') }
    ) {
        param($Name, $SeedStatus, $Dependencies, $Expected)

        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Reconcile.' + [guid]::NewGuid().ToString('N')
        )
        $issues = Join-Path $fixture 'feature\issues'
        try {
            New-Item -ItemType Directory -Path $issues -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $issues '01-first.md') -Value @'
# 01 — First

Blocked by: None — can start immediately

Status: ready-for-agent
'@
            Set-Content -LiteralPath (Join-Path $issues '02-second.md') -Value @"
# 02 — Second

Blocked by: $Dependencies

Status: $SeedStatus
"@

            $result = & $script:ralphModule {
                param($FeatureDirectory)
                Invoke-TrackerDependencyReconciliation -FeatureDirectory $FeatureDirectory
            } (Join-Path $fixture 'feature')

            $result.CompletedTicketIds | Should -Be $Expected
            $result.UpdatedTicketIds | Should -Be @('01')
            & $script:ralphModule {
                param($Path)
                Get-TrackerTicketStatus -Path $Path
            } (Join-Path $issues '01-first.md') | Should -Be 'done'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reconciles multi-level dependency chains from a completed seed in process' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Reconcile.' + [guid]::NewGuid().ToString('N')
        )
        $issues = Join-Path $fixture 'feature\issues'
        try {
            New-Item -ItemType Directory -Path $issues -Force | Out-Null
            foreach ($ticket in @(
                @{ Id = '01'; Title = 'First'; BlockedBy = 'None — can start immediately'; Status = 'ready-for-agent' },
                @{ Id = '02'; Title = 'Second'; BlockedBy = '01 — First'; Status = 'ready-for-agent' },
                @{ Id = '03'; Title = 'Third'; BlockedBy = '02 — Second'; Status = 'done' }
            )) {
                Set-Content -LiteralPath (Join-Path $issues "$($ticket.Id)-$($ticket.Title.ToLowerInvariant()).md") -Value @"
# $($ticket.Id) — $($ticket.Title)

Blocked by: $($ticket.BlockedBy)

Status: $($ticket.Status)
"@
            }

            $result = & $script:ralphModule {
                param($FeatureDirectory)
                Invoke-TrackerDependencyReconciliation -FeatureDirectory $FeatureDirectory
            } (Join-Path $fixture 'feature')

            $result.CompletedTicketIds | Should -Be @('01', '02', '03')
            $result.UpdatedTicketIds | Should -Be @('01', '02')
            foreach ($id in '01', '02', '03') {
                & $script:ralphModule {
                    param($Path)
                    Get-TrackerTicketStatus -Path $Path
                } (Join-Path $issues "$id-$(switch ($id) { '01' { 'first' }; '02' { 'second' }; default { 'third' } }).md") | Should -Be 'done'
            }
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'allows a ticket to depend on a finding from another spec' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Reconcile.' + [guid]::NewGuid().ToString('N')
        )
        $issues = Join-Path $fixture 'dependent-feature\issues'
        try {
            New-Item -ItemType Directory -Path $issues -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $issues '01-first.md') -Value @'
# 01 — First

Blocked by: Finding 1 — Add adversarial serial and job state-machine tests

Status: ready-for-agent
'@

            $result = & $script:ralphModule {
                param($FeatureDirectory)
                Invoke-TrackerDependencyReconciliation -FeatureDirectory $FeatureDirectory
            } (Join-Path $fixture 'dependent-feature')

            $result.CompletedTicketIds | Should -BeNullOrEmpty
            $result.UpdatedTicketIds | Should -BeNullOrEmpty
            & $script:ralphModule {
                param($Path)
                Get-TrackerTicketStatus -Path $Path
            } (Join-Path $issues '01-first.md') | Should -Be 'ready-for-agent'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects invalid dependency graphs before changing statuses in process' -TestCases @(
        @{
            Name = 'unknown reference'
            FirstBlockedBy = '99 — Missing'; SecondBlockedBy = 'None — can start immediately'
            Error = "unknown Blocked by reference '99'"
        },
        @{
            Name = 'malformed reference'
            FirstBlockedBy = 'First ticket'; SecondBlockedBy = 'None — can start immediately'
            Error = 'malformed Blocked by reference'
        },
        @{
            Name = 'mismatched punctuated title'
            FirstBlockedBy = 'None — can start immediately'; SecondBlockedBy = '01 — Different.'
            Error = "mismatched Blocked by title for '01'"
        },
        @{
            Name = 'cycle'
            FirstBlockedBy = '02 — Second'; SecondBlockedBy = '01 — First'
            Error = 'dependency cycle: 01 -> 02 -> 01'
        }
    ) {
        param($Name, $FirstBlockedBy, $SecondBlockedBy, $Error)

        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Reconcile.' + [guid]::NewGuid().ToString('N')
        )
        $issues = Join-Path $fixture 'feature\issues'
        try {
            New-Item -ItemType Directory -Path $issues -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $issues '01-first.md') -Value @"
# 01 — First

Blocked by: $FirstBlockedBy

Status: ready-for-agent
"@
            Set-Content -LiteralPath (Join-Path $issues '02-second.md') -Value @"
# 02 — Second

Blocked by: $SecondBlockedBy

Status: done
"@

            {
                & $script:ralphModule {
                    param($FeatureDirectory)
                    Invoke-TrackerDependencyReconciliation -FeatureDirectory $FeatureDirectory
                } (Join-Path $fixture 'feature')
            } | Should -Throw "*$Error*"
            & $script:ralphModule {
                param($Path)
                Get-TrackerTicketStatus -Path $Path
            } (Join-Path $issues '01-first.md') | Should -Be 'ready-for-agent'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'completes only the validated tracker status declaration in process' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Complete.' + [guid]::NewGuid().ToString('N')
        )
        $ticketPath = Join-Path $fixture 'feature\issues\01.done.md'
        try {
            New-Item -ItemType Directory -Path (Split-Path $ticketPath) -Force | Out-Null
            Set-Content -LiteralPath $ticketPath -Value @'
# Ticket

```md
Status: ready-for-agent
```

## Work

**Status:** ready-for-agent
'@
            $entry = [pscustomobject]@{
                feature = 'feature'
                ticket = '01.done'
                changes = 'implemented'
                checks = 'passed'
            }
            $completed = & $script:ralphModule {
                param($Scratch, $Progress)
                Complete-TrackerTicket -ScratchDirectory $Scratch -ProgressEntry $Progress
            } $fixture $entry

            $completed | Should -Be '01.done'
            $content = Get-Content -LiteralPath $ticketPath -Raw
            $content | Should -Match '(?m)^Status: ready-for-agent\r?$'
            $content | Should -Match '(?m)^\*\*Status:\*\* done\r?$'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'enforces progress tracker ownership in process' -TestCases @(
        @{ Name = 'mismatched feature scope'; EntryFeature = 'other'; Ticket = '01'; Scope = 'feature'; ScopeFeature = 'feature'; Error = 'does not match requested feature' },
        @{ Name = 'missing ticket'; EntryFeature = 'feature'; Ticket = '99'; Scope = 'automatic'; ScopeFeature = ''; Error = 'Unfinished tracker ticket not found' },
        @{ Name = 'already completed ticket'; EntryFeature = 'feature'; Ticket = '02'; Scope = 'automatic'; ScopeFeature = ''; Error = 'already completed' }
    ) {
        param($Name, $EntryFeature, $Ticket, $Scope, $ScopeFeature, $Error)

        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Ownership.' + [guid]::NewGuid().ToString('N')
        )
        try {
            $issues = Join-Path $fixture 'feature\issues'
            New-Item -ItemType Directory -Path $issues -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $issues '01.md') -Value "# Open`n`nStatus: ready-for-agent"
            Set-Content -LiteralPath (Join-Path $issues '02.md') -Value "# Done`n`nStatus: done"
            $entry = [pscustomobject]@{
                feature = $EntryFeature
                ticket = $Ticket
                changes = 'implemented'
                checks = 'passed'
            }

            {
                & $script:ralphModule {
                    param($Scratch, $Progress, $ScopeKind, $RequestedFeature)
                    Assert-ProgressEntryMatchesScope -ProgressEntry $Progress `
                        -ScopeKind $ScopeKind -ScopeFeature $RequestedFeature | Out-Null
                    Complete-TrackerTicket -ScratchDirectory $Scratch -ProgressEntry $Progress
                } $fixture $entry $Scope $ScopeFeature
            } | Should -Throw "*$Error*"
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'formats, archives, and cleans tracker fixtures in process' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Tracker.' + [guid]::NewGuid().ToString('N')
        )
        $scratch = Join-Path $fixture '.scratch'
        try {
            foreach ($feature in 'alpha-feature', 'complete-feature', 'single-feature', 'zeta-feature') {
                New-Item -ItemType Directory -Path (Join-Path $scratch "$feature\issues") -Force | Out-Null
            }
            Set-Content -LiteralPath (Join-Path $scratch 'alpha-feature\spec.md') -Value '# Alpha display'
            Set-Content -LiteralPath (Join-Path $scratch 'complete-feature\spec.md') -Value '# Complete display'
            Set-Content -LiteralPath (Join-Path $scratch 'single-feature\spec.md') -Value '# Single display'
            Set-Content -LiteralPath (Join-Path $scratch 'zeta-feature\spec.md') -Value '# Zeta display'
            Set-Content -LiteralPath (Join-Path $scratch 'alpha-feature\issues\10.md') -Value "# Tenth`n`nStatus: ready-for-agent"
            Set-Content -LiteralPath (Join-Path $scratch 'alpha-feature\issues\2.md') -Value "# Second`n`nStatus: ready-for-agent"
            Set-Content -LiteralPath (Join-Path $scratch 'alpha-feature\issues\01.done.md') -Value "# Finished`n`nStatus: done"
            Set-Content -LiteralPath (Join-Path $scratch 'complete-feature\issues\01.md') -Value "# Complete done`n`nStatus: done"
            Set-Content -LiteralPath (Join-Path $scratch 'complete-feature\issues\02.md') -Value "# Complete closed`n`nStatus: closed"
            Set-Content -LiteralPath (Join-Path $scratch 'single-feature\issues\01.md') -Value "# Single done`n`nStatus: done"
            Set-Content -LiteralPath (Join-Path $scratch 'zeta-feature\issues\01.md') -Value "# Zeta`n`nStatus: ready-for-agent"
            New-Item -ItemType Directory -Path (Join-Path $scratch 'partial-feature') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $scratch 'partial-feature\spec.md') -Value 'Specification without a heading'
            New-Item -ItemType Directory -Path (Join-Path $scratch 'done\archived-feature') -Force | Out-Null

            $lines = & $script:ralphModule {
                param($Scratch)
                Get-TrackerLines -ScratchDirectory $Scratch -Repository 'repository' -IncludeIteration:$false
            } $scratch
            $text = ($lines -join "`n") -replace "$([char]27)\[[0-9;]*m", ''
            $text.IndexOf('Alpha display') | Should -BeLessThan $text.IndexOf('Zeta display')
            $text.IndexOf('Finished') | Should -BeLessThan $text.IndexOf('Second')
            $text.IndexOf('Second') | Should -BeLessThan $text.IndexOf('Tenth')
            $text | Should -Match 'Complete display'
            $text | Should -Match 'All 2 issues completed'
            $text | Should -Not -Match 'Complete done'
            $text | Should -Not -Match 'Complete closed'
            $text | Should -Match 'Single display'
            $text | Should -Match 'All 1 issue completed'
            $text | Should -Not -Match 'Single done'
            $text | Should -Not -Match 'archived-feature'
            $text | Should -Match 'partial-feature'
            $text | Should -Match 'no tickets'

            $unfinishedArchive = & $script:ralphModule {
                param($Scratch)
                Move-CompletedTrackerFeature -ScratchDirectory $Scratch -Feature 'alpha-feature'
            } $scratch
            $unfinishedArchive | Should -BeNullOrEmpty
            Set-Content -LiteralPath (Join-Path $scratch 'alpha-feature\issues\10.md') -Value "# Tenth`n`nStatus: done"
            Set-Content -LiteralPath (Join-Path $scratch 'alpha-feature\issues\2.md') -Value "# Second`n`nStatus: done"
            New-Item -ItemType Directory -Path (Join-Path $scratch 'done\alpha-feature') -Force | Out-Null
            $archive = & $script:ralphModule {
                param($Scratch)
                Move-CompletedTrackerFeature -ScratchDirectory $Scratch -Feature 'alpha-feature'
            } $scratch
            (Split-Path $archive -Leaf) | Should -Be 'alpha-feature-2'
            Test-Path -LiteralPath (Join-Path $archive 'issues\01.done.md') | Should -BeTrue

            $progress = Join-Path $scratch 'progress.jsonl'
            Set-Content -LiteralPath $progress -Value '{"feature":"feature","ticket":"01","changes":"done","checks":"passed"}'
            & $script:ralphModule {
                param($Scratch)
                Invoke-RalphCleanup -ScratchDirectory $Scratch
            } $scratch | Out-Null
            Test-Path -LiteralPath (Join-Path $scratch 'done') | Should -BeTrue
            @(Get-ChildItem -LiteralPath (Join-Path $scratch 'done') -Directory).Count | Should -Be 0
            Test-Path -LiteralPath (Join-Path $scratch 'zeta-feature') | Should -BeTrue
            Get-Content -LiteralPath $progress -Raw | Should -Match '"feature":"feature"'

            New-Item -ItemType Directory -Path (Join-Path $scratch 'done\unsafe_archive') -Force | Out-Null
            {
                & $script:ralphModule {
                    param($Scratch)
                    Invoke-RalphCleanup -ScratchDirectory $Scratch
                } $scratch | Out-Null
            } | Should -Throw '*Unsafe archived feature directory*'
            Test-Path -LiteralPath (Join-Path $scratch 'done\unsafe_archive') | Should -BeTrue
            Remove-Item -LiteralPath (Join-Path $scratch 'done\unsafe_archive') -Recurse -Force

            Remove-Item -LiteralPath (Join-Path $scratch 'zeta-feature') -Recurse -Force
            Remove-Item -LiteralPath (Join-Path $scratch 'complete-feature') -Recurse -Force
            Remove-Item -LiteralPath (Join-Path $scratch 'single-feature') -Recurse -Force
            Remove-Item -LiteralPath (Join-Path $scratch 'partial-feature') -Recurse -Force
            $emptyLines = & $script:ralphModule {
                param($Scratch)
                Get-TrackerLines -ScratchDirectory $Scratch -IncludeIteration:$false
            } $scratch
            ($emptyLines -join "`n") | Should -Match 'No active features'
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'collapses inactive specs when tracker space is constrained' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.CompactTracker.' + [guid]::NewGuid().ToString('N')
        )
        $scratch = Join-Path $fixture '.scratch'
        try {
            foreach ($feature in 'alpha', 'beta', 'gamma') {
                $issues = Join-Path $scratch "$feature\issues"
                New-Item -ItemType Directory -Path $issues -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $scratch "$feature\spec.md") -Value "# $feature display"
                Set-Content -LiteralPath (Join-Path $issues '01.md') -Value "# $feature ticket`n`nStatus: ready-for-agent"
            }

            $lines = & $script:ralphModule {
                param($Scratch)
                Get-AdaptiveTrackerLines -ScratchDirectory $Scratch `
                    -WorkingFeatureName 'beta' -WindowHeight 18
            } $scratch
            $rawText = $lines -join "`n"
            $text = $rawText -replace "$([char]27)\[[0-9;]*m", ''

            $text | Should -Match 'beta ticket'
            $text | Should -Not -Match 'alpha ticket|gamma ticket'
            $text | Should -Match '▸ alpha display.*1 open issue'
            $text | Should -Match '▸ gamma display.*1 open issue'
            $escape = [regex]::Escape([string][char]27)
            $expandedTitle = [regex]::Match(
                $rawText,
                "(?<Style>${escape}\[[0-9;]*m)beta display(?<Reset>${escape}\[[0-9;]*m)"
            )
            $expandedFolder = [regex]::Match(
                $rawText,
                "(?<Style>${escape}\[[0-9;]*m)\(beta\)(?<Reset>${escape}\[[0-9;]*m)"
            )
            $expandedTitle.Success | Should -BeTrue
            $expandedFolder.Success | Should -BeTrue
            $rawText.Contains(
                "$($expandedTitle.Groups['Style'].Value)alpha display$($expandedTitle.Groups['Reset'].Value)"
            ) | Should -BeTrue
            $rawText.Contains(
                "$($expandedFolder.Groups['Style'].Value)(alpha)$($expandedFolder.Groups['Reset'].Value)"
            ) | Should -BeTrue
            $lines.Count | Should -BeLessOrEqual 8
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'sorts specs by title instead of feature directory name' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.SpecTitleSort.' + [guid]::NewGuid().ToString('N')
        )
        $scratch = Join-Path $fixture '.scratch'
        try {
            foreach ($feature in @(
                @{ Directory = 'alpha-folder'; Title = 'Zulu spec' },
                @{ Directory = 'finding-15'; Title = 'Finding 15: Later' },
                @{ Directory = 'finding-5'; Title = 'Finding 5: Earlier' },
                @{ Directory = 'zeta-folder'; Title = 'Alpha spec' }
            )) {
                $issues = Join-Path $scratch "$($feature.Directory)\issues"
                New-Item -ItemType Directory -Path $issues -Force | Out-Null
                Set-Content -LiteralPath (
                    Join-Path $scratch "$($feature.Directory)\spec.md"
                ) -Value "# $($feature.Title)"
                Set-Content -LiteralPath (Join-Path $issues '01.md') -Value (
                    "# Ticket`n`nStatus: ready-for-agent"
                )
            }

            $lines = & $script:ralphModule {
                param($Scratch)
                Get-TrackerLines -ScratchDirectory $Scratch -IncludeIteration:$false
            } $scratch
            $text = ($lines -join "`n") -replace "$([char]27)\[[0-9;]*m", ''

            $text.IndexOf('Alpha spec') | Should -BeLessThan $text.IndexOf('Zulu spec')
            $text.IndexOf('Finding 5:') | Should -BeLessThan $text.IndexOf('Finding 15:')
        }
        finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'renders and refreshes the workboard in process' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Workboard.' + [guid]::NewGuid().ToString('N')
        )
        $scratch = Join-Path $fixture '.scratch'
        $writer = [System.IO.StringWriter]::new()
        $originalWriter = [Console]::Out
        try {
            New-Item -ItemType Directory -Path (Join-Path $scratch 'feature\issues') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $scratch 'feature\spec.md') -Value '# Feature'
            Set-Content -LiteralPath (Join-Path $scratch 'feature\issues\01.md') -Value (
                "# First ticket`n`nStatus: ready-for-agent"
            )
            [Console]::SetOut($writer)

            $state = & $script:ralphModule {
                param($Scratch)
                Enter-RalphWorkboard -ScratchDirectory $Scratch -Repository 'repository' `
                    -AgentSummary 'codex / test (medium)' -CurrentIteration 1 -TotalIterations 2
            } $scratch
            $initial = $writer.ToString()
            $initial | Should -Match 'Ralph tracker'
            $initial | Should -Match 'Agent output'
            $initial | Should -Match 'Repository:'
            $initial | Should -Match "`e\[2J"
            $initial | Should -Match "`e\[\?25l"
            $initial | Should -Match "`e\[\d+;\d+r"
            $state.RetainedFeatureNames | Should -Contain 'feature'

            $writer.GetStringBuilder().Clear() | Out-Null
            $state = & $script:ralphModule {
                param($Scratch, $WorkboardState)
                Update-RalphWorkboard -ScratchDirectory $Scratch -State $WorkboardState `
                    -WindowWidth 60 -WindowHeight 18 -ForceFullRedraw
            } $scratch $state
            $widthRefresh = $writer.ToString()
            $widthRefresh | Should -Match "`e\[2J"
            $state.InnerWidth | Should -Be 56
            $state.WindowWidth | Should -Be 60

            $writer.GetStringBuilder().Clear() | Out-Null
            $env:RALPH_TEST_WORKBOARD_DIMENSIONS = '60x18'
            $unchanged = & $script:ralphModule {
                param($Scratch, $WorkboardState)
                Remove-Variable -Name RalphTestDimensionQueue -Scope Script -ErrorAction SilentlyContinue
                Refresh-RalphWorkboardForResize -ScratchDirectory $Scratch -State $WorkboardState
            } $scratch $state
            $writer.ToString() | Should -Be ''
            $unchanged.WindowWidth | Should -Be 60

            $writer.GetStringBuilder().Clear() | Out-Null
            $env:RALPH_TEST_WORKBOARD_DIMENSIONS = '40x14'
            $heightRefresh = & $script:ralphModule {
                param($Scratch, $WorkboardState)
                Remove-Variable -Name RalphTestDimensionQueue -Scope Script -ErrorAction SilentlyContinue
                Refresh-RalphWorkboardForResize -ScratchDirectory $Scratch -State $WorkboardState
            } $scratch $state
            $heightOutput = $writer.ToString()
            $heightOutput | Should -Match "`e\[2J"
            $heightOutput | Should -Match "`e\[\d+;13r"
            $heightRefresh.WindowHeight | Should -Be 14

            $writer.GetStringBuilder().Clear() | Out-Null
            $env:RALPH_TEST_WORKBOARD_DIMENSIONS = '40x5'
            $deferred = & $script:ralphModule {
                param($Scratch, $WorkboardState)
                Remove-Variable -Name RalphTestDimensionQueue -Scope Script -ErrorAction SilentlyContinue
                Refresh-RalphWorkboardForResize -ScratchDirectory $Scratch -State $WorkboardState
            } $scratch $heightRefresh
            $writer.ToString() | Should -Be ''
            $deferred.WindowHeight | Should -Be 14

            $writer.GetStringBuilder().Clear() | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $scratch 'later-feature\issues') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $scratch 'later-feature\spec.md') -Value '# Later feature'
            Set-Content -LiteralPath (Join-Path $scratch 'later-feature\issues\01.md') -Value (
                "# Later ticket`n`nStatus: ready-for-agent"
            )
            $recovered = & $script:ralphModule {
                param($Scratch, $WorkboardState)
                Update-RalphWorkboard -ScratchDirectory $Scratch -State $WorkboardState `
                    -WindowWidth 40 -WindowHeight 18 -ForceFullRedraw
            } $scratch $deferred
            $recoveredOutput = $writer.ToString()
            $recoveredOutput | Should -Match 'Later feature'
            $recoveredOutput | Should -Match "`e\[\d+;17r"

            $writer.GetStringBuilder().Clear() | Out-Null
            Set-Content -LiteralPath (Join-Path $scratch 'feature\issues\01.md') -Value (
                "# First ticket`n`nStatus: done"
            )
            New-Item -ItemType Directory -Path (Join-Path $scratch 'done') -Force | Out-Null
            Move-Item -LiteralPath (Join-Path $scratch 'feature') -Destination (Join-Path $scratch 'done\feature') -Force
            $completed = & $script:ralphModule {
                param($Scratch, $WorkboardState)
                Update-RalphWorkboard -ScratchDirectory $Scratch -State $WorkboardState
            } $scratch $recovered
            $completionOutput = $writer.ToString()
            $completionOutput | Should -Match '\[✓\]'
            $completionOutput | Should -Not -Match 'later-feature.*\[✓\]'

            $writer.GetStringBuilder().Clear() | Out-Null
            & $script:ralphModule {
                param($WorkboardState)
                Exit-RalphWorkboard -State $WorkboardState
            } $completed
            $exitOutput = $writer.ToString()
            $exitOutput | Should -Match "`e\[r"
            $exitOutput | Should -Match "`e\[\d+;1H"
            $exitOutput | Should -Match "`e\[\?25h"
        }
        finally {
            [Console]::SetOut($originalWriter)
            Remove-Item Env:RALPH_TEST_WORKBOARD_DIMENSIONS -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
        [Console]::Out | Should -Be $originalWriter
    }

    It 'keeps every visible Agent output row framed after repeated typed and plain scrolling' {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('Invoke-Ralph.Scroll.' + [guid]::NewGuid().ToString('N'))
        $scratch = Join-Path $fixture '.scratch'
        $writer = [System.IO.StringWriter]::new()
        $originalWriter = [Console]::Out
        try {
            New-Item -ItemType Directory -Path (Join-Path $scratch 'feature\issues') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $scratch 'feature\spec.md') -Value '# Feature'
            Set-Content -LiteralPath (Join-Path $scratch 'feature\issues\01.md') -Value "# Ticket`n`nStatus: ready-for-agent"
            [Console]::SetOut($writer)
            $state = & $script:ralphModule {
                param($Scratch)
                Enter-RalphWorkboard -ScratchDirectory $Scratch -Repository 'repository' -AgentSummary 'codex / test (medium)' -CurrentIteration 1 -TotalIterations 1
            } $scratch
            & $script:ralphModule {
                param($WorkboardState)
                for ($index = 0; $index -lt 40; $index++) {
                    if ($index -lt 8) {
                        Write-TypedAgentOutputRow -Content "`e[36mtyped $index 漢`e[0m" -ContentWidth 10 -InnerWidth $WorkboardState.InnerWidth -WorkboardState $WorkboardState
                    }
                    else {
                        Write-AgentOutputRow -Content $(if ($index % 5 -eq 0) { '' } else { "plain $index" }) -InnerWidth $WorkboardState.InnerWidth -WorkboardState $WorkboardState
                    }
                }
            } $state

            $screen = ConvertFrom-RalphTerminalOutput -Output $writer.ToString() -Width $state.WindowWidth -Height $state.WindowHeight
            $screen.Cells[($state.BottomRow - 1), 0] | Should -Be '╰' -Because $screen.Snapshot
            for ($row = ($state.ScrollTop - 1); $row -lt $state.MessageBottom; $row++) {
                $screen.Cells[$row, 0] | Should -Be '│' -Because $screen.Snapshot
                $screen.Cells[$row, ($state.WindowWidth - 1)] | Should -Be '│' -Because $screen.Snapshot
            }

            $state = & $script:ralphModule {
                param($Scratch, $WorkboardState)
                Update-RalphWorkboard -ScratchDirectory $Scratch -State $WorkboardState
            } $scratch $state
            & $script:ralphModule {
                param($WorkboardState)
                Write-AgentOutputRow -Content 'after tracker refresh' -InnerWidth $WorkboardState.InnerWidth -WorkboardState $WorkboardState
            } $state
            $screen = ConvertFrom-RalphTerminalOutput -Output $writer.ToString() -Width $state.WindowWidth -Height $state.WindowHeight
            for ($row = ($state.ScrollTop - 1); $row -lt $state.MessageBottom; $row++) {
                $screen.Cells[$row, 0] | Should -Be '│' -Because $screen.Snapshot
                $screen.Cells[$row, ($state.WindowWidth - 1)] | Should -Be '│' -Because $screen.Snapshot
            }

            $writer.GetStringBuilder().Clear() | Out-Null
            $state = & $script:ralphModule {
                param($Scratch, $WorkboardState)
                Update-RalphWorkboard -ScratchDirectory $Scratch -State $WorkboardState `
                    -WindowWidth 40 -WindowHeight 14 -ForceFullRedraw
            } $scratch $state
            & $script:ralphModule {
                param($WorkboardState)
                Write-TypedAgentOutputRow -Content 'after resize' -ContentWidth 12 -InnerWidth $WorkboardState.InnerWidth -WorkboardState $WorkboardState
            } $state
            $screen = ConvertFrom-RalphTerminalOutput -Output $writer.ToString() -Width 40 -Height 14
            $screen.Cells[($state.BottomRow - 1), 0] | Should -Be '╰' -Because $screen.Snapshot
            for ($row = ($state.ScrollTop - 1); $row -lt $state.MessageBottom; $row++) {
                $screen.Cells[$row, 0] | Should -Be '│' -Because $screen.Snapshot
                $screen.Cells[$row, 39] | Should -Be '│' -Because $screen.Snapshot
            }

            $writer.GetStringBuilder().Clear() | Out-Null
            $deferred = & $script:ralphModule {
                param($Scratch, $WorkboardState)
                Update-RalphWorkboard -ScratchDirectory $Scratch -State $WorkboardState `
                    -WindowWidth 40 -WindowHeight 5 -ForceFullRedraw
            } $scratch $state
            $writer.ToString() | Should -Be ''
            $deferred.WindowHeight | Should -Be 14

            $state = & $script:ralphModule {
                param($Scratch, $WorkboardState)
                Update-RalphWorkboard -ScratchDirectory $Scratch -State $WorkboardState `
                    -WindowWidth 40 -WindowHeight 18 -ForceFullRedraw
            } $scratch $deferred
            & $script:ralphModule {
                param($WorkboardState)
                Write-AgentOutputRow -Content 'after resize recovery' -InnerWidth $WorkboardState.InnerWidth -WorkboardState $WorkboardState
                Compact-AgentOutputPanel -State $WorkboardState
                Exit-RalphWorkboard -State $WorkboardState
            } $state
            $screen = ConvertFrom-RalphTerminalOutput -Output $writer.ToString() -Width 40 -Height 18
            $screen.Cells[($state.BottomRow - 1), 0] | Should -Be '╰' -Because $screen.Snapshot
            for ($row = ($state.ScrollTop - 1); $row -lt $state.MessageBottom; $row++) {
                $screen.Cells[$row, 0] | Should -Be '│' -Because $screen.Snapshot
                $screen.Cells[$row, 39] | Should -Be '│' -Because $screen.Snapshot
            }
        }
        finally {
            [Console]::SetOut($originalWriter)
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Command' -Tag 'Command' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestSupport.ps1')

        $script:ralphScript = (Get-Item -LiteralPath (
            Join-Path $PSScriptRoot '..\Startup\Invoke-Ralph.ps1'
        )).FullName
        $script:pwsh = (Get-Command pwsh -ErrorAction Stop).Source
        $script:temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Invoke-Ralph.Tests.' + [guid]::NewGuid().ToString('N')
        )
        $script:originalPath = $env:PATH
        $script:commandRunner = Join-Path $temporaryRoot 'run-ralph.ps1'
        function Invoke-Git {
            param([string] $Repository, [string[]] $Arguments)

            $result = Invoke-BoundedProcess -FilePath 'git' -ArgumentList (
                @('-C', $Repository) + $Arguments
            ) -TimeoutSeconds 30
            if ($result.ExitCode -ne 0) {
                throw "git $($Arguments -join ' ') failed with exit code $($result.ExitCode): $($result.Command)`nstdout:`n$($result.StdOut)`nstderr:`n$($result.StdErr)"
            }

            return $result.StdOut.TrimEnd([char[]]"`r`n")
        }

        function Set-TestTicket {
            param([string] $Path, [string] $Heading, [string] $Status = 'ready-for-agent')

            Set-Content -LiteralPath $Path -Value (
                "$Heading`n`nBlocked by: None — can start immediately`n`nStatus: $Status"
            )
        }

        New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
        @'
param(
    [Parameter(Mandatory)][string] $TargetScript,
    [Parameter(Mandatory)][string] $PwshPath,
    [Parameter(Mandatory)][string] $EncodedArguments
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$scriptArguments = @(
    [System.Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($EncodedArguments)
    ) | ConvertFrom-Json
)
& $PwshPath -NoProfile -File $TargetScript @scriptArguments
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $commandRunner -Encoding Ascii -NoNewline

        $script:commandBaseline = Join-Path $temporaryRoot 'baseline'
        New-Item -ItemType Directory -Path (Join-Path $commandBaseline '.scratch\feature\issues') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $commandBaseline '.gitignore') -Value ".scratch/`n"
        Set-Content -LiteralPath (Join-Path $commandBaseline 'baseline.txt') -Value "baseline`n"
        Set-Content -LiteralPath (Join-Path $commandBaseline '.scratch\feature\spec.md') -Value '# Feature'
        Set-TestTicket -Path (Join-Path $commandBaseline '.scratch\feature\issues\01.md') -Heading '# Ticket'
        Invoke-Git $commandBaseline @('init', '--quiet') | Out-Null
        Invoke-Git $commandBaseline @('config', 'user.name', 'Ralph Tests') | Out-Null
        Invoke-Git $commandBaseline @('config', 'user.email', 'ralph-tests@example.invalid') | Out-Null
        Invoke-Git $commandBaseline @('add', '--force', '.gitignore', 'baseline.txt', '.scratch') | Out-Null
        Invoke-Git $commandBaseline @('commit', '--quiet', '--message', 'baseline') | Out-Null

        $script:commandAgentDirectory = Join-Path $temporaryRoot 'agents'
        New-Item -ItemType Directory -Path $commandAgentDirectory | Out-Null
        $fakeAgent = @'
param([Parameter(ValueFromRemainingArguments)] [string[]] $AgentArguments)
$ErrorActionPreference = 'Stop'
[System.IO.File]::WriteAllLines($env:RALPH_ARGUMENT_LOG, $AgentArguments)
$root = (& git rev-parse --show-toplevel).Trim()
$progress = Join-Path $root '.scratch\progress.jsonl'
$record = '{"feature":"feature","ticket":"01","changes":"implemented","checks":"passed"}'
$completedMessage = if ($env:RALPH_SCENARIO -eq 'rich-markdown') {
    @(
        'completed message',
        '',
        '```powershell',
        "`$value = `t漢",
        'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz',
        '```',
        '',
        '---',
        '',
        '<div>literal <em>HTML</em></div>',
        '',
        'See [the linked reference](https://example.com/reference) and [https://example.com/same](https://example.com/same).',
        '',
        '![architecture diagram](https://example.com/diagram.svg)',
        '',
        '| Name | Score | Notes |',
        '| :--- | ---: | :---: |',
        '| Alpha | 42 | 漢字 with deliberately long table content |'
    ) -join [Environment]::NewLine
}
else {
    'completed message'
}
[System.IO.File]::AppendAllText(
    $env:RALPH_INVOCATION_LOG,
    (($AgentArguments | ConvertTo-Json -Compress) + [Environment]::NewLine)
)

switch ($env:RALPH_SCENARIO) {
    'agent-failure' {
        Write-Output 'codex raw tool result'
        Write-Output 'codex stderr diagnostic'
        exit 7
    }
    'invalid-handoff' {
        Set-Content -LiteralPath (Join-Path $root 'work.txt') -Value 'implemented'
        Write-Output 'agent omitted the required handoff'
        break
    }
    'scratch-staged' {
        Set-Content -LiteralPath (Join-Path $root '.scratch\agent-staged.txt') -Value 'must remain local'
        & git add --force -- .scratch
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Set-Content -LiteralPath (Join-Path $root 'work.txt') -Value 'implemented'
        Add-Content -LiteralPath $progress -Value $record
        break
    }
    'automatic' {
        $next = Get-ChildItem -LiteralPath (Join-Path $root '.scratch') -Directory |
            Where-Object { $_.Name -cne 'done' } |
            Sort-Object Name |
            ForEach-Object {
                $ticket = Get-ChildItem -LiteralPath (Join-Path $_.FullName 'issues') -File -Filter '*.md' |
                    Where-Object {
                        (Get-Content -LiteralPath $_.FullName -Raw) -match '(?im)^Status:\s*ready-for-agent\s*$'
                    } |
                    Sort-Object Name |
                    Select-Object -First 1
                if ($ticket) {
                    [pscustomobject]@{ Feature = $_.Name; Ticket = $ticket.BaseName }
                }
            } |
            Select-Object -First 1
        Set-Content -LiteralPath (Join-Path $root "work-$($next.Feature)-$($next.Ticket).txt") -Value 'implemented'
        Add-Content -LiteralPath $progress -Value (
            [pscustomobject]@{
                feature = $next.Feature
                ticket = $next.Ticket
                changes = 'implemented'
                checks = 'passed'
            } | ConvertTo-Json -Compress
        )
        break
    }
    'unterminated-handoff' {
        $next = Get-ChildItem -LiteralPath (Join-Path $root '.scratch\feature\issues') -File -Filter '*.md' |
            Where-Object {
                (Get-Content -LiteralPath $_.FullName -Raw) -match '(?im)^Status:\s*ready-for-agent\s*$'
            } |
            Sort-Object Name |
            Select-Object -First 1
        Set-Content -LiteralPath (Join-Path $root "work-$($next.BaseName).txt") -Value 'implemented'
        $nextRecord = [pscustomobject]@{
            feature = 'feature'
            ticket = $next.BaseName
            changes = 'implemented'
            checks = 'passed'
        } | ConvertTo-Json -Compress
        [System.IO.File]::AppendAllText(
            $progress,
            $nextRecord,
            [System.Text.UTF8Encoding]::new($false)
        )
        break
    }
    'post-reconciliation' {
        Set-Content -LiteralPath (Join-Path $root 'work.txt') -Value 'implemented'
        Add-Content -LiteralPath $progress -Value (
            '{"feature":"feature","ticket":"03","changes":"implemented","checks":"passed"}'
        )
        break
    }
    default {
        Set-Content -LiteralPath (Join-Path $root 'work.txt') -Value 'implemented'
        Add-Content -LiteralPath $progress -Value $record
        if ($AgentArguments -contains '--json') {
            @(
                @{ type = 'item.updated'; item = @{ type = 'agent_message'; text = 'transient output' } }
                @{ id = 'event-1'; type = 'item.completed'; item = @{ id = 'message-1'; type = 'agent_message'; text = $completedMessage } }
                @{ id = 'event-1'; type = 'item.completed'; item = @{ id = 'message-1'; type = 'agent_message'; text = $completedMessage } }
            ) | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 4 }
        }
        else {
            @(
                @{ type = 'assistant.message_delta'; data = @{ content = 'transient output' } }
                @{ id = 'event-1'; type = 'assistant.message'; data = @{ message = @{ id = 'message-1'; content = $completedMessage } } }
                @{ id = 'event-1'; type = 'assistant.message'; data = @{ message = @{ id = 'message-1'; content = $completedMessage } } }
            ) | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 5 }
        }
        if ($env:RALPH_SCENARIO -ne 'rich-markdown') {
            Write-Output "`e[36mraw diagnostic`e[0m"
        }
    }
}
'@
        foreach ($agentName in 'codex', 'copilot') {
            Set-Content -LiteralPath (Join-Path $commandAgentDirectory "$agentName.ps1") -Value $fakeAgent
        }

        function New-RalphCommandScenario {
            param([Parameter(Mandatory)][string] $Name)

            $repository = Join-Path $script:temporaryRoot "scenario-$Name"
            Invoke-Git $script:commandBaseline @('clone', '--quiet', $script:commandBaseline, $repository) | Out-Null
            return $repository
        }

        function Invoke-RalphCommandScenario {
            param(
                [Parameter(Mandatory)][string] $Name,
                [ValidateSet('codex', 'copilot')][string] $Agent = 'codex',
                [string] $Scenario = 'success',
                [switch] $Interactive,
                [string] $WorkboardDimensions = '',
                [string[]] $RalphArguments = @('-Agent', $Agent, '-Feature', 'feature', '-Iterations', '1'),
                [scriptblock] $Setup
            )

            $repository = New-RalphCommandScenario -Name $Name
            $argumentLog = Join-Path $script:temporaryRoot "scenario-$Name.args"
            $invocationLog = Join-Path $script:temporaryRoot "scenario-$Name.invocations"
            $previousPath = $env:PATH
            $previousScenario = $env:RALPH_SCENARIO
            $previousArgumentLog = $env:RALPH_ARGUMENT_LOG
            $previousInvocationLog = $env:RALPH_INVOCATION_LOG
            $previousInteractive = $env:RALPH_FORCE_INTERACTIVE
            $previousWorkboardDimensions = $env:RALPH_TEST_WORKBOARD_DIMENSIONS
            try {
                if ($Setup) {
                    & $Setup $repository
                }
                $env:PATH = "$script:commandAgentDirectory;$previousPath"
                $env:RALPH_SCENARIO = $Scenario
                $env:RALPH_ARGUMENT_LOG = $argumentLog
                $env:RALPH_INVOCATION_LOG = $invocationLog
                if ($Interactive) { $env:RALPH_FORCE_INTERACTIVE = '1' }
                if ($WorkboardDimensions) {
                    $env:RALPH_TEST_WORKBOARD_DIMENSIONS = $WorkboardDimensions
                }
                $encodedArguments = [Convert]::ToBase64String(
                    [System.Text.Encoding]::UTF8.GetBytes(
                        (ConvertTo-Json -InputObject $RalphArguments -Compress)
                    )
                )
                $process = Invoke-BoundedProcess -FilePath $script:pwsh -ArgumentList @(
                    '-NoProfile', '-File', $script:commandRunner,
                    '-TargetScript', $script:ralphScript,
                    '-PwshPath', $script:pwsh,
                    '-EncodedArguments', $encodedArguments
                ) -WorkingDirectory $repository -TimeoutSeconds 90
                $output = @($process.StdOut, $process.StdErr) |
                    Where-Object { -not [string]::IsNullOrEmpty($_) } |
                    Join-String -Separator "`n"
                $output = $output -replace "`r`n?", "`n"
                $exitCode = $process.ExitCode
            }
            finally {
                $env:PATH = $previousPath
                if ($null -eq $previousScenario) { Remove-Item Env:RALPH_SCENARIO -ErrorAction SilentlyContinue } else { $env:RALPH_SCENARIO = $previousScenario }
                if ($null -eq $previousArgumentLog) { Remove-Item Env:RALPH_ARGUMENT_LOG -ErrorAction SilentlyContinue } else { $env:RALPH_ARGUMENT_LOG = $previousArgumentLog }
                if ($null -eq $previousInvocationLog) { Remove-Item Env:RALPH_INVOCATION_LOG -ErrorAction SilentlyContinue } else { $env:RALPH_INVOCATION_LOG = $previousInvocationLog }
                if ($null -eq $previousInteractive) { Remove-Item Env:RALPH_FORCE_INTERACTIVE -ErrorAction SilentlyContinue } else { $env:RALPH_FORCE_INTERACTIVE = $previousInteractive }
                if ($null -eq $previousWorkboardDimensions) { Remove-Item Env:RALPH_TEST_WORKBOARD_DIMENSIONS -ErrorAction SilentlyContinue } else { $env:RALPH_TEST_WORKBOARD_DIMENSIONS = $previousWorkboardDimensions }
            }

            [pscustomobject]@{
                Repository = $repository
                ExitCode = $exitCode
                Output = ($output | ForEach-Object ToString) -join "`n"
                Arguments = @(Get-Content -LiteralPath $argumentLog -ErrorAction SilentlyContinue)
                Invocations = @(Get-Content -LiteralPath $invocationLog -ErrorAction SilentlyContinue)
            }
        }

        function Get-NonScratchStatus {
            param([Parameter(Mandatory)][string] $Repository)

            Invoke-Git $Repository @(
                'status', '--porcelain', '--untracked-files=all', '--', '.',
                ':(exclude).scratch/**'
            )
        }
    }


    It 'runs the Codex success lifecycle with semantic output and Git effects' {
        $result = Invoke-RalphCommandScenario -Name 'codex-success' -Agent codex -Scenario 'rich-markdown'

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Arguments | Should -Contain '--json'
        $result.Arguments | Should -Contain '--model'
        $result.Arguments | Should -Contain 'gpt-5.6-luna'
        $result.Arguments | Should -Contain 'model_reasoning_effort="medium"'
        [regex]::Matches($result.Output, 'completed message').Count | Should -Be 1
        $result.Output | Should -Not -Match 'transient output'
        $result.Output | Should -Match '(?m)^powershell$'
        $result.Output | Should -Match '\$value = {4}漢'
        $result.Output | Should -Match ('─' * 12)
        $result.Output | Should -Match '<div>literal <em>HTML</em></div>'
        $result.Output | Should -Match 'the linked reference \(https://example\.com/reference\)'
        [regex]::Matches($result.Output, 'https://example\.com/same').Count | Should -Be 1
        $result.Output | Should -Match 'Image: architecture diagram \(https://example\.com/diagram\.svg\)'
        $result.Output | Should -Match '\| Name +\| +Score +\| +Notes +\|'
        $result.Output | Should -Match '\|─+┼─+┼─+\|'
        $result.Output | Should -Match 'deliberately long table content'
        $result.Output | Should -Not -Match [regex]::Escape([string][char]27)
        (Get-Content -LiteralPath (Join-Path $result.Repository '.scratch\done\feature\issues\01.md') -Raw) |
            Should -Match '(?m)^Status: done\r?$'
        Invoke-Git $result.Repository @('log', '-1', '--format=%s') |
            Should -Be 'ralph: feature/01, FEATURE completed'
        Get-NonScratchStatus $result.Repository | Should -Be ''
    }

    It 'removes agent-staged scratch paths before committing' {
        $result = Invoke-RalphCommandScenario -Name 'scratch-staged' -Scenario 'scratch-staged'

        $result.ExitCode | Should -Be 0 -Because $result.Output
        Invoke-Git $result.Repository @('show', '--format=', '--name-only', 'HEAD') |
            Should -Not -Match '\.scratch[\\/]'
        Invoke-Git $result.Repository @('show', '--format=', '--name-only', 'HEAD') |
            Should -Match '(?m)^work\.txt$'
        Invoke-Git $result.Repository @('diff', '--cached', '--name-only') | Should -Be ''
        Test-Path -LiteralPath (Join-Path $result.Repository '.scratch\agent-staged.txt') |
            Should -BeTrue
        Invoke-Git $result.Repository @('ls-files', '--cached', '--', '.scratch/agent-staged.txt') |
            Should -BeNullOrEmpty
    }

    It 'runs the Copilot success lifecycle with its wire configuration' {
        $result = Invoke-RalphCommandScenario -Name 'copilot-success' -Agent copilot

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Arguments | Should -Contain '--output-format'
        $result.Arguments[$result.Arguments.IndexOf('--output-format') + 1] | Should -Be 'json'
        $result.Arguments | Should -Contain '--stream'
        $result.Arguments[$result.Arguments.IndexOf('--stream') + 1] | Should -Be 'off'
        $result.Arguments | Should -Contain '--effort'
        $result.Arguments[$result.Arguments.IndexOf('--effort') + 1] | Should -Be 'medium'
        [regex]::Matches($result.Output, 'completed message').Count | Should -Be 1
        $result.Output | Should -Not -Match 'transient output'
        $result.Output | Should -Match ([regex]::Escape("`e[36mraw diagnostic`e[0m"))
        Invoke-Git $result.Repository @('log', '-1', '--format=%s') |
            Should -Be 'ralph: feature/01, FEATURE completed'
        Get-NonScratchStatus $result.Repository | Should -Be ''
    }

    It 'surfaces a nonzero agent exit without committing' {
        $result = Invoke-RalphCommandScenario -Name 'agent-failure' -Agent codex -Scenario 'agent-failure'

        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'codex failed with exit code 7'
        $result.Output | Should -Not -Match 'codex raw tool result|codex stderr diagnostic'
        Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD') | Should -Be '1'
        Invoke-Git $result.Repository @('diff', '--cached', '--name-only') | Should -Be ''
    }

    It 'renders only completed Codex agent messages' {
        $result = Invoke-RalphCommandScenario -Name 'codex-noisy-success' -Agent codex

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'completed message'
        $result.Output | Should -Not -Match 'raw diagnostic|transient output'
    }

    It 'rejects an invalid handoff before staging and restores the terminal' {
        $result = Invoke-RalphCommandScenario -Name 'invalid-handoff' -Scenario 'invalid-handoff' -Interactive

        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'without updating .scratch/progress.jsonl'
        $result.Output | Should -Match ([regex]::Escape("`e[r"))
        $result.Output | Should -Match ([regex]::Escape("`e[?25h"))
        Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD') | Should -Be '1'
        Invoke-Git $result.Repository @('diff', '--cached', '--name-only') | Should -Be ''
    }

    It 'wires real interactive pacing, workboard completion, and terminal teardown' {
        $result = Invoke-RalphCommandScenario -Name 'interactive-success' -Agent codex -Scenario 'rich-markdown' -Interactive

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Ralph tracker'
        $result.Output | Should -Match 'completed message'
        $result.Output | Should -Match 'powershell'
        $result.Output | Should -Match '↪ '
        $result.Output | Should -Match ('─' * 12)
        $result.Output | Should -Match '<div>literal <em>HTML</em></div>'
        $result.Output | Should -Match ([regex]::Escape(
                "`e]8;;https://example.com/reference`e\the linked reference`e]8;;`e\"
            ))
        $result.Output | Should -Match ([regex]::Escape(
                "`e]8;;https://example.com/diagram.svg`e\Image: architecture diagram`e]8;;`e\"
            ))
        [regex]::Matches($result.Output, [regex]::Escape("`e]8;;`e\")).Count |
            Should -Be 3
        $result.Output | Should -Match '\| Name +\| +Score +\| +Notes +\|'
        $result.Output | Should -Match '\|─+┼─+┼─+\|'
        $result.Output | Should -Match ([regex]::Escape("`e[2J"))
        $result.Output | Should -Match ([regex]::Escape("`e[r"))
        $result.Output | Should -Match ([regex]::Escape("`e[?25h"))
        $result.Output | Should -Match 'Requested scope complete\.'
        Get-NonScratchStatus $result.Repository | Should -Be ''
    }

    It 'renders an impossible-width interactive table as vertical records' {
        $result = Invoke-RalphCommandScenario -Name 'interactive-narrow-table' `
            -Agent codex -Scenario 'rich-markdown' -Interactive `
            -WorkboardDimensions '18x24;18x24;18x24;18x24'

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Name: Alpha'
        $result.Output | Should -Match 'Score: 42'
        $result.Output | Should -Match 'Notes: 漢字'
        $result.Output | Should -Match 'deliberately'
        $result.Output | Should -Match 'long table'
        $result.Output | Should -Match 'content'
        $result.Output | Should -Not -Match '\| Name +\| +Score +\|'
        $hyperlinkOpens = [regex]::Matches(
            $result.Output,
            [regex]::Escape("`e]8;;https://")
        ).Count
        $hyperlinkCloses = [regex]::Matches(
            $result.Output,
            [regex]::Escape("`e]8;;`e\")
        ).Count
        $hyperlinkOpens | Should -BeGreaterThan 3
        $hyperlinkCloses | Should -Be $hyperlinkOpens
    }

    It 'runs list mode without invoking an agent or mutating the tracker' {
        $result = Invoke-RalphCommandScenario -Name 'list-mode' -RalphArguments @('-List')

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Feature'
        $result.Output | Should -Match 'Ticket'
        $result.Output | Should -Match 'feature'
        $result.Invocations | Should -BeNullOrEmpty
        (Get-Content -LiteralPath (Join-Path $result.Repository '.scratch\feature\issues\01.md') -Raw) |
            Should -Match '(?m)^Status: ready-for-agent\r?$'
        Get-NonScratchStatus $result.Repository | Should -Be ''
    }

    It 'runs archive mode without invoking an agent or changing progress history' {
        $progress = '{"feature":"previous","ticket":"00","changes":"done","checks":"passed"}'
        $result = Invoke-RalphCommandScenario -Name 'archive-mode' -RalphArguments @('-Archive', 'feature') -Setup {
            param($Repository)
            Set-Content -LiteralPath (Join-Path $Repository '.scratch\progress.jsonl') -Value $progress -NoNewline
        }

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match ([regex]::Escape("Archived feature 'feature' to:"))
        $result.Invocations | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $result.Repository '.scratch\feature') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $result.Repository '.scratch\done\feature\issues\01.md') | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $result.Repository '.scratch\progress.jsonl') -Raw |
            Should -Be $progress
        Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD') | Should -Be '1'
    }

    It 'runs cleanup mode while retaining active work and progress history' {
        $progress = '{"feature":"previous","ticket":"00","changes":"done","checks":"passed"}'
        $result = Invoke-RalphCommandScenario -Name 'cleanup-mode' -RalphArguments @('-Cleanup') -Setup {
            param($Repository)
            New-Item -ItemType Directory -Path (Join-Path $Repository '.scratch\done\completed-feature') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Repository '.scratch\done\completed-feature\preserve.txt') -Value 'remove me'
            Set-Content -LiteralPath (Join-Path $Repository '.scratch\progress.jsonl') -Value $progress -NoNewline
        }

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Cleanup complete: removed completed-feature\.'
        $result.Invocations | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $result.Repository '.scratch\done\completed-feature') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $result.Repository '.scratch\feature\issues\01.md') | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $result.Repository '.scratch\progress.jsonl') -Raw |
            Should -Be $progress
    }

    It 'repairs an unterminated progress history before an agent appends its handoff' {
        $previous = '{"feature":"previous","ticket":"00","changes":"done","checks":"passed"}'
        $result = Invoke-RalphCommandScenario -Name 'unterminated-progress-history' -Setup {
            param($Repository)
            [System.IO.File]::WriteAllText(
                (Join-Path $Repository '.scratch\progress.jsonl'),
                $previous,
                [System.Text.UTF8Encoding]::new($false)
            )
        }

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $progress = [System.IO.File]::ReadAllBytes(
            (Join-Path $result.Repository '.scratch\progress.jsonl')
        )
        $repairedHistory = [System.Text.Encoding]::UTF8.GetBytes($previous + "`n")
        $progress[0..($repairedHistory.Length - 1)] | Should -Be $repairedHistory
        $progress[$progress.Length - 1] | Should -Be 10
        @(Get-Content -LiteralPath (Join-Path $result.Repository '.scratch\progress.jsonl')).Count |
            Should -Be 2
        Invoke-Git $result.Repository @('log', '-1', '--format=%s') |
            Should -Be 'ralph: feature/01, FEATURE completed'
    }

    It 'normalizes validated unterminated handoffs before committing each iteration' {
        $result = Invoke-RalphCommandScenario -Name 'unterminated-handoffs' `
            -Scenario 'unterminated-handoff' `
            -RalphArguments @('-Agent', 'codex', '-Feature', 'feature', '-Iterations', '2') -Setup {
                param($Repository)
                Set-TestTicket -Path (Join-Path $Repository '.scratch\feature\issues\02.md') `
                    -Heading '# Second ticket'
            }

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $progressPath = Join-Path $result.Repository '.scratch\progress.jsonl'
        $progress = [System.IO.File]::ReadAllBytes($progressPath)
        $progress[$progress.Length - 1] | Should -Be 10
        @(Get-Content -LiteralPath $progressPath).Count | Should -Be 2
        Invoke-Git $result.Repository @('show', '--format=', '--name-only', 'HEAD~1') |
            Should -Not -Match '\.scratch[\\/]'
        Get-NonScratchStatus $result.Repository | Should -Be ''
    }

    It 'reconciles only a selected preflight scope, archives it, and suppresses the agent' {
        $result = Invoke-RalphCommandScenario -Name 'reconciliation-preflight' `
            -RalphArguments @('-Agent', 'codex', '-Feature', 'feature') -Setup {
                param($Repository)
                Set-Content -LiteralPath (Join-Path $Repository '.scratch\feature\issues\01.md') -Value @'
# 01 — First

Blocked by: None — can start immediately

Status: ready-for-agent
'@
                Set-Content -LiteralPath (Join-Path $Repository '.scratch\feature\issues\02.md') -Value @'
# 02 — Completed

Blocked by: 01 — First

Status: done
'@
                $otherIssues = Join-Path $Repository '.scratch\other-feature\issues'
                New-Item -ItemType Directory -Path $otherIssues -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $Repository '.scratch\other-feature\spec.md') -Value '# Other'
                Set-Content -LiteralPath (Join-Path $otherIssues '01.md') -Value @'
# 01 — Other

Blocked by: None — can start immediately

Status: ready-for-agent
'@
                Set-Content -LiteralPath (Join-Path $otherIssues '02.md') -Value @'
# 02 — Completed

Blocked by: 01 — Other

Status: done
'@
                Invoke-Git $Repository @('add', '--force', '.scratch') | Out-Null
                Invoke-Git $Repository @('commit', '--quiet', '--message', 'reconciliation fixture') | Out-Null
            }

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Requested scope complete\.'
        $result.Invocations | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $result.Repository '.scratch\done\feature\issues\01.md') |
            Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $result.Repository '.scratch\done\feature\issues\01.md') -Raw) |
            Should -Match '(?m)^Status: done\r?$'
        (Get-Content -LiteralPath (Join-Path $result.Repository '.scratch\other-feature\issues\01.md') -Raw) |
            Should -Match '(?m)^Status: ready-for-agent\r?$'
        Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD') | Should -Be '2'
    }

    It 'reconciles dependencies after a validated handoff without committing tracker edits' {
        $result = Invoke-RalphCommandScenario -Name 'reconciliation-post-handoff' `
            -Scenario 'post-reconciliation' -Setup {
                param($Repository)
                Set-Content -LiteralPath (Join-Path $Repository '.scratch\feature\issues\01.md') -Value @'
# 01 — First

Blocked by: None — can start immediately

Status: ready-for-agent
'@
                Set-Content -LiteralPath (Join-Path $Repository '.scratch\feature\issues\02.md') -Value @'
# 02 — Second

Blocked by: 01 — First

Status: ready-for-agent
'@
                Set-Content -LiteralPath (Join-Path $Repository '.scratch\feature\issues\03.md') -Value @'
# 03 — Third

Blocked by: 02 — Second

Status: ready-for-agent
'@
                Invoke-Git $Repository @('add', '--force', '.scratch') | Out-Null
                Invoke-Git $Repository @('commit', '--quiet', '--message', 'reconciliation fixture') | Out-Null
            }

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Invocations.Count | Should -Be 1
        foreach ($ticket in '01.md', '02.md', '03.md') {
            (Get-Content -LiteralPath (
                Join-Path $result.Repository ".scratch\done\feature\issues\$ticket"
            ) -Raw) | Should -Match '(?m)^Status: done\r?$'
        }
        Invoke-Git $result.Repository @('show', '--format=', '--name-only', 'HEAD') |
            Should -Not -Match '\.scratch[\\/]done[\\/]feature[\\/]issues'
        Get-NonScratchStatus $result.Repository | Should -Be ''
    }

    It 'iterates active features in priority order until all work is archived' {
        $result = Invoke-RalphCommandScenario -Name 'automatic-iteration' -Scenario 'automatic' `
            -RalphArguments @('-Agent', 'codex', '-Iterations', '4') -Setup {
                param($Repository)
                $issues = Join-Path $Repository '.scratch\later-feature\issues'
                New-Item -ItemType Directory -Path $issues -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $Repository '.scratch\later-feature\spec.md') -Value '# Later feature'
                Set-Content -LiteralPath (Join-Path $issues '01.md') -Value (
                    "# Later ticket`n`nBlocked by: None — can start immediately`n`nStatus: ready-for-agent"
                )
            }

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Requested scope complete\.'
        $result.Invocations.Count | Should -Be 2
        $firstPrompt = ($result.Invocations[0] | ConvertFrom-Json) -join "`n"
        $secondPrompt = ($result.Invocations[1] | ConvertFrom-Json) -join "`n"
        $firstPrompt | Should -Match '(?m)^\.scratch\\feature\\issues\r?$'
        $firstPrompt | Should -Match ([regex]::Escape(
                '"feature" must be the exact selected directory name directly under .scratch.'
            ))
        $firstPrompt | Should -Match ([regex]::Escape(
                '"ticket" must be the exact selected ticket filename without the final .md extension.'
            ))
        $firstPrompt | Should -Match ([regex]::Escape(
                'Do not use the Markdown title for either field.'
            ))
        $secondPrompt | Should -Not -Match '(?m)^\.scratch\\feature\\issues\r?$'
        $secondPrompt | Should -Match '(?m)^\.scratch\\later-feature\\issues\r?$'
        @(Get-Content -LiteralPath (Join-Path $result.Repository '.scratch\progress.jsonl')).Count | Should -Be 2
        Invoke-Git $result.Repository @('log', '--format=%s') |
            Should -Be "ralph: later-feature/01, FEATURE completed`nralph: feature/01, FEATURE completed`nbaseline"
        Test-Path -LiteralPath (Join-Path $result.Repository '.scratch\done\feature\issues\01.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $result.Repository '.scratch\done\later-feature\issues\01.md') | Should -BeTrue
    }

    It 'rejects an invalid public invocation before agent execution or mutation' {
        $result = Invoke-RalphCommandScenario -Name 'invalid-invocation' `
            -RalphArguments @('-List', '-Agent', 'copilot')

        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match '-List cannot be combined with: Agent'
        $result.Invocations | Should -BeNullOrEmpty
        Invoke-Git $result.Repository @('rev-list', '--count', 'HEAD') | Should -Be '1'
        Get-NonScratchStatus $result.Repository | Should -Be ''
    }

    AfterAll {
        $env:PATH = $originalPath
        if (Test-Path $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}
