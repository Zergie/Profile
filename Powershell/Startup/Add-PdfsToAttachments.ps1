Get-Issues -State New | Get-Attachments

Get-ChildItem | 
    Where-Object basename -Match "^\d+" | 
    Get-ChildItem -Recurse | 
    Where-Object Name -Match "Rückmeldung" | 
    Remove-Item

Get-ChildItem | 
    Where-Object basename -Match "^\d+" | 
    Get-ChildItem -Recurse | 
    ConvertTo-Pdf

Get-ChildItem | 
    Where-Object basename -Match "^\d+" | 
    Get-ChildItem -Recurse | 
    Where-Object Name -NotMatch "\.pdf$" | 
    Remove-Item

Get-ChildItem | 
    Where-Object basename -Match "^\d+" | 
    Get-ChildItem -Recurse |
    New-Attachments