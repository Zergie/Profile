#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

function Get-GithubRelease {
    param(
        [string] $Repo,
        [string] $File,
        [string] $OutFolder
    )
    if (!$IsCoreCLR) {
        # We only need to do this in Windows PowerShell.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    Remove-Item $OutFolder -Force -Recurse -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $OutFolder | Out-Null
    Push-Location $OutFolder

    $releases = "https://api.github.com/repos/$Repo/releases"

    Write-Host -ForegroundColor Cyan "Determining latest release for $Repo ..."
    $tag = ((Invoke-RestMethod $releases)| Where-Object { $_.prerelease -eq $false })[0].tag_name
    Write-Host -ForegroundColor Cyan "Latest Release: $tag"

    Write-Host -ForegroundColor Cyan "Downloading : $tag"
    $download = "https://github.com/$Repo/releases/download/$tag/$File"
    $zip = "temp.zip"
    Invoke-WebRequest $download -OutFile $zip

    Write-Host -ForegroundColor Cyan "Extracting release files..."
    Microsoft.PowerShell.Archive\Expand-Archive $zip $pwd -Force
    Remove-Item $zip -Force

    Write-Host -ForegroundColor Cyan "Release install completed."

    Pop-Location
}

function Update-File {
    param (
        [string] $OrgFile,
        [string] $PatchFile
    )
    . "C:\Program Files\Git\usr\bin\patch.exe" $OrgFile $PatchFile 
}

function Install-File {
    param (
        [string] $Source,
        [string] $Destination
    )
    Write-Host -ForegroundColor Magenta "Installing '$source' -> '$Destination'"
    Remove-Item "$Destination" -Force -ErrorAction SilentlyContinue | Out-Null

    $directory = [System.IO.Path]::GetDirectoryName($Destination)
    $filename = [System.IO.Path]::GetFileName($Destination)
    
    Push-Location $directory | Out-Null
    New-Item -Type HardLink -Name "$filename" -Value "$Source" | Out-Null
    Pop-Location
}

function Install-Directory {
    param (
        [string] $Source,
        [string] $Destination
    )
    Write-Host -ForegroundColor Magenta "Installing '$source' -> '$Destination'"
    Remove-Item "$Destination" -Force -Recurse -ErrorAction SilentlyContinue | Out-Null

    $directory = [System.IO.Path]::GetDirectoryName($Destination)
    $filename = [System.IO.Path]::GetFileName($Destination)
    try { mkdir $directory | Out-Null } catch {}

    Push-Location $directory | Out-Null
    New-Item -Type Junction -Name "$filename" -Value "$Source" | Out-Null
    Pop-Location
}

if ((Test-Path "$PSScriptRoot\secrets")) {
    Install-Directory `
        "$PSScriptRoot\secrets\FileZilla" `
        "$env:APPDATA\FileZilla"
    
    Install-File `
        "$PSScriptRoot\secrets\Beyond Compare 4\BC4Key.txt" `
        "$PSScriptRoot\Beyond Compare 4\BC4Key.txt" `
    
    Install-File `
        "$PSScriptRoot\secrets\secrets.json" `
        "$PSScriptRoot\Powershell\secrets.json" `
}

Install-File `
    "$PSScriptRoot\git\.gitconfig" `
    "$env:USERPROFILE\.gitconfig"

Install-File `
    "$PSScriptRoot\Microsoft.WindowsTerminal\settings.json" `
    "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
 
Install-Directory `
    "$PSScriptRoot\Powershell" `
    "$env:USERPROFILE\Documents\PowerShell"

Install-Directory `
    "$PSScriptRoot\bat" `
    "$env:APPDATA\bat"
. "$env:ProgramData\chocolatey\bin\bat.exe" cache --build

Install-Directory `
    "$PSScriptRoot\Beyond Compare 4" `
    "$env:USERPROFILE\AppData\Roaming\Scooter Software\Beyond Compare 4"

Install-Directory `
    "$PSScriptRoot\neovim" `
    "$env:USERPROFILE\AppData\Local\nvim"

Get-GithubRelease `
    -Repo "PowerShell/PowerShellEditorServices" `
    -File "PowerShellEditorServices.zip" `
    -OutFolder "$PSScriptRoot\neovim\PowershellEditorServices"
Get-GithubRelease `
    -Repo "redhat-developer/vscode-xml" `
    -File "lemminx-win32.zip" `
    -OutFolder "$PSScriptRoot\neovim\lemminx"
Update-File `
    "C:\tools\neovim\nvim-win64\share\nvim\runtime\lua\vim\lsp\util.lua" `
    "$PSScriptRoot\patches\util.lua.patch"
. "C:/tools/neovim/nvim-win64/bin/nvim.exe" `
    +'PlugInstall' `
    +'|q|q'
