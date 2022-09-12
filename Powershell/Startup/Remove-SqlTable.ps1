
    param(
        [Parameter(Mandatory)]
        [string]
        $Database,

        [Parameter(Mandatory)]
        $Table,

        [Parameter(ParameterSetName='Filter')]
        [string]
        $Filter,

        [Parameter(ParameterSetName='Filter')]
        [object]
        $Value
    )
        if ($PSBoundParameters.ContainsKey("Filter")) {
            $Query = "DELETE FROM "
        }
        else {
            $Query = "TRUNCATE TABLE"
        }

        if ($Table.Contains(".")) {
            $Query += " $Table "   
        }
        else {
            $Query += " [$Table] "
        }

        if ($PSBoundParameters.ContainsKey("Filter")) {
            $Query += " WHERE $(Format-SqlFilterCriteria $Filter $Value)" 
        }

        Write-Verbose $Query
        Invoke-Sqlcmd -Database $Database -Query $Query

