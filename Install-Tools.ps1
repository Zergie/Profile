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
    [pscustomobject]@{name="7zip"}
    [pscustomobject]@{name="autohotkey"}
    [pscustomobject]@{name="bat"}
    [pscustomobject]@{name="BatteryBar"}
    [pscustomobject]@{name="beyondcompare"}
    [pscustomobject]@{name="brave";reason="brave has integrated updates";pin=$true}
    [pscustomobject]@{name="discord"}
    [pscustomobject]@{name="docker-desktop";reason="docker-desktop has to frequent and big updates";pin=$true}
    [pscustomobject]@{name="gimp"}
    [pscustomobject]@{name="git";version="2.36.0";reason="interative.singlekey does not work in version 2.37.1";pin=$true}
    [pscustomobject]@{name="git-status-cache-posh-client"}
    [pscustomobject]@{name="git.install";version="2.36.0";reason="interative.singlekey does not work in version 2.37.1";pin=$true}
    [pscustomobject]@{name="gsudo"}
    [pscustomobject]@{name="InkScape"}
    [pscustomobject]@{name="microsoft-teams"}
    [pscustomobject]@{name="microsoft-windows-terminal"}
    [pscustomobject]@{name="neovim"}
    [pscustomobject]@{name="nodejs-lts" ;}
    [pscustomobject]@{name="nuget.commandline"}
    [pscustomobject]@{name="obs-studio"}
    [pscustomobject]@{name="phonerlite"}
    [pscustomobject]@{name="poshgit"}
    [pscustomobject]@{name="powershell-core"}
    [pscustomobject]@{name="powertoys"}
    [pscustomobject]@{name="sql-server-management-studio"}
    [pscustomobject]@{name="treesizefree"}
    [pscustomobject]@{name="visualstudio2022community";reason="Visual Studio 2020 Community has an integrated updates";pin=$true}
    [pscustomobject]@{name="vscode"}
    [pscustomobject]@{name="wireshark"}
    [pscustomobject]@{name="wsl2"}
    [pscustomobject]@{name="ripgrep"}
)

$npm = @(
    [pscustomobject]@{name="@mermaid-js/mermaid-cli"} # cli for mermaid diagrams
    [pscustomobject]@{name="pyright"}                 # python LSP Server for NeoVim
    [pscustomobject]@{name="vsce"}                    # used for Visual Studio Code Plugin Development
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
