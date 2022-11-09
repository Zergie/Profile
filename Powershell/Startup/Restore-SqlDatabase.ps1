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
        docker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak
        docker cp "$((Get-Location).Path)\$db.bak" mssql:/tmp/$db.bak
        Invoke-Sqlcmd "RESTORE DATABASE [$db] FROM DISK='/tmp/$db.bak' WITH REPLACE" -Verbose
        docker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak
    }
}
end {}
