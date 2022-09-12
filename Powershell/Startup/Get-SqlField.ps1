
    param(
        [Parameter(Mandatory)]
        [string] 
        $Database,

        [string] 
        $Table,

        [ValidateSet("TABLE_CATALOG", "TABLE_SCHEMA", "TABLE_NAME", "COLUMN_NAME", "ORDINAL_POSITION", "COLUMN_DEFAULT", "IS_NULLABLE", "DATA_TYPE", "CHARACTER_MAXIMUM_LENGTH", "CHARACTER_OCTET_LENGTH", "NUMERIC_PRECISION", "NUMERIC_PRECISION_RADIX", "NUMERIC_SCALE", "DATETIME_PRECISION", "CHARACTER_SET_CATALOG", "CHARACTER_SET_SCHEMA", "CHARACTER_SET_NAME", "COLLATION_CATALOG", "COLLATION_SCHEMA", "COLLATION_NAME", "DOMAIN_CATALOG", "DOMAIN_SCHEMA", "DOMAIN_NAME")]
        [string[]] 
        $Sort,

        [switch] 
        $Descending,

        [ValidateSet("TABLE_CATALOG", "TABLE_SCHEMA", "TABLE_NAME", "COLUMN_NAME", "ORDINAL_POSITION", "COLUMN_DEFAULT", "IS_NULLABLE", "DATA_TYPE", "CHARACTER_MAXIMUM_LENGTH", "CHARACTER_OCTET_LENGTH", "NUMERIC_PRECISION", "NUMERIC_PRECISION_RADIX", "NUMERIC_SCALE", "DATETIME_PRECISION", "CHARACTER_SET_CATALOG", "CHARACTER_SET_SCHEMA", "CHARACTER_SET_NAME", "COLLATION_CATALOG", "COLLATION_SCHEMA", "COLLATION_NAME", "DOMAIN_CATALOG", "DOMAIN_SCHEMA", "DOMAIN_NAME")]
        [string[]] 
        $Fields
    )

    $Query = "SELECT "

    if ($PSBoundParameters.ContainsKey("Fields")) {
        $Query += $Fields -join ","
    } else {
        $Query += ("TABLE_NAME", "COLUMN_NAME", "ORDINAL_POSITION", "COLUMN_DEFAULT", "IS_NULLABLE", "DATA_TYPE", "CHARACTER_MAXIMUM_LENGTH", "CHARACTER_OCTET_LENGTH", "NUMERIC_PRECISION", "NUMERIC_PRECISION_RADIX", "NUMERIC_SCALE", "DATETIME_PRECISION", "CHARACTER_SET_CATALOG", "CHARACTER_SET_SCHEMA", "CHARACTER_SET_NAME", "COLLATION_CATALOG", "COLLATION_SCHEMA", "COLLATION_NAME", "DOMAIN_CATALOG", "DOMAIN_SCHEMA", "DOMAIN_NAME") -join ","
    }

    $Query += " FROM Information_Schema.columns"

    if ($PSBoundParameters.ContainsKey("Table")) {
        $Query += " WHERE TABLE_NAME like '$Table'"
    }

    if ($PSBoundParameters.ContainsKey("Sort")) {
        $Query += " ORDER BY "
        $Query +=($sort |% { if ($_.Contains(' ')) { "[$_]" } else { $_ } } |% { if ($Descending) { "$_ DESC" } else { "$_ ASC" } }) -join ","
    } elseif ($PSBoundParameters.ContainsKey("Fields")) {
        $Query += " ORDER BY "
        $Query +=($Fields |% { if ($_.Contains(' ')) { "[$_]" } else { $_ } } |% { if ($Descending) { "$_ DESC" } else { "$_ ASC" } }) -join ","
    }

    Write-Verbose $Query
    Invoke-Sqlcmd -Database $Database -Query $Query | ConvertTo-Csv | ConvertFrom-Csv

