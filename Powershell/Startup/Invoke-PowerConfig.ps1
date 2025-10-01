<#
.synopsis
    Powercfg Wrapper
.DESCRIPTION
    A PowerShell wrapper for Powercfg.exe
    https://docs.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options
.NOTES
    This script is a wrapper around the Powercfg.exe command-line tool.
.PARAMETER List
    Lists all power schemes on the system.
.PARAMETER GetActiveScheme
    Retrieves the currently active power scheme.
.PARAMETER Help
    Displays help information for the Powercfg.exe tool.
.PARAMETER SetActive
    Sets the active power scheme by name or GUID.
#>

[CmdletBinding()]
param (
    [Alias('L')]
    [switch]
    $List,

    [switch]
    $GetActiveScheme,

    [switch]
    $Help

    # [Alias('Q')]
    # [string]
    # $Query,

    # [Alias('X')]
    # [string]
    # $Change,

    # [string]
    # $ChangeName,

    # [string]
    # $DuplicateScheme,

    # [Alias('D')]
    # [string]
    # $Delete,

    # [string]
    # $DeleteSetting,

    # [string]
    # $SetActiveValueIndex,

    # [string]
    # $SetDCValueIndex,

    # [string]
    # $Import,

    # [string]
    # $Export,

    # [string]
    # $Aliases,

    # [string]
    # $GetSecurityDescriptor,

    # [string]
    # $SetSecurityDescriptor,

    # [Alias('H')]
    # [string]
    # $Hibernate,

    # [Alias('A')]
    # [string]
    # $AvailableSleepStates,

    # [string]
    # $DeviceQuery,

    # [string]
    # $DeviceEnableWake,

    # [string]
    # $DeviceDisableWake,

    # [string]
    # $LastWake,

    # [string]
    # $WakeTimers,

    # [string]
    # $Requests,

    # [string]
    # $RequestsOverride,

    # [string]
    # $Energy,

    # [string]
    # $BatteryReport,

    # [string]
    # $SleepStudy,

    # [string]
    # $SrumUtil,

    # [string]
    # $SystemSleepDiagnostics,

    # [string]
    # $SystemPowerReport,

    # [string]
    # $PowerThrottling,

    # [Alias('PXML')]
    # [string]
    # $ProvisioningXml
)
dynamicparam {
    function Get-List {
        powercfg.exe /LIST |
            Select-Object -Skip 3 |
            ForEach-Object { $_.Split(":")[1].Trim() } |
            ForEach-Object {
                $p = $_.Split(" ", 2)
                [pscustomobject]@{
                    GUID = $p[0].Trim()
                    Name = $p[1].Replace("(", "").Replace(")", "").TrimStart().TrimEnd(" *")
                }
            }
    }

    Set-Alias "New-DynamicParameter" "$PSScriptRoot\New-DynamicParameter.ps1"
    @(
        [pscustomobject]@{
            Type  = [string]
            Alias = 'S'
            Name  = "SetActive"
            ValidateSet =  Get-List |
                ForEach-Object {
                    $_.Name
                }
        }
    ) | New-DynamicParameter
}
process {
    function __powercfg {
        param ([string] $arguments)
        Write-Host -ForegroundColor Cyan "powercfg.exe $arguments"
        Invoke-Expression "powercfg.exe $arguments"
    }
    function __error {
        param ([string] $message)
        Write-Host -ForegroundColor Red $message
    }


    if ($PSBoundParameters.List) {
        Write-Host -ForegroundColor Cyan "powercfg.exe /LIST"
        Get-List
    } elseif ( $PSBoundParameters.SetActive ) {
        $object = Get-List | Where-Object { $_.Name.StartsWith($($PSBoundParameters.SetActive)) }
        if (-not $object) {
            __error "Power scheme '$($PSBoundParameters.SetActive)' not found."
            Get-List
            return
        } elseif ($object.Count -gt 1) {
            __error "Multiple power schemes found matching '$($PSBoundParameters.SetActive)'. Please specify a more specific name."
            $object
            return
        } else {
            __powercfg "/SETACTIVE $($object.GUID)"
            powercfg /GETACTIVESCHEME
        }
    } elseif ($PSBoundParameters.GetActiveScheme) {
        __powercfg "/GETACTIVESCHEME"
    } else {
        Get-Help $PSScriptRoot\Invoke-PowerConfig.ps1 -Detailed
        # powercfg.exe /help
    }

}
