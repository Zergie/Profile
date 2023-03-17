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
        Write-Host -ForegroundColor Cyan "docker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak"
        docker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak

        Write-Host -ForegroundColor Cyan "BACKUP DATABASE [$db] TO DISK='/tmp/$db.bak'" -Verbose
        Invoke-Sqlcmd "BACKUP DATABASE [$db] TO DISK='/tmp/$db.bak'" -Verbose

        Write-Host -ForegroundColor Cyan "docker cp mssql:/tmp/$db.bak `"$docker((Get-Location).Path)\$db.bak`""
        docker cp mssql:/tmp/$db.bak "$((Get-Location).Path)\$db.bak"
    }
}
end {}
