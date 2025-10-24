[cmdletbinding()]
param(
    [Parameter(ParameterSetName='StopParameterSet')]
    [switch]
    $Stop,

    [Parameter()]
    [int]
    $Delay = 0
)
$DriveLetter = "F:"
$VolumeName = "\\?\Volume{1093b91d-97e0-11f0-99cb-e848b8c82000}\"
$Addresses = @(
    "10.0.0.27"
    "10.0.0.28"
)

if ($Delay -gt 0) {
    Write-Host "Waiting for $Delay seconds before proceeding..."
    Start-Sleep -Seconds $Delay
}

if ($Stop) {
    Write-Host "Disconnecting from iSCSI targets and stopping service..."
} else {
    $Mount = $true
    Write-Host "Starting iSCSI service and connecting to targets..."
    Get-Service -Name MSiSCSI | Start-Service
}

# Write-Host "Unmounting volume $DriveLetter if it exists..."
# mountvol $DriveLetter /P

Write-Host "Disconnecting from all iSCSI targets..."
Get-IscsiTarget | Disconnect-IscsiTarget -Confirm:$false

Write-Host "Removing all iSCSI target portals..."
Get-IscsiTargetPortal | Remove-IscsiTargetPortal -Confirm:$false

if ($Mount) {
    Write-Host "Verifying connectivity to iSCSI target portals..."
    $Addresses |
        ForEach-Object {
            Write-Host -ForegroundColor Cyan "Testing connection to $_ .. " -NoNewline
            $status = (Invoke-WebRequest $_ -ConnectionTimeoutSeconds 5).StatusDescription
            if ($status -eq "OK") {
                Write-Host -ForegroundColor Green $status
            } else {
                Write-Host -ForegroundColor Red $status
            }
        } |
        Format-Table

    Write-Host "Adding iSCSI target portal..."
    $Addresses |
        ForEach-Object {
            Write-Host -ForegroundColor Cyan "New-IscsiTargetPortal -TargetPortalAddress $_".Trim()
            New-IscsiTargetPortal -TargetPortalAddress $_ -ErrorAction Stop
        }

    Write-Host "Discovering iSCSI targets..."
    Get-IscsiTarget |
        ForEach-Object {
            Write-Host -ForegroundColor Cyan "Connect-IscsiTarget -NodeAddress $($_.NodeAddress)".Trim()
            Connect-IscsiTarget -NodeAddress $_.NodeAddress
        }

    # Write-Host "Mounting volume $VolumeName to drive letter $DriveLetter..."
    # mountvol $DriveLetter $VolumeName

    Write-Host "Checking connected iSCSI targets..."
    Get-ChildItem $DriveLetter -ErrorAction Stop
} elseif ($Stop) {
    Write-Host "Stopping iSCSI service..."
    Get-Service -Name MSiSCSI | Stop-Service -Force
}