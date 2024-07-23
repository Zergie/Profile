[cmdletbinding()]
param(
)
$path = "$PSScriptRoot\..\Locations.json"
Get-Content $path -Encoding UTF8 |
    Join-String -Separator "," |
    ForEach-Object -Begin {"["} -Process {$_} -End {"]"} |
    ConvertFrom-Json
