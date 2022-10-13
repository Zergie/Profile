#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

Write-Host -ForegroundColor Cyan "Installing chocolatey"
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

$modules = @(
    "posh-git"
    # "7Zip4PowerShell"
)

$tools = @(
    [PsCustomObject]@{name="7zip"}
    [PsCustomObject]@{name="autohotkey"}
    [PsCustomObject]@{name="bat"}
    [PsCustomObject]@{name="BatteryBar"}
    [PsCustomObject]@{name="beyondcompare"}
    [PsCustomObject]@{name="brave";reason="brave has integrated updates";pin=$true}
    [PsCustomObject]@{name="discord"}
    [PsCustomObject]@{name="docker-desktop";reason="docker-desktop has to frequent and big updates";pin=$true}
    [PsCustomObject]@{name="gimp"}
    [PsCustomObject]@{name="git";version="2.36.0";reason="interative.singlekey does not work in version 2.37.1";pin=$true}
    [PsCustomObject]@{name="git-status-cache-posh-client"}
    [PsCustomObject]@{name="git.install";version="2.36.0";reason="interative.singlekey does not work in version 2.37.1";pin=$true}
    [PsCustomObject]@{name="gsudo"}
    [PsCustomObject]@{name="InkScape"}
    [PsCustomObject]@{name="microsoft-teams"}
    [PsCustomObject]@{name="microsoft-windows-terminal"}
    [PsCustomObject]@{name="neovim"}
    [PsCustomObject]@{name="nodejs-lts" ;}
    [PsCustomObject]@{name="nuget.commandline"}
    [PsCustomObject]@{name="obs-studio"}
    [PsCustomObject]@{name="phonerlite"}
    [PsCustomObject]@{name="poshgit"}
    [PsCustomObject]@{name="powershell-core"}
    [PsCustomObject]@{name="powertoys"}
    [PsCustomObject]@{name="sql-server-management-studio"}
    [PsCustomObject]@{name="treesizefree"}
    [PsCustomObject]@{name="visualstudio2022community";reason="Visual Studio 2020 Community has an integrated updates";pin=$true}
    [PsCustomObject]@{name="vscode"}
    [PsCustomObject]@{name="wireshark"}
    [PsCustomObject]@{name="wsl2"}
    [PsCustomObject]@{name="ripgrep"}
)

$npm = @(
    [PsCustomObject]@{name="@mermaid-js/mermaid-cli"} # cli for mermaid diagrams
    [PsCustomObject]@{name="pyright"}                 # python LSP Server for NeoVim
    [PsCustomObject]@{name="vsce"}                    # used for Visual Studio Code Plugin Development
)

foreach ($tool in $modules) {
    Write-Host -ForegroundColor Cyan "Installing $tool"
    Install-Module -Name $tool -Force
}

foreach ($tool in $tools | Where-Object version -NE $null) {
    "choco install $($tool.name) --version $($tool.version) --allow-downgrade -y" |
        ForEach-Object { Write-Host -ForegroundColor Cyan $_; Invoke-Expression $_ }
}

foreach ($tool in $tools | Where-Object pin -EQ $true) {
    if ($null -ne $tool.reason) {
        "choco pin add --name=$($tool.name)" |
            ForEach-Object { Write-Host -ForegroundColor Cyan $_; Invoke-Expression $_ }

    } else {
        "choco pin add --name $($tool.name)" |
            ForEach-Object { Write-Host -ForegroundColor Cyan $_; Invoke-Expression $_ }
    }
}

$choco_packages_without_version = $tools | Where-Object version -EQ $null | ForEach-Object name
"choco install $choco_packages_without_version -y" |
        ForEach-Object { Write-Host -ForegroundColor Cyan $_; Invoke-Expression $_ }

"npm install -g $($npm.name)" |
        ForEach-Object { Write-Host -ForegroundColor Cyan $_; Invoke-Expression $_ }


Write-Host -ForegroundColor Cyan "Configuring Windows Defender"
Add-MpPreference -ExclusionPath "C:\Program Files\PowerShell\7\"
