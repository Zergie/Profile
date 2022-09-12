
    param(
        [Parameter(Mandatory)]
        [string] 
        $Database,

        [Parameter(Mandatory)]
        [string] 
        $Table,

        [Parameter(ParameterSetName='Filter')]
        [string]
        $Filter,

        [Parameter(ParameterSetName='Filter')]
        [object]
        $Value,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]
        $Data
    )
    Begin {
        $connection_string = "Server=$($credentials.ServerInstance);Database=$Database;User Id=$($credentials.Username);Password=$($credentials.Password);"
        Write-Verbose "connecting to: $connection_string" 
        $connection = [System.Data.SqlClient.SqlConnection]::new($connection_string)
        $connection.Open()
    }
    Process {
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
        }
        
        Write-Verbose $Query

        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        foreach ($p in $Data.psobject.properties | Where-Object Name -ne $Filter) {
            if ($null -eq $p.Value) {
                $db_value = [System.DBNull]::Value
            } else {
                $db_value = $p.Value
            }
            $command.Parameters.AddWithValue($p.Name, $db_value) | Out-Null
        }
        if ($PSBoundParameters.ContainsKey("Filter")) {
            if ($PSBoundParameters.ContainsKey("Value")) {
                $command.Parameters.AddWithValue($Filter, $Value) | Out-Null
            } else {
                $command.Parameters.AddWithValue($Filter, $Data.$Filter) | Out-Null
            }
        }

        $command.ExecuteNonQuery() | Out-Null
        $command.Dispose()
    }
    End {
        $connection.Close()
        $connection.Dispose()
    }

