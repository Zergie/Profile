[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true,
               Position = 1)]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path,


    [Parameter(Mandatory = $false)]
    [int]
    $Seconds = 1
)

Write-Host "Watching folder '$Path'"

while (1) {
    Get-ChildItem -Path $Path -Filter $Filter |
        ForEach-Object {
            bat $_
            Remove-Item $_
        }
    Start-Sleep -Seconds $Seconds
}

