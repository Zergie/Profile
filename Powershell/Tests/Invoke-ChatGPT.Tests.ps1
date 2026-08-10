#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Set-StrictMode -Version Latest

Describe 'Invoke-ChatGPT' {
    BeforeAll {
        $script:chatScriptPath = (Get-Item -LiteralPath (
            Join-Path $PSScriptRoot '..\Startup\Invoke-ChatGPT.ps1'
        )).FullName
        $quotedScriptPath = $script:chatScriptPath.Replace("'", "''")
        $importScript = [scriptblock]::Create(@"
`$script:InvokeChatGPTImportOnly = `$true
. '$quotedScriptPath'
"@)
        $script:chatModule = New-Module -Name (
            'Invoke-ChatGPT.TestImport.' + [guid]::NewGuid().ToString('N')
        ) -ScriptBlock $importScript
        Import-Module -ModuleInfo $script:chatModule -Force

        function New-FakeRawUi {
            param(
                [Parameter(Mandatory)][string[]] $Lines,
                [switch] $Unavailable
            )

            $width = [Math]::Max(1, ($Lines | ForEach-Object Length | Measure-Object -Maximum).Maximum)
            $rawUi = [pscustomobject]@{
                WindowPosition = [System.Management.Automation.Host.Coordinates]::new(0, 0)
                WindowSize = [System.Management.Automation.Host.Size]::new($width, [Math]::Max(1, $Lines.Count))
                Lines = $Lines
                Unavailable = $Unavailable.IsPresent
            }
            $rawUi | Add-Member -MemberType ScriptMethod -Name GetBufferContents -Value {
                param([System.Management.Automation.Host.Rectangle] $Rectangle)
                if ($this.Unavailable) {
                    throw 'screen buffer unavailable'
                }

                $cells = [System.Management.Automation.Host.BufferCell[,]]::new(
                    $this.WindowSize.Height,
                    $this.WindowSize.Width
                )
                for ($row = 0; $row -lt $this.WindowSize.Height; $row++) {
                    $line = if ($row -lt $this.Lines.Count) { [string]$this.Lines[$row] } else { '' }
                    for ($column = 0; $column -lt $this.WindowSize.Width; $column++) {
                        $character = if ($column -lt $line.Length) {
                            $line[$column]
                        } else {
                            ' '
                        }
                        $cells[$row, $column] = [System.Management.Automation.Host.BufferCell]::new(
                            $character,
                            [ConsoleColor]::White,
                            [ConsoleColor]::Black,
                            [System.Management.Automation.Host.BufferCellType]::Complete
                        )
                    }
                }
                Write-Output -NoEnumerate $cells
            }
            $rawUi
        }
    }

    AfterAll {
        if ($script:chatModule) {
            Remove-Module -ModuleInfo $script:chatModule -Force -ErrorAction SilentlyContinue
        }
    }

    It 'imports private behavior without reading RawUI, sending requests, or entering the command loop' -Tag 'Internal' {
        & $script:chatModule {
            Get-Command Get-VisibleTerminalText | Should -Not -BeNullOrEmpty
            Get-Command Invoke-ChatGPTConversation | Should -Not -BeNullOrEmpty
        }
    }

    It 'declares IncludeTerminal only for chat requests' -Tag 'Internal' {
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:chatScriptPath,
            [ref] $null,
            [ref] $parseErrors
        )
        $parseErrors | Should -BeNullOrEmpty
        $includeParameter = $ast.ParamBlock.Parameters | Where-Object {
            $_.Name.VariablePath.UserPath -eq 'IncludeTerminal'
        }
        $includeParameter | Should -Not -BeNullOrEmpty
        @($includeParameter.Attributes | ForEach-Object {
            $_.NamedArguments | Where-Object {
                $_.ArgumentName -eq 'ParameterSetName' -and
                $_.Argument.Extent.Text -eq '"ChatParameterSet"'
            }
        }) | Should -HaveCount 1
    }

    It 'captures visible terminal text without truncating long lines' -Tag 'Internal' {
        $longLine = 'x' * 12000
        $rawUi = New-FakeRawUi -Lines @(
            'PS C:\repo> git status'
            "PS C:\repo> Invoke-ChatGPT -Message 'why' -IncludeTerminal"
            $longLine
        )
        $terminalText = & $script:chatModule {
            param($RawUi)
            Get-VisibleTerminalText -RawUi $RawUi
        } $rawUi

        $terminalText | Should -Match 'PS C:\\repo> git status'
        $terminalText | Should -Match "Invoke-ChatGPT -Message 'why' -IncludeTerminal"
        $terminalText | Should -Match ([regex]::Escape($longLine))
    }

    It 'adds visible terminal context in one-shot, pipeline, and interactive modes' -Tag 'Command' -TestCases @(
        @{ Name = 'one-shot'; Pipeline = $false; Interactive = $false }
        @{ Name = 'pipeline'; Pipeline = $true; Interactive = $false }
        @{ Name = 'interactive'; Pipeline = $false; Interactive = $true }
    ) {
        param($Pipeline, $Interactive)

        $requests = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-VisibleTerminalText -ModuleName $script:chatModule.Name -MockWith {
            "PS C:\repo> git status`nPS C:\repo> Invoke-ChatGPT -Message 'why' -IncludeTerminal`n$('x' * 12000)"
        }
        Mock -CommandName Invoke-RestMethod -ModuleName $script:chatModule.Name -MockWith {
            param($Method, $Uri, $Headers, $Body)
            [void] $requests.Add(($Body | ConvertFrom-Json))
            [pscustomobject]@{
                choices = @([pscustomobject]@{
                    message = [pscustomobject]@{ content = 'test response' }
                })
            }
        }
        if ($Interactive) {
            Mock -CommandName Read-Host -ModuleName $script:chatModule.Name -MockWith { 'exit' }
        }

        if ($Pipeline) {
            'original question' | & $script:chatModule {
                process { Invoke-ChatGPTConversation -Message $_ -IncludeTerminal }
            }
        } else {
            & $script:chatModule {
                param($IsInteractive)
                Invoke-ChatGPTConversation -Message 'original question' -IncludeTerminal -Interactive:$IsInteractive
            } $Interactive
        }

        $requests | Should -HaveCount 1
        $content = $requests[0].messages[1].content
        $content.StartsWith('[TERMINAL OUTPUT - VISIBLE SCREEN]') | Should -BeTrue
        $content | Should -Match 'PS C:\\repo> git status'
        $content | Should -Match "Invoke-ChatGPT -Message 'why' -IncludeTerminal"
        $content | Should -Match ('x' * 12000)
        $content.EndsWith('original question') | Should -BeTrue
    }

    It 'fails before requesting when terminal capture is unavailable' -Tag 'Command' {
        $requests = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-VisibleTerminalText -ModuleName $script:chatModule.Name -MockWith {
            throw [System.InvalidOperationException]::new(
                'Cannot include terminal context because this PowerShell host cannot read its visible screen buffer. Run the command in a console host that supports RawUI.GetBufferContents(), or omit -IncludeTerminal. No API request was sent.'
            )
        }
        Mock -CommandName Invoke-RestMethod -ModuleName $script:chatModule.Name -MockWith {
            [void] $requests.Add('unexpected')
        }

        $caught = $null
        try {
            & $script:chatModule {
                Invoke-ChatGPTConversation -Message 'do not send' -IncludeTerminal
            }
        } catch {
            $caught = $_
        }
        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -Match 'omit -IncludeTerminal'
        $caught.Exception.Message | Should -Match 'No API request was sent'
        $requests.Count | Should -Be 0
    }

    It 'does not require a terminal buffer when IncludeTerminal is omitted' -Tag 'Command' {
        $requests = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Invoke-RestMethod -ModuleName $script:chatModule.Name -MockWith {
            param($Method, $Uri, $Headers, $Body)
            [void] $requests.Add(($Body | ConvertFrom-Json))
            [pscustomobject]@{
                choices = @([pscustomobject]@{
                    message = [pscustomobject]@{ content = 'test response' }
                })
            }
        }
        Mock -CommandName Get-VisibleTerminalText -ModuleName $script:chatModule.Name -MockWith {
            throw 'Terminal capture must not run without IncludeTerminal.'
        }

        & $script:chatModule {
            Invoke-ChatGPTConversation -Message 'unchanged question'
        } | Out-Null

        $requests | Should -HaveCount 1
        $requests[0].messages[1].content | Should -Be 'unchanged question'
        Should -Invoke Get-VisibleTerminalText -ModuleName $script:chatModule.Name -Times 0 -Exactly
    }
}
