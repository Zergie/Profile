#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

Write-Host -ForegroundColor Magenta "Installing chocolatey"
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
)

$npm = @(
    [PsCustomObject]@{name="@mermaid-js/mermaid-cli"} # cli for mermaid diagrams
    [PsCustomObject]@{name="pyright"}                 # python LSP Server for NeoVim
    [PsCustomObject]@{name="vsce"}                    # used for Visual Studio Code Plugin Development
)

foreach ($tool in $modules) {
    Write-Host -ForegroundColor Magenta "Installing $tool"
    Install-Module -Name $tool -Force
}

foreach ($tool in $tools | Where-Object version -NE $null) {
    Write-Host -ForegroundColor Magenta "Installing $($tool.name) (version $($tool.version))"
    choco install $tool.name --version $tool.version --allow-downgrade -y

    if ($null -ne $tool.pin) {
        if ($null -ne $tool.reason) {
            choco pin add --name $tool.name --reason "$($tool.reason)"
        } else {
            choco pin add --name $tool.name
        }
    }
}

foreach ($tool in $tools | Where-Object pin -EQ $true) {
    Write-Host -ForegroundColor Magenta "Pinning $($tool.name) (version $($tool.version))"
    if ($null -ne $tool.reason) {
        choco pin add --name $tool.name --reason "$($tool.reason)"
    } else {
        choco pin add --name $tool.name
    }
}

$choco_packages_without_version = $tools | Where-Object version -EQ $null | ForEach-Object name
Write-Host -ForegroundColor Magenta "Installing $choco_packages_without_version"
Invoke-Expression "choco install $choco_packages_without_version -y"

foreach ($tool in $npm) {
    Write-Host -ForegroundColor Magenta "Installing $($tool.name)"
    npm install -g $tool.name
}

Write-Host -ForegroundColor Magenta "Configuring Windows Defender"
Add-MpPreference -ExclusionPath "C:\Program Files\PowerShell\7\"
