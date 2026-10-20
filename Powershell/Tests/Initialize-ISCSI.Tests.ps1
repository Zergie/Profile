#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Initialize-ISCSI session persistence' {
    BeforeAll {
        $path = Join-Path $PSScriptRoot '..\Startup\Initialize-ISCSI.ps1'
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $path, [ref] $null, [ref] $parseErrors
        )
        if ($parseErrors) { throw $parseErrors[0] }
        # Exercise the real registration action without changing local storage.
        $command = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Invoke-Action' -and
                $node.Extent.Text -match 'Registering persistent iSCSI sessions'
        }, $true)
        $action = $command.CommandElements |
            Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }
        $script:registerAction = $action.ScriptBlock.GetScriptBlock()
        function Get-IscsiSession { param($ErrorAction) }
        function Register-IscsiSession { param($SessionIdentifier, $ErrorAction) }
    }

    BeforeEach {
        $nodeAddress = 'iqn.test:restore'
        Mock Register-IscsiSession {}
    }

    It 'registers only connected sessions that are not already persistent' {
        Mock Get-IscsiSession {
            [pscustomobject]@{ TargetNodeAddress = 'iqn.test:restore'; SessionIdentifier = 'new'; IsConnected = $true; IsPersistent = $false }
            [pscustomobject]@{ TargetNodeAddress = 'iqn.test:restore'; SessionIdentifier = 'saved'; IsConnected = $true; IsPersistent = $true }
            [pscustomobject]@{ TargetNodeAddress = 'iqn.test:restore'; SessionIdentifier = 'offline'; IsConnected = $false; IsPersistent = $false }
            [pscustomobject]@{ TargetNodeAddress = 'iqn.test:other'; SessionIdentifier = 'other'; IsConnected = $true; IsPersistent = $false }
        }
        & $script:registerAction
        Should -Invoke Register-IscsiSession -Times 1 -Exactly
        Should -Invoke Register-IscsiSession -Times 1 -Exactly -ParameterFilter {
            $SessionIdentifier -eq 'new'
        }
        Should -Invoke Get-IscsiSession -Times 1 -Exactly
    }

    It 'does not register persistent sessions again' {
        Mock Get-IscsiSession {
            [pscustomobject]@{ TargetNodeAddress = 'iqn.test:restore'; SessionIdentifier = 'saved'; IsConnected = $true; IsPersistent = $true }
        }
        & $script:registerAction
        Should -Invoke Register-IscsiSession -Times 0 -Exactly
    }

    It 'reports a missing connected session' {
        Mock Get-IscsiSession {}
        { & $script:registerAction } | Should -Throw '*No connected iSCSI session*'
        Should -Invoke Register-IscsiSession -Times 0 -Exactly
    }
}
