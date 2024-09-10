param(
    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    # [Parameter(ParameterSetName='FilterParameterSet')]
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ServerInstance,

    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    # [Parameter(ParameterSetName='FilterParameterSet')]
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Username,

    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    # [Parameter(ParameterSetName='FilterParameterSet')]
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Password,

    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    # [Parameter(ParameterSetName='FilterParameterSet')]
    [Parameter(Mandatory)]
    [string]
    $Database,

    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    # [Parameter(ParameterSetName='FilterParameterSet')]
    [Parameter(Mandatory, Position=0)]
    [string]
    $Table,

    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    # [Parameter(ParameterSetName='FilterParameterSet')]
    [Parameter(Mandatory,
               ValueFromPipeline = $true)]
    [pscustomobject]
    $Data,

    # [Parameter(ParameterSetName='CriteriaParameterSet')]
    [string]
    $Criteria,

    # [Parameter(ParameterSetName='FilterParameterSet')]
    [string]
    $Filter,

    # [Parameter(ParameterSetName='FilterParameterSet')]
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
    if ($Data -is [Hashtable]) {
        $Data = [pscustomobject]$Data
    }
    Write-Verbose "data: $($data | ConvertTo-Json -Compress)"

    $data_types = Invoke-Sqlcmd `
                    -Database $Database `
                    -Query "SELECT column_name, data_type FROM Information_Schema.columns WHERE table_name='$Table' AND NOT data_type IN ('nvarchar','text')"



    $Query = "UPDATE "

    if ($Table.Contains(".")) {
        $Query += " $Table "
    }
    else {
        $Query += " [$Table] "
    }

    $Query += " SET "
    $Query += ($Data.psobject.properties | Where-Object Name -ne $Filter | ForEach-Object {"[$($_.Name)]=@$($_.Name)"} ) -join ","

    if ($PSBoundParameters.ContainsKey("Filter")) {
        $Query += " WHERE [$Filter] = @$Filter"
    } elseif ($Criteria.Length -gt 0) {
        $Query += " WHERE $Criteria"
    }

    Write-Verbose $Query

    $command = $connection.CreateCommand()
    $command.CommandText = $Query
    foreach ($p in $Data.psobject.properties | Where-Object Name -ne $Filter) {
        if ($null -eq $p.Value) {
            $db_value = [System.DBNull]::Value
        } elseif ( $p.Name -in $data_types.column_name ) {
            if ($p.Value.Length -eq 0) {
                $db_value = [System.DBNull]::Value
            } else {
                $sql_data_type = $data_types | Where-Object column_name -eq $p.Name | Select-Object -First 1 | ForEach-Object data_type

                if ($sql_data_type -eq "datetime") {
                    $db_value = $(switch -regex ($p.value) {
                        "\d+\.\d+\.\d+ \d+:\d+:\d+$" { [datetime]::parseexact($p.value, "dd.MM.yyyy hh:mm:ss", $null) }
                        "\d+\.\d+\.\d+ \d+:\d+$"     { [datetime]::parseexact($p.value, "dd.MM.yyyy hh:mm", $null) }
                        "\d+\.\d+\.\d+$"             { [datetime]::parseexact($p.value, "dd.MM.yyyy", $null) }
                        "\d+/\d+/\d+ \d+:\d+:\d+$"   { [datetime]::parseexact($p.value, "MM/dd/yyyy hh:mm:ss", $null) }
                        "\d+/\d+/\d+$"               { [datetime]::parseexact($p.value, "MM/dd/yyyy", $null) }
                        default                      { [datetime]::parse($p.value) }
                    })
                } else {
                    $db_value = $p.Value
                }
            }
        } else {
            $db_value = $p.Value
        }
        Write-Verbose "$($p.Name): $db_value"
        $command.Parameters.AddWithValue($p.Name, $db_value) | Out-Null
    }
    if ($PSBoundParameters.ContainsKey("Filter")) {
        if ($PSBoundParameters.ContainsKey("Value")) {
            $command.Parameters.AddWithValue($Filter, $Value) | Out-Null
        } else {
            $command.Parameters.AddWithValue($Filter, $Data.$Filter) | Out-Null
        }
    }

    #$command.Parameters | Select-Object ParameterName, Value
    $command.ExecuteNonQuery() | Out-Null
    $command.Dispose()
}
End {
    $connection.Close()
    $connection.Dispose()
}
