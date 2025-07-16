[CmdletBinding()]
param(
)
dynamicparam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    @(
            "all"
            "chocolatey"
            "pwsh-modules"
            "npm"
            "junctions"
            "patches"
            "github-releases"
            "commands"
    ) |
        ForEach-Object {
            $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
            $ParameterAttribute.Position = 0
            $ParameterAttribute.Mandatory = $false
            $ParameterAttribute.ParameterSetName = "$_ParameterSet"
            $AttributeCollection.Add($ParameterAttribute)

            $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("$_", [switch], $AttributeCollection)
            $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)
        }

    return $RuntimeParameterDictionary
}
process {
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
                ForEach-Object {
                    if ($_.Value -eq $true) {
                        "-$($_.Key)"
                    } else {
                        "-$($_.Key) $($_.Value)"
                    }
                }
        ) | Join-String -Separator " "
        Write-Host -ForegroundColor Cyan $expression
        Invoke-Expression $expression
    }
    exit
}

Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

function Test-IsWorkstation { $env:USERNAME -eq "puchinger" }
function Test-IsLaptop { (Get-Computerinfo -Property CsPCSystemType).CsPCSystemType -ne 3 }

Write-Host -ForegroundColor Cyan "  Test-IsWorkstation: $(Test-IsWorkstation)"
Write-Host -ForegroundColor Cyan "  Test-IsLaptop: $(Test-IsLaptop)"

$modules = @(
    "posh-git"
    "SqlServer"
    "ImportExcel"
)

$tools = @(
    if (Test-IsWorkstation) {
        [pscustomobject]@{name="autohotkey"}
        [pscustomobject]@{name="azure-cli"}
        [pscustomobject]@{name="filezilla"}
        [pscustomobject]@{name="keepass"}
        [pscustomobject]@{name="nodejs-lts"}
        [pscustomobject]@{name="sql-server-management-studio"}
        [pscustomobject]@{name="wixtoolset"}
        [pscustomobject]@{name="zoom"}
    }
    if (Test-IsLaptop) {
        [pscustomobject]@{name="autohotkey"}
    }

    [pscustomobject]@{name="7zip"}
    [pscustomobject]@{name="7zip.commandline"}
    [pscustomobject]@{name="InkScape"}
    [pscustomobject]@{name="autodesk-fusion360";reason="program has integrated updates";pin=$true}
    [pscustomobject]@{name="bat"}
    [pscustomobject]@{name="beyondcompare"}
    [pscustomobject]@{name="brave";reason="program has integrated updates";pin=$true}
    [pscustomobject]@{name="delta"}
    [pscustomobject]@{name="discord"}
    [pscustomobject]@{name="docker-desktop"}
    [pscustomobject]@{name="dotnet-6.0-desktopruntime"}
    [pscustomobject]@{name="gh"}
    [pscustomobject]@{name="gimp"}
    [pscustomobject]@{name="git";version="2.36.0";reason="interative.singlekey does not work in version 2.37.1";pin=$true}
    [pscustomobject]@{name="git-status-cache-posh-client"}
    [pscustomobject]@{name="git.install";version="2.36.0";reason="interative.singlekey does not work in version 2.37.1";pin=$true}
    [pscustomobject]@{name="gsudo"}
    [pscustomobject]@{name="irfanview"}
    [pscustomobject]@{name="microsoft-teams-new-bootstrapper"}
    [pscustomobject]@{name="microsoft-teams"}
    [pscustomobject]@{name="neovim"}
    [pscustomobject]@{name="nerd-fonts-Meslo"}
    [pscustomobject]@{name="nuget.commandline"}
    [pscustomobject]@{name="poshgit"}
    [pscustomobject]@{name="powershell-core"}
    [pscustomobject]@{name="powertoys"}
    [pscustomobject]@{name="pypy3"}
    [pscustomobject]@{name="python3";version="3.11";reason="neovim-remote does not work with python 3.12"}
    [pscustomobject]@{name="ripgrep"}
    [pscustomobject]@{name="visualstudio2022community";reason="Visual Studio 2020 Community has an integrated updates";pin=$true}
    [pscustomobject]@{name="vlc"}
    [pscustomobject]@{name="vscode"}
    [pscustomobject]@{name="wireshark"}
    [pscustomobject]@{name="wiztree"}
    [pscustomobject]@{name="wsl2"}

)

$npm = @(
    if (Test-IsWorkstation) {
        [pscustomobject]@{name="@mermaid-js/mermaid-cli"} # cli for mermaid diagrams
        [pscustomobject]@{name="@vscode/vsce"}            # used for Visual Studio Code Plugin Development
    }
)

