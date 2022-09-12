
    param(
        [Parameter(Mandatory)]
        [string] 
        $Database,

        [Parameter(Mandatory)]
        [string] 
        $Table,

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
        $Query = "INSERT INTO"

        if ($Table.Contains(".")) {
            $Query += " $Table "   
        }
        else {
            $Query += " [$Table] "
        }

        $Query += "($(($Data.psobject.properties.Name | ForEach-Object { "[$_]" }) -join ","))"
        $Query += " VALUES "
        $Query += "($(($Data.psobject.properties.Name | ForEach-Object { "@$_" }) -join ","))"

        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        foreach ($p in $Data.psobject.properties) {
            if ($null -eq $p.Value) {
                $db_value = [System.DBNull]::Value
            } else {
                $db_value = $p.Value
            }
            $command.Parameters.AddWithValue($p.Name, $db_value) | Out-Null
        }
        $command.ExecuteNonQuery() | Out-Null
        $command.Dispose()

        Write-Verbose $Query
    }
    End {
        $connection.Close()
        $connection.Dispose()
    }

