
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
        if ($Data -is [Hashtable]) {
            $Data = [PSCustomObject]$Data
        }

        $data_types = Invoke-Sqlcmd `
                        -Database $Database `
                        -Query "SELECT column_name, data_type FROM Information_Schema.columns WHERE table_name='$Table' AND NOT data_type IN ('nvarchar','text')"


        
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
            } elseif ( $p.Name -in $data_types.column_name ) {
                if ($p.Value.Length -eq 0) {
                    $db_value = [System.DBNull]::Value
                } else {
                    $sql_data_type = $data_types | Where-Object column_name -eq $p.Name | Select-Object -First 1 | ForEach-Object data_type
                    
                    if ($sql_data_type -eq "datetime") {
                        try {
                            $db_value = [Datetime]::ParseExact($p.Value, "MM/dd/yyyy HH:mm:ss", $null)
                        } catch {
                            $db_value = [Datetime]::Parse($p.Value)
                        }
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
        $command.ExecuteNonQuery() | Out-Null
        $command.Dispose()

        Write-Verbose $Query
    }
    End {
        $connection.Close()
        $connection.Dispose()
    }

