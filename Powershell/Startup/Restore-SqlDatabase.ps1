[CmdletBinding()]
param(
    [Parameter(Mandatory=$false,
               Position=0,
               ParameterSetName="ParameterSetName")]
    [string[]]
    $Database
)
begin {
    $dockerScript = "C:\Dokumente\Daten\docker.ps1"
    $credentials =  Get-Content -raw $dockerScript |
                        Select-String -Pattern "\n\s*\`$Global:credentials = (@\{[^}]+})" -AllMatches |
                        ForEach-Object Matches |
                        Select-Object -Last 1 |
                        ForEach-Object { $_.Groups[1].Value } |
                        Invoke-Expression
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
        if (! $credentials.IsInstalledOnHost) {
            Write-Host -ForegroundColor Cyan "`ndocker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak"
            docker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak

            Write-Host -ForegroundColor Cyan "`ndocker cp `"$((Get-Location).Path)\$db.bak`" mssql:/tmp/$db.bak"
            docker cp "$((Get-Location).Path)\$db.bak" mssql:/tmp/$db.bak

            Write-Host -ForegroundColor Cyan "`nRESTORE DATABASE [$db] FROM DISK='/tmp/$db.bak' WITH REPLACE"
            Invoke-Sqlcmd -Database master -Query "RESTORE DATABASE [$db] FROM DISK='/tmp/$db.bak' WITH REPLACE" -Verbose

            Write-Host -ForegroundColor Cyan "`ndocker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak"
            docker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak
        } else {
            Write-Host -ForegroundColor Cyan "`nCopy-Item `"$((Get-Location).Path)\$db.bak`" C:\temp\db.bak"
            Copy-Item "$((Get-Location).Path)\$db.bak" C:\temp\db.bak

            Write-Host -ForegroundColor Cyan "`nRESTORE DATABASE [$db] FROM DISK='C:\temp\db.bak' WITH REPLACE"
            Invoke-Sqlcmd -Database master -Query "RESTORE DATABASE [$db] FROM DISK='C:\temp\db.bak' WITH REPLACE" -Verbose
        }
    }
}
end {}
