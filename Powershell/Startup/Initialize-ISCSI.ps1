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
    $arguments = @(
        "-NoProfile"
        if ($PSBoundParameters.Debug.IsPresent) { "-NoExit" }
        "-File"
        $MyInvocation.MyCommand.Path
        $MyInvocation.BoundParameters.GetEnumerator() |
            ForEach-Object {
                if ($_.Value -is [System.Management.Automation.SwitchParameter]) {
                    '-{0}:${1}' -f $_.Key, $_.Value.IsPresent
                } else {
                    "-$($_.Key)"
                    "$($_.Value)"
                }
            }
    )

    & gsudo --direct (Join-Path $PSHOME 'pwsh.exe') @arguments
    exit $LASTEXITCODE
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
    Set-Service -Name MSiSCSI -StartupType Automatic -ErrorAction Stop
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
    foreach ($address in $Addresses) {
        Invoke-Action `
            -Message "Testing connectivity to $address .. " `
            -Action {
                $status = (Test-NetConnection $address).PingSucceeded
                if (-not $status) {
                    throw "Ping failed"
                }
            } `
            -SuccessMessage "OK"
    }

    foreach ($address in $Addresses) {
        Invoke-Action `
            -Message "Adding iSCSI target portal $address .. " `
            -Action {
                New-IscsiTargetPortal -TargetPortalAddress $address -ErrorAction Stop | Out-Null
            } `
            -SuccessMessage "Added"
    }

    foreach ($target in (Get-IscsiTarget)) {
        $nodeAddress = $target.NodeAddress
        Invoke-Action `
            -Message "Connecting to iSCSI target $nodeAddress .. " `
            -Action {
                # Windows may reconnect a persistent session after discovery.
                if (-not (Get-IscsiTarget -NodeAddress $nodeAddress -ErrorAction Stop).IsConnected) {
                    Connect-IscsiTarget -NodeAddress $nodeAddress -ErrorAction Stop | Out-Null
                }
            } `
            -SuccessMessage "Connected"

        Invoke-Action `
            -Message "Registering persistent iSCSI sessions for $nodeAddress .. " `
            -Action {
                $sessions = @(Get-IscsiSession -ErrorAction Stop |
                    Where-Object { $_.TargetNodeAddress -eq $nodeAddress -and $_.IsConnected })
                if ($sessions.Count -eq 0) {
                    throw "No connected iSCSI session found for $nodeAddress"
                }
                foreach ($session in $sessions) {
                    if (-not $session.IsPersistent) {
                        Register-IscsiSession -SessionIdentifier $session.SessionIdentifier -ErrorAction Stop
                    }
                }
            } `
            -SuccessMessage "Persistent"
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
