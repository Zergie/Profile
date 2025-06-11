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
    } elseif (-not $PSBoundParameters.ContainsKey("Table")) {
        $result
    } else {
        $props = $result |
            Select-Object -First 1 |
            ForEach-Object psadapted |
            Get-Member -MemberType Property -ErrorAction SilentlyContinue

        $result |
            Select-Object -Property $props.Name |
            ForEach-Object {
                if ("LetzteDbRevision" -in $props.Name) {
                    $_.LetzteDbRevision = ([int]($_.LetzteDbRevision[0])).ToString("000")
                }
                if ("MandantDbRevision" -in $props.Name) {
                    $_.MandantDbRevision = ([int]($_.MandantDbRevision[0])).ToString("000")
                }

                $item = $_
                $props |
                    Where-Object Definition -Like "datetime *" |
                    ForEach-Object {
                        $v = $item.($_.Name)
                        if ($v -eq [DBNull]::Value) {
                        } elseif ($v.Year -eq 1899 -and $v.Month -eq 12 -and $v.Day -eq 30) {
                            $item |
                                Add-Member `
                                    -Force `
                                    -NotePropertyName $_.Name `
                                    -NotePropertyValue ([System.TimeOnly]::FromDateTime($v))
                        } elseif ($v.Hour -eq 0 -and $v.Minute -eq 0 -and $v.Second -eq 0) {
                            $item |
                                Add-Member `
                                    -Force `
                                    -NotePropertyName $_.Name `
                                    -NotePropertyValue ([System.DateOnly]::FromDateTime($v))
                        }
                    }

                $Global:Table = $Table
                Add-Member -InputObject $_ -MemberType ScriptMethod -Name "::Table" -Value { $Global:Table }
                $Global:Filter = $Filter
                Add-Member -InputObject $_ -MemberType ScriptMethod -Name "::Filter" -Value { $Global:Filter }

                if (!$PSBoundParameters.ContainsKey('Fields')) {
                    $Fields = @()
                    $Fields += Invoke-Sqlcmd `
                        -Database $Database `
                        -Query "SELECT column_name FROM Information_Schema.columns WHERE table_name='$Table' ORDER BY ORDINAL_POSITION" |
                        ForEach-Object column_name
                }

                $item | Select-Object $Fields
            }
    }
}
