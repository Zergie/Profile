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
        Invoke-Sqlcmd "BACKUP DATABASE [$db] TO DISK='/tmp/$db.bak'" -Verbose
        docker cp mssql:/tmp/$db.bak "$((Get-Location).Path)\$db.bak"
    }
}
end {}
