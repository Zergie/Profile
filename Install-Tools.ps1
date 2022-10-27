[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("*", "chocolatey", "pwsh-modules", "npm", "junctions", "patches", "github-releases", "commands", "fonts")]
    [string]
    $Install = "*"
)
$ErrorActionPreference = 'Stop'

# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    if ($null -eq (Get-Command sudo)) {
        throw "This script needs to be run as Administrator."
    } else {
        $expression = @(
            "sudo"
            "`"$($MyInvocation.MyCommand.Path)`""
            $MyInvocation.BoundParameters.GetEnumerator() |
                ForEach-Object { "-$($_.Key) $($_.Value)" }
        ) | Join-String -Separator " "
        Write-Host -ForegroundColor Cyan $expression
        Invoke-Expression $expression
    }
    exit
}

Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

$modules = @(
    "posh-git"
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

$github = @(
    [pscustomobject]@{repo="PowerShell/PowerShellEditorServices";   file="PowerShellEditorServices.zip"
                      folder="$PSScriptRoot\neovim\lsp_server\PowershellEditorServices"}
    [pscustomobject]@{repo="redhat-developer/vscode-xml";           file="lemminx-win32.zip"
                      folder="$PSScriptRoot\neovim\lsp_server\lemminx"}
    [pscustomobject]@{repo="OmniSharp/omnisharp-roslyn";            file="omnisharp-win-x64-net6.0.zip"
                      folder="$PSScriptRoot\neovim\lsp_server\omnisharp"}
    [pscustomobject]@{repo="sumneko/lua-language-server";           file="lua-language-server-3.5.6-win32-x64.zip"
                      folder="$PSScriptRoot\neovim\lsp_server\lua-language-server"}
)

$patches = @(
    [pscustomobject]@{file="C:\tools\neovim\nvim-win64\share\nvim\runtime\lua\vim\lsp\util.lua"; patch="$PSScriptRoot\neovim\patches\util.lua.patch"}
)

$junctions = @(
    if ((Test-Path "$PSScriptRoot\secrets")) {
        [pscustomobject]@{source      = "$PSScriptRoot\secrets\FileZilla"
                          destination = "$env:APPDATA\FileZilla"}

        [pscustomobject]@{source      = "$PSScriptRoot\secrets\Beyond Compare 4\BC4Key.txt"
                          destination = "$PSScriptRoot\Beyond Compare 4\BC4Key.txt"}
                          
        [pscustomobject]@{source      = "$PSScriptRoot\secrets\secrets.json"
                          destination = "$PSScriptRoot\Powershell\secrets.json"}
    }

    [pscustomobject]@{source      = "$PSScriptRoot\git\.gitconfig"
                      destination = "$env:USERPROFILE\.gitconfig"}

    [pscustomobject]@{source      = "$PSScriptRoot\Microsoft.WindowsTerminal"
                      destination = "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"}

    [pscustomobject]@{source      = "$PSScriptRoot\Powershell"
                      destination = "$env:USERPROFILE\Documents\PowerShell"}

    [pscustomobject]@{source      = "$PSScriptRoot\bat"
                      destination = "$env:APPDATA\bat"}

    [pscustomobject]@{source      = "$PSScriptRoot\Beyond Compare 4"
                      destination = "$env:USERPROFILE\AppData\Roaming\Scooter Software\Beyond Compare 4"}

    [pscustomobject]@{source      = "$PSScriptRoot\neovim"
                      destination = "$env:USERPROFILE\AppData\Local\nvim"}
)

$commands = @(
    { . "$env:ProgramData\chocolatey\bin\bat.exe" cache --build                             }
    { . "C:/tools/neovim/nvim-win64/bin/nvim.exe" +'PlugUpgrade|PlugInstall|PlugUpdate|q|q' }
    { Add-MpPreference -ExclusionPath "C:\Program Files\PowerShell\7\"                      }
)


# functions
function Get-GithubRelease {
    param(
        [Parameter(ValueFromPipelineByPropertyName=$true)] [string] $Repo,
        [Parameter(ValueFromPipelineByPropertyName=$true)] [string] $File,
        [Parameter(ValueFromPipelineByPropertyName=$true)] [string] $Folder
    )
    process {
        Remove-Item $Folder -Force -Recurse -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $Folder | Out-Null
        Push-Location $Folder

        $releases = "https://api.github.com/repos/$Repo/releases"

        Write-Host -ForegroundColor Cyan -NoNewline "Determining latest release for $Repo ..."
        $tag = ((Invoke-RestMethod $releases)| Where-Object { $_.prerelease -eq $false })[0].tag_name
        Write-Host -ForegroundColor Cyan -NoNewline " $tag ..."

        $download = "https://github.com/$Repo/releases/download/$tag/$File"
        $zip = "temp.zip"
        Invoke-WebRequest $download -OutFile $zip

        Microsoft.PowerShell.Archive\Expand-Archive $zip $pwd -Force
        Remove-Item $zip -Force

        Write-Host -ForegroundColor Cyan " completed."

        Pop-Location
    }
}

function Update-File {
    param (
        [Parameter(ValueFromPipelineByPropertyName=$true)] [string] $File,
        [Parameter(ValueFromPipelineByPropertyName=$true)] [string] $Patch
    )
    process {
        . "C:\Program Files\Git\usr\bin\patch.exe" $File $Patch
    }
}

function Install-Junction {
    param (
        [Parameter(ValueFromPipelineByPropertyName=$true)] [string] $Source,
        [Parameter(ValueFromPipelineByPropertyName=$true)] [string] $Destination
    )
    process {
        Remove-Item $Destination -Force -ErrorAction SilentlyContinue | Out-Null

        $directory = [System.IO.Path]::GetDirectoryName($Destination)
        $filename = [System.IO.Path]::GetFileName($Destination)
        
        if ((Test-Path $source -PathType Leaf)) {
            Push-Location $directory | Out-Null
            "New-Item -Type HardLink -Name `"$filename`" -Value `"$Source`"" |
                ForEach-Object { Write-Host -ForegroundColor Cyan $_; Invoke-Expression $_ } |
                Out-Null
            Pop-Location
        } else {
            try { mkdir $directory | Out-Null } catch {}
            Push-Location $directory | Out-Null
            "New-Item -Type Junction -Name `"$filename`" -Value `"$Source`"" |
                ForEach-Object { Write-Host -ForegroundColor Cyan $_; Invoke-Expression $_ } |
                Out-Null
            Pop-Location
        }
    }
}

