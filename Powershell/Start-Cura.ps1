$cura = Get-ChildItem "$env:ProgramFiles\UltiMaker Cura *" |
    Get-ChildItem -Filter UltiMaker-Cura.exe |
    Sort-Object -Descending FullName |
    Select-Object -First 1 |
    ForEach-Object FullName
. $cura "$args"

