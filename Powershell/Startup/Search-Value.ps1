[cmdletbinding()]
param (
    [Parameter(Mandatory)]
    [string]
    $Database,

    [Parameter()]
    [string[]]
    $Table,

    [Parameter(Mandatory)]
    [string]
    $Pattern
)

Get-SqlTable -Database $Database |
    Where-Object { $_.Name -in $Table -or $Table.Length -eq 0 } |
    ForEach-Object {
        [pscustomobject]@{
            table=$_.Name
            rows=Get-SqlTable -Database $Database -Table $_.Name
        }
    } |
    ForEach-Object {
        $parent=$_
        foreach ($item in $_.rows) {
            Get-Member -InputObject $item -Type NoteProperty |
                ForEach-Object {
                    [pscustomobject] @{
                        table=$parent.table
                        column=$_.Name
                        value=$item.($_.Name)
                        row = $item
                    }
                }
        }
    } |
    Where-Object Value -Match $Pattern
