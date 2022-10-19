param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ServerInstance,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Username,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Password,

    [Parameter(Mandatory = $true)]
    [string] 
    $Database,

    [Parameter(Mandatory = $true)]
    [string] 
    $Table,

    [Parameter(ParameterSetName='Filter')]
    [string]
    $Filter,

    [Parameter(ParameterSetName='Filter')]
    [object]
    $Value,

    [Parameter(Mandatory = $true,
               ValueFromPipeline = $true)]
    [PSCustomObject]
    $Data
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
        $Data = [PSCustomObject]$Data
    }

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
    if ($PSBoundParameters.ContainsKey("Filter")) {
        if ($PSBoundParameters.ContainsKey("Value")) {
            $command.Parameters.AddWithValue($Filter, $Value) | Out-Null
        } else {
            $command.Parameters.AddWithValue($Filter, $Data.$Filter) | Out-Null
        }
    }

    $command.Parameters | Select ParameterName, Value
    $command.ExecuteNonQuery() | Out-Null
    $command.Dispose()
}
End {
    $connection.Close()
    $connection.Dispose()
}

