
    param(
        [Parameter(Mandatory)]
        [string]
        $Database,

        [string]
        $Table,

        [string[]]
        $Fields,

        [int]
        $First,

        [string[]]
        $Sort,

        [switch]
        $Descending,

        [Parameter(ParameterSetName='FilterParameterSet')]
        [string]
        $Filter,

        [Parameter(ParameterSetName='FilterParameterSet')]
        [object]
        $Value,

        [switch]
        $Unique,

        [switch]
        $NullValues
    )
        $Query = "SELECT "

        if ($Unique) {
            $Query += "DISTINCT "
        }

        if ($PSBoundParameters.ContainsKey("First")) {
            $Query += "TOP $First "
        }

        if ($PSBoundParameters.ContainsKey("Fields")) {
            # $Query += "[$($Fields -join "],[")] "
            # $Query += "$(($Fields | ForEach-Object { if ($_.Contains(' ')) { "[$_]" } else { $_ } }) -join ',') "
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
            $Query += "FROM [$Table] "
        }

        if ($PSBoundParameters.ContainsKey("Filter")) {
            $Query += " WHERE $(Format-SqlFilterCriteria $Filter $Value)" 
        }

        if ($PSBoundParameters.ContainsKey("Sort")) {
            $Query += "ORDER BY "
            $Query +=($sort |% { if ($_.Contains(' ')) { "[$_]" } else { $_ } } |% { if ($Descending) { "$_ DESC" } else { "$_ ASC" } }) -join ","
        }
        elseif (-not $PSBoundParameters.ContainsKey("Table")) {
            $Query += "ORDER BY 1, 2, 3, 4"
        }

        Write-Verbose $Query

        if ( $NullValues ) {
            Invoke-Sqlcmd -Database $Database -Query $Query `
                |% { $o = $_; Get-Member -InputObject $o -Type Properties |% Name |%{ $o.$_ = [System.DBNull]::Value }; $o} `
                | ConvertTo-Csv | ConvertFrom-Csv
        } else {
            Invoke-Sqlcmd -Database $Database -Query $Query `
                | ConvertTo-Csv | ConvertFrom-Csv
        }

