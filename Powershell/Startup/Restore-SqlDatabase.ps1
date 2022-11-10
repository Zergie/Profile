[CmdletBinding()]
param(
    [Parameter(Mandatory=$false,
               Position=0,
               ParameterSetName="ParameterSetName")]
    [string[]]
    $Database
)
begin {
}
process {
    foreach ($db in $Database) {
        Invoke-Sqlcmd -Database master -Query "SELECT * FROM sys.dm_exec_sessions WHERE database_id = db_id('$db')" |
        ForEach-Object {
            Write-Host "killing session $($_.session_id)"
            try {
                Invoke-Sqlcmd -Database master -Query "kill $($_.session_id)"
            } catch {
            }
        }
    }

    foreach ($db in $Database) {
        docker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak
        docker cp "$((Get-Location).Path)\$db.bak" mssql:/tmp/$db.bak
        Invoke-Sqlcmd -Database master -Query "RESTORE DATABASE [$db] FROM DISK='/tmp/$db.bak' WITH REPLACE" -Verbose
        docker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak
    }
}
end {}
