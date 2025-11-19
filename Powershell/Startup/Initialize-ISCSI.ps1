[cmdletbinding()]
param(
    [Parameter(ParameterSetName='StopParameterSet')]
    [switch]
    $Stop,

    [Parameter()]
    [int]
    $Delay = 0
)
$DriveLetter = "Y:"
$VolumeName = "\\?\Volume{1093b91d-97e0-11f0-99cb-e848b8c82000}\"
$Addresses = @(
    "10.0.0.27"
    "10.0.0.28"
)

# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    $expression = @(
        "pwsh"
        "-NoProfile"
        if ($PSBoundParameters.Debug.IsPresent) { "-NoExit" }
        "-File"
        "`"$($MyInvocation.MyCommand.Path)`""
        $MyInvocation.BoundParameters.GetEnumerator() |
            ForEach-Object { "-$($_.Key) $(if ($_.Value.GetType().Name -eq 'SwitchParameter' -and $_.Value.IsPresent) { '' } else { $_.Value })" }
    ) | Join-String -Separator " "

    "sudo {${expression}}" |
        ForEach-Object {
            Write-Host -ForegroundColor Cyan $_
            Invoke-Expression $_
        }
    exit
}

function Invoke-Action {
    param (
        [string]$Message,
        [scriptblock]$Action,
        [string]$SuccessMessage = "Done",
        [int]$RetryCount = 5
    )
    $Finished = $false
    Write-Host "$Message " -NoNewline

    while (-not $Finished) {
        try {
            $Action.Invoke() | Out-Null
            Write-Host -ForegroundColor Green $SuccessMessage
            $Finished = $true
        } catch {
            $RetryCount--
            if ($RetryCount -gt 0) {
                Write-Host -NoNewline "."
                Start-Sleep -Seconds 1
            } else {
                Write-Host -ForegroundColor Red " $($_.Exception.InnerException.ErrorRecord)"
                $Finished = $true
            }
        }
    }
}

if ($Delay -gt 0) {
    Write-Host "Waiting for $Delay seconds before proceeding .." -NoNewline
    Start-Sleep -Seconds $Delay
    Write-Host -ForegroundColor Green " Done"
}

if ($Stop) {
    Write-Host "Disconnecting from iSCSI targets and stopping service..."
} else {
    $Mount = $true
    Write-Host "Starting iSCSI service and connecting to targets .." -NoNewline
    Get-Service -Name MSiSCSI | Start-Service
    Write-Host -ForegroundColor Green " Started"
}

# Write-Host "Unmounting volume $DriveLetter if it exists..."
# mountvol $DriveLetter /P

Write-Host "Disconnecting from all iSCSI targets .." -NoNewline
Get-IscsiTarget | Disconnect-IscsiTarget -Confirm:$false
Write-Host -ForegroundColor Green " Disconnected"

Write-Host "Removing all iSCSI target portals .." -NoNewline
Get-IscsiTargetPortal | Remove-IscsiTargetPortal -Confirm:$false
Write-Host -ForegroundColor Green " Removed"

if ($Mount) {
    $Addresses |
        ForEach-Object {
            Invoke-Action `
                -Message "Testing connectivity to $_ .. " `
                -Action {
                    $status = (Invoke-WebRequest $_ -ConnectionTimeoutSeconds 5).StatusDescription
                    if ($status -ne "OK") {
                        throw "$status"
                    }
                } `
                -SuccessMessage "OK"
        }

    $Addresses |
        ForEach-Object {
            Invoke-Action `
                -Message "Adding iSCSI target portal $_ .. " `
                -Action {
                    New-IscsiTargetPortal -TargetPortalAddress $_ -ErrorAction Stop | Out-Null
                } `
                -SuccessMessage "Added"
        }

    Get-IscsiTarget |
        ForEach-Object {
            Invoke-Action `
                -Message "Connecting to iSCSI target $($_.NodeAddress) .. " `
                -Action {
                    Connect-IscsiTarget -NodeAddress $_.NodeAddress -ErrorAction Stop | Out-Null
                } `
                -SuccessMessage "Connected"
        }

    # Write-Host "Mounting volume $VolumeName to drive letter $DriveLetter..."
    # mountvol $DriveLetter $VolumeName

    Invoke-Action `
        -Message "Checking connected iSCSI targets .." `
        -Action {
            while ($null -eq (Get-ChildItem $DriveLetter -ErrorAction SilentlyContinue)) {
                Write-Host "." -NoNewline
                Start-Sleep -Seconds 2
            }
        } `
        -SuccessMessage "Volume is accessible"

    Get-ChildItem $DriveLetter -ErrorAction SilentlyContinue
} elseif ($Stop) {
    Write-Host "Stopping iSCSI service..."
    Get-Service -Name MSiSCSI | Stop-Service -Force
}
