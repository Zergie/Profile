#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

function Install-File {
    param (
        [String] $Source,
        [String] $Destination
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
        [String] $Source,
        [String] $Destination
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
& "$env:ProgramData\chocolatey\bin\bat.exe" cache --build

Install-Directory `
    "$PSScriptRoot\Beyond Compare 4" `
    "$env:USERPROFILE\AppData\Roaming\Scooter Software\Beyond Compare 4"

Install-Directory `
    "$PSScriptRoot\neovim" `
    "$env:USERPROFILE\AppData\Local\nvim"

New-Item -Type Directory -Path "$PSScriptRoot\neovim\PowerShellEditorServices" | Push-Location | Out-Null
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString("https://raw.githubusercontent.com/coc-extensions/coc-powershell/master/downloadPSES.ps1"))
Pop-Location

. "C:/tools/neovim/nvim-win64/bin/nvim.exe" `
    +'PlugInstall' `
    +'|q|q'
