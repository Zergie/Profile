[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true,
               Position = 1)]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Path,


    [Parameter(Mandatory = $false)]
    [int]
    $Seconds = 1
)

Write-Host "Watching File '$Path'"

$LastCheck = [datetime]::Now
while (1) {
    foreach ($p in $Path) {
        Get-ChildItem -Path $p -ErrorAction SilentlyContinue |
            Where-Object LastWriteTime -gt $LastCheck
        $LastCheck = [datetime]::Now
        Start-Sleep -Seconds $Seconds
    }
}
