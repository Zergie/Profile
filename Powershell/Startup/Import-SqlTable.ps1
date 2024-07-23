param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ServerInstance,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Username,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Password,

    [Parameter(Mandatory)]
    [string]
    $Database,

    [Parameter(Mandatory, Position=0, ValueFromPipelineByPropertyName)]
    [Alias("::Table")]
    [string]
    $Table,

    [string[]]
    $ExcludeProperty,

    [Parameter(Mandatory, ValueFromPipeline)]
    [pscustomobject]
    $Data,

    [Parameter()]
    [switch]
    $PassThru
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
    $PassThruData = $Data
    $Data = $Data |
                ForEach-Object psadapted -PipelineVariable item |
                Get-Member -MemberType Property |
                Where-Object Name -NotLike "::*" |
                Where-Object Name -NotIn $ExcludeProperty |
                ForEach-Object {
                    [pscustomobject]@{
                        Name = $_.Name
                        Value = $item.($_.Name)
                    }
                }
    $Table = $Table.TrimStart("[").TrimEnd("]")
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

    $Query += "($(($Data.Name | ForEach-Object { "[$_]" }) -join ","))"
    $Query += " VALUES "
    $Query += "($(($Data.Name | ForEach-Object { "@$_" }) -join ","))"

    $command = $connection.CreateCommand()
    $command.CommandText = $Query
    foreach ($p in $Data) {
        if ($null -eq $p.Value) {
            $db_value = [System.DBNull]::Value
        } elseif ( $p.Name -in $data_types.column_name ) {
            if ($p.Value.Length -eq 0) {
                $db_value = [System.DBNull]::Value
            } else {
                $sql_data_type = $data_types | Where-Object column_name -eq $p.Name | Select-Object -First 1 | ForEach-Object data_type

                if ($sql_data_type -eq "datetime") {
                    if ($p.Value.Length -lt 5) {
                        $db_value = [System.DBNull]::Value
                    } else {
                        $db_value = $(switch -Regex ($p.Value) {
                            "\d+\.\d+\.\d+ \d+:\d+:\d+$" { [Datetime]::ParseExact($p.Value, "dd.MM.yyyy HH:mm:ss", $null) }
                            "\d+\.\d+\.\d+ \d+:\d+$"     { [Datetime]::ParseExact($p.Value, "dd.MM.yyyy HH:mm", $null) }
                            "\d+\.\d+\.\d+$"             { [Datetime]::ParseExact($p.Value, "dd.MM.yyyy", $null) }
                            "\d+/\d+/\d+ \d+:\d+:\d+$"   { [Datetime]::ParseExact($p.Value, "MM/dd/yyyy HH:mm:ss", $null) }
                            "\d+/\d+/\d+$"               { [Datetime]::ParseExact($p.Value, "MM/dd/yyyy", $null) }
                            default                      { [Datetime]::Parse($p.Value) }
                        })
                    }
                } else {
                    $db_value = $p.Value
                }
            }
        } else {
            $db_value = $p.Value
        }

        Write-Verbose "$($p.Name): $(if ($db_value -eq [System.DBNull]::Value) {"`e[3m__null__`e[0m"} else {$db_value})"
        $command.Parameters.AddWithValue($p.Name, $db_value) | Out-Null
    }
    # try {
        $command.ExecuteNonQuery() | Out-Null
    # } catch {
    #     if ($Table.Contains(".")) {
    #         $command.CommandText = "SET IDENTITY_INSERT $TABLE ON; $Query;SET IDENTITY_INSERT $TABLE OFF"
    #     }
    #     else {
    #         $command.CommandText = "SET IDENTITY_INSERT [$TABLE] ON; $Query;SET IDENTITY_INSERT [$TABLE] OFF"
    #     }
    #     $command.ExecuteNonQuery() | Out-Null
    # }
    $command.Dispose()

    Write-Verbose $Query

    if ($PassThru) {
        $PassThruData |
            Select-Object -ExcludeProperty "::Table"
    }
}
End {
    $connection.Close()
    $connection.Dispose()
}
