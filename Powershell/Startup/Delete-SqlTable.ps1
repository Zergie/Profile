param(
    # [Parameter(ParameterSetName='BasicParameterSet')]
    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    # [Parameter(ParameterSetName='FilterParameterSet')]
    [ValidateNotNullOrEmpty()]
    [string]
    $ServerInstance,

    # [Parameter(ParameterSetName='BasicParameterSet')]
    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    # [Parameter(ParameterSetName='FilterParameterSet')]
    [ValidateNotNullOrEmpty()]
    [string]
    $Username,

    # [Parameter(ParameterSetName='BasicParameterSet')]
    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    # [Parameter(ParameterSetName='FilterParameterSet')]
    [ValidateNotNullOrEmpty()]
    [string]
    $Password,

    # [Parameter(ParameterSetName='BasicParameterSet')]
    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    # [Parameter(ParameterSetName='FilterParameterSet')]
    [string]
    $Database,

    # [Parameter(Position=0, ParameterSetName='BasicParameterSet')]
    # [Parameter(Position=0, ParameterSetName='CriteriaParameterSet')]
    # [Parameter(Position=0, ParameterSetName='FilterParameterSet')]
    [Parameter(Position=0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string]
    $Table,

    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    [string]
    $Criteria,

    # [Parameter(ParameterSetName='FilterParameterSet')]
    [Parameter(Position=1)]
    [string[]]
    $Filter,

    # [Parameter(ParameterSetName='FilterParameterSet')]
    [Parameter(Position=2, ValueFromPipeline)]
    [object]
    $Value
)
Begin {
    $connection_string = @(
            "Server=$ServerInstance"
            "Database=$Database"
            "User Id=$Username"
            "Password=$Password"
        ) | Join-String -Separator ";"
    Write-Verbose "connecting to: $connection_string"
    $connection = [System.Data.SqlClient.SqlConnection]::new($connection_string)
    $connection.Open()
}
Process {
    if ($PSBoundParameters.ContainsKey("Filter")) {
        $Query = "DELETE FROM"
    } elseif ($Criteria.Length -gt 0) {
        $Query = "DELETE FROM"
    } else {
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
    } elseif ($Criteria.Length -gt 0) {
        $Query += "WHERE $Criteria"
    }

    Write-Verbose $Query

    $command = $connection.CreateCommand()
    $command.CommandText = $Query
    $command.ExecuteNonQuery() | Out-Null
    $command.Dispose()
}
End {
    $connection.Close()
    $connection.Dispose()
}