# powershell modules
if ($Install -in @('*', 'pwsh-modules')) {
    foreach ($tool in $modules) {
        Write-Host -ForegroundColor Cyan "Installing $tool"
        Install-Module -Name $tool -Force
    }
}


# chocolatey tools
if ($Install -in @('*', 'chocolatey')) {
    Write-Host -ForegroundColor Cyan "Installing chocolatey"
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
}

# npm
if ($Install -in @('*', 'npm')) {
    "npm install -g $($npm.name)" | ForEach-Object { Write-Host -ForegroundColor Cyan $_; Invoke-Expression $_ }
}

# junctions
if ($Install -in @('*', 'junctions')) {
    $junctions | Install-Junction
}


# patches
if ($Install -in @('*', 'patches')) {
    $patches | Update-File
}


# github releases
if ($Install -in @('*', 'github-releases')) {
    $github | Get-GithubRelease
}

# commands
if ($Install -in @('*', 'commands')) {
    foreach ($item in $commands) {
        Write-Host -ForegroundColor Cyan "$item"
        Invoke-Command -ScriptBlock $item
    }
}

# install my nerd font
if ($Install -in @('fonts')) {
    Remove-Item -Force -Recurse .\patched-fonts\ -ErrorAction SilentlyContinue
    Invoke-WebRequest "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/install.ps1" -OutFile "$PSScriptRoot/install.ps1"

    New-Item -ItemType Directory "$PSScriptRoot/patched-fonts/complete" | Push-Location
    (Invoke-RestMethod "https://api.github.com/repos/ryanoasis/nerd-fonts/contents/patched-fonts/AurulentSansMono/complete").GetEnumerator() |
        ForEach-Object { Invoke-WebRequest $_.download_url -OutFile $_.name }
    Pop-Location

    . "$PSScriptRoot/install.ps1" -WindowsCompatibleOnly -FontName complete
    Remove-item -Force "$PSScriptRoot/install.ps1"
    Remove-item -Force -Recurse "$PSScriptRoot/patched-fonts"
}
