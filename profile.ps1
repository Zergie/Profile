﻿trap { Write-Warning ($_.ScriptStackTrace | Out-String) }
# # # # # # # # # # # Bleeping Computer # # # # # # # # # # #
# These get imported no matter what, but we can save a few ms by importing them ourselves
# Except that Azure CloudShell pwsh used to freak out if you tried to load these explicitly.
Import-Module -Name Microsoft.PowerShell.Management, Microsoft.PowerShell.Security, Microsoft.PowerShell.Utility -Verbose:$false

# The purpose of this profile script is to:
# 1. Fix the PSModulePath, which must be different in different versions of PowerShell
# 2. Initialize settings for modules (PSReadLine) which have defaults I don't like, and no configuration
# 3. Import the Profile module (which this script is part of, technically)
# Set the profile directory first, so we can refer to it from now on.
Set-Variable ProfileDir (Split-Path $Profile.CurrentUserAllHosts -Parent) -Scope Global -Option AllScope, Constant -ErrorAction SilentlyContinue

# PART 1: Fix the PSModulePath
function Select-UniquePath {
    <#
        .SYNOPSIS
            Select-UniquePath normalizes path variables and ensures only folders that actually currently exist are in them.
        .EXAMPLE
            $ENV:PATH = $ENV:PATH | Select-UniquePath
    #>
    [CmdletBinding()]
    param(
        # Paths to folders
        [Parameter(Position = 1, Mandatory = $true, ValueFromRemainingArguments = $true, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Path,

        # If set, output the path(s) as an array of paths
        # Otherwise output joined by -Delimiter
        [switch]$AsArray,

        # The Path value is split by the delimiter. Defaults to '[IO.Path]::PathSeparator' so you can use this on $Env:Path
        [Parameter(Mandatory = $False)]
        [AllowNull()]
        [string]$Delimiter = [IO.Path]::PathSeparator
    )
    begin {
        # Write-Information "Select-UniquePath $Delimiter $Path" -Tags "Trace", "Enter"
        [string[]]$Output = @()
        [string[]]$oldFolders = @()
        $CaseInsensitive = $false -notin (Test-Path $PSScriptRoot.ToLowerInvariant(), $PSScriptRoot.ToUpperInvariant())
    }
    process {
        $Output += $(
            # Split and trim trailing slashes to normalize, and drop empty strings
            $oldFolders += $folders = $Path -split $Delimiter -replace '[\\\/]$' -gt ""

            # Remove duplicates that are only different by case on FileSystems that are not case-sensitive
            if ($CaseInsensitive) {
                # Converting a path with wildcards forces Windows to calculate the ACTUAL case of the path
                $folders -replace '(?<!:|\\|/|\*)(\\|/|$)', '*$1'
            } else {
                $folders
            }
        )
    }
    end {
        # Use Get-Item -Force to ensure we don't loose hidden folders
        # This won't work: Convert-Path C:\programdata*
        # But make sure we didn't add anything that wasn't already there
        [string[]]$Output = (Get-Item $Output -Force).FullName | Where-Object { $_ -iin $oldFolders }

        if ((-not $AsArray) -and $Delimiter) {
            # This is just faster than Select-Object -Unique
            [System.Linq.Enumerable]::Distinct($Output) -join $Delimiter
        } else {
            [System.Linq.Enumerable]::Distinct($Output)
        }
        # Write-Information "Select-UniquePath $Delimiter $Path" -Tags "Trace", "Exit"
    }
}
# NOTES:
# 1. The main concern is to keep things in order:
#     a. User path ($Home) before machine path ($PSHome)
#     b. Existing PSModulePath before other versions
#     c. current version before other versions
# 2. I don't worry about duplicates because `Select-UniquePath` takes care of it
# 3. I don't worry about missing paths, because `Select-UniquePath` takes care of it
# 4. I don't worry about x86 because I never use it.
# 5. I don't worry about linux because I add paths based on `$PSScriptRoot`, `$Profile` and `$PSHome`
$Env:PSModulePath =
    # Prioritize "this" location (e.g. CloudDrive) UNLESS it's ~\projects\modules
    @(if (($ModuleRootParent = Split-Path $PSScriptRoot) -ne "$Home\Projects\Modules") { $ModuleRootParent }) +
    # The normal first location in PSModulePath is the "Modules" folder next to the real profile:
    @(Join-Path $ProfileDir Modules) +
    # After that, whatever is in the environment variable
    @($Env:PSModulePath) +
    # PSHome is where powershell.exe or pwsh.exe lives ... it should already be in the Env:PSModulePath, but just in case:
    @(Join-Path $PSHome Modules) +
    # FINALLY, add the Module paths for other PowerShell versions, because I'm an optimist
    @(Join-Path (Split-Path (Split-Path $PSHome)) *PowerShell\ | Convert-Path | Get-ChildItem -Filter Modules -Directory -Recurse -Depth 2).FullName +
    @(Convert-Path @(
        Split-Path $ProfileDir | Join-Path -ChildPath *PowerShell\Modules
        # These may be duplicate or not exist, but it doesn't matter
        "$Env:ProgramFiles\*PowerShell\Modules"
        "$Env:ProgramFiles\*PowerShell\*\Modules"
        "$Env:SystemRoot\System32\*PowerShell\*\Modules"
    )) +
    # Guarantee my ~\Projects\Modules are there so I can load my dev projects
    @("$Home\Projects\Modules") +
    # To ensure canonical path case, wildcard every path separator and then convert-path
    @() | Select-UniquePath

# PART 2. Fix default values
# PSReadLine is usually pre-loaded if it can be
if (Get-Module PSReadline) {
    Set-PSReadlineKeyHandler Ctrl+Alt+c CaptureScreen
    Set-PSReadlineKeyHandler Ctrl+Shift+r ForwardSearchHistory
    Set-PSReadlineKeyHandler Ctrl+r ReverseSearchHistory

    Set-PSReadlineKeyHandler Ctrl+DownArrow HistorySearchForward
    Set-PSReadlineKeyHandler Ctrl+UpArrow HistorySearchBackward
    Set-PSReadLineKeyHandler Ctrl+Home BeginningOfHistory

    Set-PSReadlineKeyHandler Ctrl+m SetMark
    Set-PSReadlineKeyHandler Ctrl+Shift+m ExchangePointAndMark

    Set-PSReadlineKeyHandler Ctrl+K KillLine
    Set-PSReadlineKeyHandler Ctrl+I Yank

    Set-PSReadLineKeyHandler Ctrl+h BackwardDeleteWord
    Set-PSReadLineKeyHandler Ctrl+Enter AddLine
    Set-PSReadLineKeyHandler Ctrl+Shift+Enter AcceptAndGetNext
}

# PART 3. Import the Profile module
#   For now, we're not going to import the profile module because it takes too long
#   Instead we list the modules that would be imported and define Import-DefaultModule to import them

# Note these are dependencies of the Profile module, but it's faster to load them explicitly up front
$DefaultModules = @(
    @{ ModuleName="Environment";        RequiredVersion="1.1.0" }
    @{ ModuleName="Configuration";      RequiredVersion="1.4.0" }
    @{ ModuleName="Pansies";            RequiredVersion="2.1.0" }
    @{ ModuleName="PowerLine";          RequiredVersion="3.2.2" }
    # @{ ModuleName="PSReadLine";       ModuleVersion="2.0.0" }

    @{ ModuleName = "DefaultParameter"; RequiredVersion = "2.0.0" }
    @{ ModuleName = "ErrorView";        RequiredVersion = "0.0.2" }
    @{ ModuleName = "Profile";          ModuleVersion = "1.3.0" }

    if ($Env:WT_SESSION) {
        @{ ModuleName = "Theme.PowerShell"; ModuleVersion = "0.0" }
        @{ ModuleName = "Theme.PSReadline"; ModuleVersion = "0.0" }
        @{ ModuleName = "Theme.Terminal";   ModuleVersion = "0.0" }
        @{ ModuleName = "EzTheme";          ModuleVersion = "0.0" }
    } else {
        @{ ModuleName = "Theme.PowerShell"; ModuleVersion = "0.0" }
        @{ ModuleName = "Theme.PSReadline"; ModuleVersion = "0.0" }
        @{ ModuleName = "EzTheme";          ModuleVersion = "0.0" }
    }
)

function Import-DefaultModule {
    Import-Module -FullyQualifiedName $DefaultModules

    if (Test-Elevation) {
        Import-Theme Lightly -IncludeModule Theme.PowerShell, Theme.PSReadLine, Theme.Terminal, PowerLine
    } elseif ($PSVersionTable.PSVersion.Major -le 5) {
        Import-Theme Legacy -IncludeModule Theme.PowerShell, Theme.PSReadLine, Theme.Terminal, PowerLine
    } else {
        Import-Theme Darkly -IncludeModule Theme.PowerShell, Theme.PSReadLine, Theme.Terminal, PowerLine
    }
}

# I prefer that my sessions start in a predictable location, regardless of elevation, etc.
if ($psEditor.Workspace.Path) { # in VS Code, start in the workspace!
    Set-Location ([Uri]$psEditor.Workspace.Path).AbsolutePath
} else {
    Set-Location $ProfileDir
}

## Relax the code signing restriction so we can actually get work done
Set-ExecutionPolicy RemoteSigned Process