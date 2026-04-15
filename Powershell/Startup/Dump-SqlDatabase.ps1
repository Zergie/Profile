[cmdletbinding()]
param(
    [Parameter(Mandatory)]
    [string]
    $Database,

    [Parameter()]
    [string]
    $OutputPath
)

Write-Progress -Activity "Dumping Database" -PercentComplete 0
$tables = Invoke-Sqlcmd -Query "SELECT name FROM sys.tables" -Database $Database |
    Where-Object Name -NotLike "spt_*" |
    Where-Object Name -NotIn @("MSreplication_options") |
    ForEach-Object Name

if (-not $tables -or $tables.Count -eq 0) {
    Write-Error "No user tables found in database '$Database'."
    Write-Progress -Activity "Dumping Database" -Completed
    exit 1
}

if (-not $OutputPath) {
    $OutputPath = (New-Item -ItemType Directory -Path "." -Name $Database -Force).FullName
} else {
    $OutputPath = (Resolve-Path -Path $OutputPath).Path
}

Get-ChildItem $OutputPath -Filter "*.json" |
    ForEach-Object { Write-Host "Removing existing file: $($_.FullName)"; $_.FullName } |
    Remove-Item -Force

$index = 0
foreach ($table in $tables) {
    $percentComplete = [math]::Round((($index / $tables.Count) * 100), 2)
    $index++
    Write-Progress -Activity "Dumping Database" -PercentComplete $percentComplete -Status "Exporting table $table ($($index + 1) of $($tables.Count))"

    $tableOutputPath = Join-Path -Path $OutputPath -ChildPath "$table.json"
    Invoke-Sqlcmd -Query "SELECT * FROM [$table]" -Database $Database |
        ConvertTo-Csv |
        ConvertFrom-Csv |
        ConvertTo-Json |
        Set-Content -Encoding UTF8 -Path $tableOutputPath
}
Write-Progress -Activity "Dumping Database" -Completed

Compress-Archive -Path (Join-Path -Path $OutputPath -ChildPath "*.json") -DestinationPath (Join-Path -Path $OutputPath -ChildPath "..\$Database.zip") -Force
Remove-Item $OutputPath -Recurse -Force

