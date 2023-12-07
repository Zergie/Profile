[CmdletBinding()]
param (
)
process {
    if ($null -ne (Get-Process MSACCESS -ErrorAction SilentlyContinue)) {
        if (!(Get-Process MSACCESS).CloseMainWindow()) {
            try {
                . "$PSScriptRoot/Invoke-MsAccess.ps1" -Procedure Application.Quit | Out-Null
            } catch {
            }
        }

        if ($null -ne (Get-Process MSACCESS -ErrorAction SilentlyContinue)) {
            Start-Sleep -Seconds 5
            try {
                Stop-Process -ProcessName MSACCESS
                Write-Host "MSACCESS killed." -ForegroundColor Red
            } catch {
            }
        } else {
            Write-Host "MSACCESS did exit gracefully."
        }
    } else {
        Write-Host "MSACCESS is not running." -ForegroundColor Red
    }
}
