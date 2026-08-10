#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Set-StrictMode -Version Latest

Describe 'Watch-Command' {
    BeforeAll {
        $script:watchScriptPath = (Get-Item -LiteralPath (
            Join-Path $PSScriptRoot '..\Startup\Watch-Command.ps1'
        )).FullName
        $quotedScriptPath = $script:watchScriptPath.Replace("'", "''")
        $importScript = [scriptblock]::Create(@"
`$script:WatchCommandImportOnly = `$true
. '$quotedScriptPath' -ScriptBlock { `$null }
"@)
        $script:watchModule = New-Module -Name (
            'Watch-Command.TestImport.' + [guid]::NewGuid().ToString('N')
        ) -ScriptBlock $importScript
        Import-Module -ModuleInfo $script:watchModule -Force
    }

    AfterAll {
        if ($script:watchModule) {
            Remove-Module -ModuleInfo $script:watchModule -Force -ErrorAction SilentlyContinue
        }
    }

    It 'imports private behavior without validating RawUI or entering a refresh loop' -Tag 'Internal' {
        & $script:watchModule {
            Get-Command Limit-WatchLines | Should -Not -BeNullOrEmpty
            Get-Command Format-WatchColorHeader | Should -Not -BeNullOrEmpty
            Get-Command Resolve-WatchColorAnchor | Should -Not -BeNullOrEmpty
            Get-Command Invoke-WatchCommandLifecycle | Should -Not -BeNullOrEmpty
        }
    }

    It 'exists and parses without errors' -Tag 'Internal' {
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:watchScriptPath, [ref] $null, [ref] $parseErrors
        ) | Out-Null

        $parseErrors | Should -BeNullOrEmpty
    }

    It 'declares the <Name> parameter with its expected type' -Tag 'Internal' -TestCases @(
        @{ Name = 'Color'; Type = [System.Management.Automation.SwitchParameter] }
        @{ Name = 'Seconds'; Type = [double] }
        @{ Name = 'Milliseconds'; Type = [int] }
    ) {
        param($Name, $Type)

        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:watchScriptPath, [ref] $null, [ref] $null
        )
        $parameter = $ast.ParamBlock.Parameters | Where-Object {
            $_.Name.VariablePath.UserPath -eq $Name
        }

        $parameter | Should -Not -BeNullOrEmpty
        $parameter.StaticType | Should -Be $Type
    }

    It 'documents Color limitations for <Term>' -Tag 'Internal' -TestCases @(
        @{ Term = 'alternate screen'; Pattern = 'alternate-\s*screen' }
        @{ Term = 'progress bars'; Pattern = 'progress bars' }
        @{ Term = 'cursor-driven commands'; Pattern = 'cursor-driven' }
    ) {
        param($Pattern)

        $help = Get-Help -Name $script:watchScriptPath -Full | Out-String

        $help | Should -Match $Pattern
    }

    It 'formats a three-line color header with status, timestamp, interval, and cancellation hint' -Tag 'Internal' {
        $header = & $script:watchModule {
            Format-WatchColorHeader -UpdatedAt '09:15:42' -IntervalText '500 ms'
        }
        $printable = "● WATCHING | 09:15:42 | every 500 ms | Ctrl+C to stop"
        $rule = '─' * $printable.Length

        $header | Should -HaveCount 3
        $header[0] | Should -Match ([regex]::Escape($rule))
        $header[1] | Should -Match 'WATCHING'
        $header[1] | Should -Match '09:15:42'
        $header[1] | Should -Match '500 ms'
        $header[1] | Should -Match 'Ctrl\+C'
        $header[2] | Should -Match ([regex]::Escape($rule))
    }

    It 'limits lines by height, width, and first-line offset' -Tag 'Internal' -TestCases @(
        @{ Name = 'height'; Lines = @('a', 'b', 'c', 'd'); Width = 80; Offset = 0; Height = 2; Expected = '[output truncated]' }
        @{ Name = 'width'; Lines = @(('x' * 200)); Width = 20; Offset = 0; Height = 5; Expected = '[output truncated]' }
        @{ Name = 'first-line-offset'; Lines = @(('x' * 100), ('x' * 100)); Width = 40; Offset = 10; Height = 5; Expected = '[output truncated]' }
    ) {
        param($Lines, $Width, $Offset, $Height, $Expected)

        $result = @(& $script:watchModule {
            param($Lines, $Width, $Offset, $Height)
            Limit-WatchLines -Lines $Lines -Width $Width -FirstLineOffset $Offset -Height $Height
        } $Lines $Width $Offset $Height)

        $result.Count | Should -BeLessOrEqual $Height
        $result[-1] | Should -Be $Expected
    }

    It 'preserves short lines unchanged' -Tag 'Internal' {
        $result = @(& $script:watchModule {
            Limit-WatchLines -Lines @('hello', 'world') -Width 80 -FirstLineOffset 0 -Height 10
        })

        $result | Should -Be @('hello', 'world')
    }

    It 'resolves color anchors for <Name>' -Tag 'Internal' -TestCases @(
        @{
            Name = 'a valid marker'; Lines = @('line', '● WATCHING | current', 'tail')
            WindowTop = 100; ProposedY = 100; ExpectedX = 4; ExpectedY = 100
        }
        @{
            Name = 'the nearest complete marker above a stale anchor'; Lines = @('● WATCHING | old', 'line', '● WATCHING | newest', 'line', 'stale')
            WindowTop = 100; ProposedY = 104; ExpectedX = 2; ExpectedY = 101
        }
        @{
            Name = 'an incomplete marker'; Lines = @('line', '● unrelated', 'line')
            WindowTop = 100; ProposedY = 101; ExpectedX = 2; ExpectedY = 100
        }
        @{
            Name = 'a marker below a stale anchor'; Lines = @('line', 'stale', '● WATCHING | below')
            WindowTop = 100; ProposedY = 100; ExpectedX = 2; ExpectedY = 100
        }
        @{
            Name = 'blank visible rows'; Lines = @('', '● WATCHING | current', '', 'tail')
            WindowTop = 100; ProposedY = 100; ExpectedX = 4; ExpectedY = 100
        }
        @{
            Name = 'a blank viewport'; Lines = @('')
            WindowTop = 200; ProposedY = 200; ExpectedX = 2; ExpectedY = 200
        }
    ) {
        param($Lines, $WindowTop, $ProposedY, $ExpectedX, $ExpectedY)

        $anchor = & $script:watchModule {
            param($Lines, $WindowTop, $ProposedY)
            Resolve-WatchColorAnchor -VisibleLines $Lines -WindowLeft 2 -WindowTop $WindowTop `
                -ProposedAnchor ([System.Management.Automation.Host.Coordinates]::new(4, $ProposedY))
        } $Lines $WindowTop $ProposedY

        $anchor.X | Should -Be $ExpectedX
        $anchor.Y | Should -Be $ExpectedY
    }

    It 'executes bounded default and Color refreshes with supplied terminal collaborators' -Tag 'Internal' {
        $writes = [System.Collections.Generic.List[string]]::new()
        $rawUi = [pscustomobject]@{
            CursorSize = 25
            CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, 0)
            WindowPosition = [System.Management.Automation.Host.Coordinates]::new(0, 0)
            WindowSize = [System.Management.Automation.Host.Size]::new(80, 20)
        }
        $write = { param($line) $writes.Add([string]$line) }
        $writeLine = { param($line) $writes.Add([string]$line) }
        $writeErrorLine = { param($line) $writes.Add([string]$line) }
        $sleep = { param($duration) }

        & $script:watchModule {
            param($rawUi, $write, $writeLine, $writeErrorLine, $sleep)
            Invoke-WatchCommandLifecycle -ScriptBlock {
                Write-Output 'standard output'
                Write-Warning 'warning output'
            } -Interval ([TimeSpan]::FromMilliseconds(1)) -IntervalText '1 ms' `
                -RawUi $rawUi -Write $write -WriteLine $writeLine `
                -WriteErrorLine $writeErrorLine -Sleep $sleep -RefreshCount 1
        } $rawUi $write $writeLine $writeErrorLine $sleep

        ($writes -join "`n") | Should -Match 'standard output'
        ($writes -join "`n") | Should -Match 'warning output'
        $rawUi.CursorSize | Should -Be 25

        $writes.Clear()
        $colorOutput = @(& $script:watchModule {
            param($rawUi, $write, $writeLine, $writeErrorLine, $sleep)
            Invoke-WatchCommandLifecycle -ScriptBlock { 'direct color output' } `
                -Interval ([TimeSpan]::FromMilliseconds(1)) -IntervalText '1 ms' -Color `
                -RawUi $rawUi -Write $write -WriteLine $writeLine `
                -WriteErrorLine $writeErrorLine -Sleep $sleep -RefreshCount 1
        } $rawUi $write $writeLine $writeErrorLine $sleep)

        $colorOutput | Should -Be 'direct color output'
        ($writes -join "`n") | Should -Match 'WATCHING'
        $rawUi.CursorSize | Should -Be 25
    }

    It 'clears stale Color rows and restores the cursor after a refresh failure' -Tag 'Internal' {
        $writes = [System.Collections.Generic.List[string]]::new()
        $buffer = New-Object 'object[,]' 80, 20
        for ($column = 0; $column -lt 80; $column++) {
            for ($row = 0; $row -lt 20; $row++) {
                $buffer[$column, $row] = [pscustomobject]@{ Character = [char]' ' }
            }
        }
        '● WATCHING | current'.ToCharArray() | ForEach-Object -Begin { $column = 0 } -Process {
            $buffer[$column++, 1] = [pscustomobject]@{ Character = $_ }
        }
        $rawUi = [pscustomobject]@{
            CursorSize = 25
            CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, 0)
            WindowPosition = [System.Management.Automation.Host.Coordinates]::new(0, 0)
            WindowSize = [System.Management.Automation.Host.Size]::new(80, 20)
            Buffer = $buffer
        }
        $rawUi | Add-Member -MemberType ScriptMethod -Name GetBufferContents -Value {
            param($rectangle)
            return (, $this.Buffer)
        }
        $write = { param($line) $writes.Add([string]$line) }
        $writeLine = { param($line) $writes.Add([string]$line) }
        $sleep = { param($duration) }
        $state = [pscustomobject]@{ Refresh = 0 }

        & $script:watchModule {
            param($rawUi, $write, $writeLine, $sleep, $state)
            Invoke-WatchCommandLifecycle -ScriptBlock {
                $state.Refresh++
                $rawUi.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(
                    0, $(if ($state.Refresh -eq 1) { 5 } else { 3 })
                )
            } -Interval ([TimeSpan]::FromMilliseconds(1)) -IntervalText '1 ms' -Color `
                -RawUi $rawUi -Write $write -WriteLine $writeLine -WriteErrorLine $writeLine `
                -Sleep $sleep -RefreshCount 2
        } $rawUi $write $writeLine $sleep $state

        (@($writes | Where-Object { $_.Length -eq 79 })).Count | Should -BeGreaterOrEqual 2
        $rawUi.CursorSize | Should -Be 25

        $failureWriter = { param($line) throw 'writer failure' }
        {
            & $script:watchModule {
                param($rawUi, $failureWriter, $sleep)
                Invoke-WatchCommandLifecycle -ScriptBlock { 'output' } `
                    -Interval ([TimeSpan]::FromMilliseconds(1)) -IntervalText '1 ms' `
                    -RawUi $rawUi -Write $failureWriter -WriteLine $failureWriter `
                    -WriteErrorLine $failureWriter -Sleep $sleep -RefreshCount 1
            } $rawUi $failureWriter $sleep
        } | Should -Throw 'writer failure'
        $rawUi.CursorSize | Should -Be 25
    }
}