$github = @(
    # [pscustomobject]@{repo="rvaiya/warpd";         file="warpd.exe"
    #                   folder="$PSScriptRoot\warpd"}
    [pscustomobject]@{repo="max-niederman/ttyper"; file="ttyper-x86_64-*-windows-*.zip"
                      folder="$PSScriptRoot/ttyper"}
    [pscustomobject]@{repo="microsoft/WSL"; file="wsl*.x64.msi"
                      folder="$PSScriptRoot/wsl"}
)

$patches = @(
    [pscustomobject]@{file="C:\tools\neovim\nvim-win64\share\nvim\runtime\lua\vim\lsp\util.lua";
                      patch="$PSScriptRoot\neovim\patches\util.lua.patch"}
)

$junctions = @(
    if ((Test-Path "$PSScriptRoot\secrets")) {
        [pscustomobject]@{source      = "$PSScriptRoot\secrets\FileZilla"
                          destination = "$env:APPDATA\FileZilla"}

        [pscustomobject]@{source      = "$PSScriptRoot\secrets\Beyond Compare 4\BC4Key.txt"
                          destination = "$PSScriptRoot\Beyond Compare 4\BC4Key.txt"}

        [pscustomobject]@{source      = "$PSScriptRoot\secrets\secrets.json"
                          destination = "$PSScriptRoot\Powershell\secrets.json"}
        [pscustomobject]@{source      = "$PSScriptRoot\secrets\Locations.json"
                          destination = "$PSScriptRoot\Powershell\Locations.json"}
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

    [pscustomobject]@{source      = "$PSScriptRoot\Beyond Compare 5"
                      destination = "$env:USERPROFILE\AppData\Roaming\Scooter Software\Beyond Compare 5"}

    # [pscustomobject]@{source      = "$PSScriptRoot\warpd\warpd.conf"
    #                   destination = "$env:APPDATA\warpd\warpd.conf"}

    [pscustomobject]@{source      = "$PSScriptRoot\neovim"
                      destination = "$env:USERPROFILE\AppData\Local\nvim"}

    [pscustomobject]@{source      = "$PSScriptRoot\OrcaSlicer"
                      destination = "$env:USERPROFILE\AppData\Roaming\OrcaSlicer"}

    [pscustomobject]@{source      = "$PSScriptRoot\Fusion360\Library.json"
                      destination = "$env:USERPROFILE\AppData\Roaming\Autodesk\CAM360\libraries\Local\Library.json"}

    [pscustomobject]@{source      = "$PSScriptRoot\Fusion360\AddIns"
                      destination = "$env:USERPROFILE\AppData\Roaming\Autodesk\Autodesk Fusion 360\API\AddIns"}
    [pscustomobject]@{source      = "$PSScriptRoot\Fusion360\ThreadData\*"
                      destination = "$env:USERPROFILE\AppData\Local\Autodesk\webdeploy\production\**\Fusion\Server\Fusion\Configuration\ThreadData"}
    # [pscustomobject]@{source      = "$PSScriptRoot\Fusion360\ThreadData\*"
    #                   destination = "$env:ProgramFiles\Autodesk\webdeploy\production\**\Fusion\Server\Fusion\Configuration\ThreadData"}

    if ((Test-Path "$PSScriptRoot\..\mpcnc_post_processor")) {
        [pscustomobject]@{source      = "$PSScriptRoot\..\mpcnc_post_processor\MPCNC.cps"
                          destination = "$env:USERPROFILE\AppData\Roaming\Autodesk\Fusion 360 CAM\Posts\MPCNC.cps"}
    }
)

$commands = @(
    {
        (Invoke-WebRequest "https://files.openscad.org/snapshots/").links.href |
            ForEach-Object { "https://files.openscad.org/snapshots/$_" } |
            Where-Object { $_ -like "*-Installer.exe" } |
            Sort-Object -Bottom 1 |
            ForEach-Object {
                Invoke-WebRequest $_ -OutFile $env:TEMP\openscad-installer.exe
            }
        Start-Process $env:TEMP\openscad-installer.exe -ArgumentList "/S", "/D=C:\Program Files\OpenSCAD (Nightly)" -Wait
    }
    { . "$env:ProgramData\chocolatey\bin\bat.exe" cache --build                             }
    { Add-MpPreference -ExclusionPath "C:\Program Files\PowerShell\7\"                      }
    {
        Set-ItemProperty `
            -Path "HKLM:\SOFTWARE\Microsoft\Windows nt\CurrentVersion\Image File Execution Options\notepad.exe" `
            -Name "Debugger" `
            -Value "wt -w 0 split-pane --horizontal --size 0.1 cmd /c `"$((Resolve-Path "$PSScriptRoot\notepad.bat").Path)`""
    }
    { pip3 install neovim-remote }
)


# functions
function Get-GithubRelease {
    param(
        [Parameter(ValueFromPipelineByPropertyName=$true)] [string] $Repo,
        [Parameter(ValueFromPipelineByPropertyName=$true)] [string] $File,
        [Parameter(ValueFromPipelineByPropertyName=$true)] [string] $Folder,
        [Parameter(ValueFromPipelineByPropertyName=$true)] [switch] $AllowPreRelease = $false
    )
    process {
        $version = (Get-Content "$Folder/info.json" -ErrorAction SilentlyContinue
                        | ConvertFrom-Json).tag_name

        $releases = "https://api.github.com/repos/$Repo/releases"

        Write-Host -ForegroundColor Cyan -NoNewline "Determining latest release for $Repo ..."
        $release = ((Invoke-RestMethod $releases) | Where-Object { $_.prerelease -eq $AllowPreRelease })[0]
        $tag = $release.tag_name
        Write-Host -ForegroundColor Cyan -NoNewline " $tag ..."

        if ($tag -eq $version) {
            Write-Host -ForegroundColor Cyan " already installed."
        } else {
            if ($File.EndsWith(".zip")) {
                Remove-Item $Folder -Force -Recurse -ErrorAction SilentlyContinue
                New-Item -ItemType Directory -Path $Folder | Out-Null
            } else {
                Remove-Item "$Folder/$File" -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType Directory -Path $Folder -ErrorAction SilentlyContinue | Out-Null
            Push-Location $Folder

            $File = ($release.assets | Where-Object Name -like $File)[0].name
            if ($File.EndsWith(".zip")) {
                $zip = "temp.zip"
                $download = "https://github.com/$Repo/releases/download/$tag/$File"
                Invoke-WebRequest $download -OutFile $zip

                Microsoft.PowerShell.Archive\Expand-Archive $zip $pwd -Force
                Remove-Item $zip -Force
            } elseif ($File.EndsWith(".msi")) {
                $download = "https://github.com/$Repo/releases/download/$tag/$File"
                Invoke-WebRequest $download -OutFile $File

                msiexec /i (Get-Item $File).FullName #/quiet /norestart
            } else {
                $download = "https://github.com/$Repo/releases/download/$tag/$File"
                Invoke-WebRequest $download -OutFile $File
            }

            $release | ConvertTo-Json -Depth 9 | Out-File "$Folder/info.json"
            Write-Host -ForegroundColor Cyan " completed."

            Pop-Location
        }
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
        if ($Source.EndsWith("*")) {
            Get-ChildItem $Source |
                ForEach-Object {
                    Install-Junction -Source $_ -Destination "$Destination\$($_.Name)"
                }
        } elseif ($Destination.Contains("*")) {
            $directory = [System.IO.Path]::GetDirectoryName($Destination)
            $filename = [System.IO.Path]::GetFileName($Destination)
            Get-ChildItem $directory |
                ForEach-Object{
                    Install-Junction -Source $Source -Destination "$_\$filename"
                }
        } else {
            Remove-Item $Destination -Force -ErrorAction SilentlyContinue | Out-Null

            $directory = [System.IO.Path]::GetDirectoryName($Destination)
            $filename = [System.IO.Path]::GetFileName($Destination)

            if ((Test-Path $source -PathType Leaf)) {
                if (!(Test-Path $directory)) { mkdir $directory }
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
}

# powershell modules
if ($PSBoundParameters.All -or $PSBoundParameters.'pwsh-modules') {
    foreach ($tool in $modules) {
        Write-Host -ForegroundColor Cyan "Installing $tool"
        Install-Module -Name $tool -Force
    }
}


# chocolatey tools
if ($PSBoundParameters.All -or $PSBoundParameters.chocolatey) {
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

    Write-Host -ForegroundColor Cyan ""
    Write-Host -ForegroundColor Cyan "chocolatey packages not in list:"
    . $PSScriptRoot\Powershell\Startup\Invoke-Chocolatey.ps1 -Command list |
        Where-Object 'package name' -notin $tools.Name |
        Where-Object 'package name' -NotLike KB* |
        Where-Object 'package name' -NotLike chocolatey* |
        Where-Object 'package name' -NotLike dotnet* |
        Where-Object 'package name' -NotLike netfx* |
        Where-Object 'package name' -NotLike *.install
}

# npm
if ($PSBoundParameters.All -or $PSBoundParameters.npm) {
    "npm install -g $($npm.name)" | ForEach-Object { Write-Host -ForegroundColor Cyan $_; Invoke-Expression $_ }
}

# junctions
if ($PSBoundParameters.All -or $PSBoundParameters.junctions) {
    $junctions | Install-Junction
}


# patches
if ($PSBoundParameters.All -or $PSBoundParameters.patches) {
    $patches | Update-File
}


# github releases
if ($PSBoundParameters.All -or $PSBoundParameters.'github-releases') {
    $github | Get-GithubRelease
}

# commands
if ($PSBoundParameters.All -or $PSBoundParameters.commands) {
    foreach ($item in $commands) {
        Write-Host -ForegroundColor Cyan "$item"
        Invoke-Command -ScriptBlock $item
    }
}

}
