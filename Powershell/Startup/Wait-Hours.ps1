[cmdletbinding()]
param(
    [Parameter(Mandatory,
               ValueFromPipeline,
               ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [double]
    $Hours
)
if ($null -eq $PSBoundParameters.ErrorAction) { $ErrorActionPreference = 'Stop' }

if ($Hours -gt 0) {
    $Wait = [TimeSpan]::FromHours($WaitHours)
    Write-Host
    while ($Wait.TotalHours -gt 1) {
        Write-Host "Waiting $($Wait.TotalHours) h, sending @ $([datetime]::Now.Add($Wait).ToString("HH:mm")) .."
        Start-Sleep -Duration ([TimeSpan]::FromHours([System.Math]::Min(1, $Wait.TotalHours)))
        $Wait -= [TimeSpan]::FromHours(1)
    }
    while ($Wait.TotalMinutes -gt 1) {
        Write-Host "Waiting $($Wait.TotalMinutes.ToString("0")) minutes, sending @ $([datetime]::Now.Add($Wait).ToString("HH:mm")) .."
        Start-Sleep -Duration ([TimeSpan]::FromMinutes([System.Math]::Min(10, $Wait.TotalMinutes)))
        $Wait -= [TimeSpan]::FromMinutes(10)
    }
    while ($Wait.TotalSeconds -gt 1) {
        Write-Host "Waiting $($Wait.TotalSeconds.ToString("0")) seconds, sending @ $([datetime]::Now.Add($Wait).ToString("HH:mm")) .."
        Start-Sleep -Duration ([TimeSpan]::FromSeconds([System.Math]::Min(10, $Wait.TotalSeconds)))
        $Wait -= [TimeSpan]::FromSeconds(10)
    }
    Write-Host
}
