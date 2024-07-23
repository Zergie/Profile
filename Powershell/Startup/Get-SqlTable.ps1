[cmdletbinding()]
param(
    [Parameter(Mandatory)]
    [string]
    $Database,

    [Parameter(Position=0)]
    [string]
    $Table,

    [Parameter(Position=1)]
    [string[]]
    $Fields,

    [Parameter(Position=2)]
    [int]
    $First,

    [string[]]
    $Sort,

    [switch]
    $Descending,

    [Parameter(Position=2, ParameterSetName='FilterParameterSet')]
    [string]
    $Filter,

    [Parameter(Position=3, ParameterSetName='FilterParameterSet')]
    [object]
    $Value,

    [switch]
    $Unique,

    [switch]
    $Progress,

    [Parameter()]
    [string]
    $OutFile,

    [switch]
    $NullValues
)
if ($Progress) {
    Invoke-WithProgress $MyInvocation
} else {
    $Query = "SELECT "

    if ($Unique) {
        $Query += "DISTINCT "
    }

    if ($PSBoundParameters.ContainsKey("First")) {
        $Query += "TOP $First "
    }

    if ($PSBoundParameters.ContainsKey("Fields")) {
        $Query += "$(($Fields | ForEach-Object { "[$_]" }) -join ',') "
    }
    elseif (-not $PSBoundParameters.ContainsKey("Table")) {
        $Query += "name, create_date, modify_date, N'$Database' AS [database] "
    }
    else {
        $Query += "* "
    }

    if (-not $PSBoundParameters.ContainsKey("Table")) {
        $Query += "FROM sys.tables "
    }
    elseif ($Table.Contains(".")) {
        $Query += "FROM $Table "
    }
    else {
        $Query += "FROM [$($Table.TrimStart("[").TrimEnd("]"))] "
    }

    if ($PSBoundParameters.ContainsKey("Filter")) {
        $Query += " WHERE $(Format-SqlFilterCriteria $Filter $Value)"
    }

    if ($PSBoundParameters.ContainsKey("Sort")) {
        $Query += "ORDER BY "
        $Query += ($sort |
                    ForEach-Object { if ($_.Contains(' ')) { "[$_]" } else { $_ } } |
                    ForEach-Object { if ($Descending) { "$_ DESC" } else { "$_ ASC" } }
                  ) -join ","
    }
    elseif (-not $PSBoundParameters.ContainsKey("Table")) {
        $Query += "ORDER BY 1, 2, 3, 4"
    }

    Write-Verbose $Query

    if (-not $PSBoundParameters.ContainsKey("Table")) {
        $result = Invoke-Sqlcmd -Database $Database -Query $Query |
            ConvertTo-Csv |
            ConvertFrom-Csv |
            ForEach-Object {
                [pscustomobject]@{
                    name        = $_.name
                    create_date = [System.DateTime]::Parse($_.create_date)
                    modify_date = [System.DateTime]::Parse($_.modify_date)
                    database    = $_.database
                }
            }
    } elseif ($NullValues) {
        $result = Invoke-Sqlcmd -Database $Database -Query $Query |
            ForEach-Object {
                $o = $_
                Get-Member -InputObject $o -Type Properties |
                ForEach-Object Name |
                ForEach-Object { $o.$_ = [System.DBNull]::Value }
                $o
            } |
            ConvertTo-Csv |
            ConvertFrom-Csv
    } else {
        $result = Invoke-Sqlcmd -Database $Database -Query $Query
    }


    if ($PSBoundParameters.ContainsKey("OutFile")) {
        if ($OutFile -eq ".") {
            $OutFile = "${Table}.json"
        }
        $result |
            ConvertTo-Json |
            Set-Content $OutFile -Encoding utf-8

        Get-ChildItem $OutFile
    } else {
        # $result
        $result |
            ForEach-Object {
                $props = $_.psobject.Properties.Name

                if ("LetzteDbRevision" -in $props) {
                    $_.LetzteDbRevision = ([int]($_.LetzteDbRevision[0])).ToString("000")
                }
                if ("MandantDbRevision" -in $props) {
                    $_.MandantDbRevision = ([int]($_.MandantDbRevision[0])).ToString("000")
                }

                if ($PSBoundParameters.ContainsKey("Table")) {
                    $_ |
                        Select-Object -ExcludeProperty RowError,RowState,HasErrors,ItemArray,Table |
                        Add-Member -NotePropertyName "::Table" -NotePropertyValue $Table -PassThru
                } else {
                    $_
                }
            }
    }
}
