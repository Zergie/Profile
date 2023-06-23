[CmdletBinding()]
param(
    [Parameter(Mandatory=$false,
               Position=0,
               ParameterSetName="ParameterSetName")]
    [string[]]
    $Database
)
begin {
    $dockerScript = "D:\Daten\docker.ps1"
    $credentials =  Get-Content -raw $dockerScript |
                        Select-String -Pattern "\n\s*\`$Global:credentials = (@\{[^}]+})" -AllMatches |
                        ForEach-Object Matches |
                        Select-Object -Last 1 |
                        ForEach-Object { $_.Groups[1].Value } |
                        Invoke-Expression
}
process {
    function exec {
        param(
            [string]
            $Query
        )
        #Write-Host -ForegroundColor Cyan "`n$Query"
        Invoke-Sqlcmd "$Query" -Verbose
    }

    foreach ($db in $Database) {
        exec "USE [$db]"
        $mdf = (exec "SELECT name FROM sys.database_files WHERE type_desc = 'ROWS'").name
        $log = (exec "SELECT name FROM sys.database_files WHERE type_desc = 'LOG'").name
        exec "USE master"

        exec "ALTER DATABASE [$db] SET RECOVERY SIMPLE" | Out-Null
        exec "DBCC SHRINKDATABASE ([$db], 0)" | Out-Null
        exec "DBCC SHRINKFILE ([$mdf], 0)" | Out-Null
        exec "DBCC SHRINKFILE ([$log], 0)" | Out-Null

        #exec "USE master"
        exec "ALTER DATABASE [$db] SET RECOVERY FULL" | Out-Null
        exec "ALTER DATABASE [$db] MODIFY FILE (Name=$mdf, MAXSIZE=Unlimited)" | Out-Null
        exec "ALTER DATABASE [$db] MODIFY FILE (Name=$log, MAXSIZE=Unlimited)" | Out-Null

        if (! $credentials.IsInstalledOnHost) {
            Write-Host -ForegroundColor Cyan "`ndocker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak"
            docker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak

            exec "BACKUP DATABASE [$db] TO DISK='/tmp/$db.bak'"

            Write-Host -ForegroundColor Cyan "`ndocker cp mssql:/tmp/$db.bak `"$docker((Get-Location).Path)\$db.bak`""
            docker cp mssql:/tmp/$db.bak "$((Get-Location).Path)\$db.bak"
        } else {
            Write-Host -ForegroundColor Cyan "Remove-Item `"C:\temp\db.bak`" -Force -ErrorAction SilentlyContinue"
            Remove-Item "C:\temp\db.bak" -Force -ErrorAction SilentlyContinue

            exec "BACKUP DATABASE [$db] TO DISK='C:\temp\db.bak'" -Verbose

            Write-Host -ForegroundColor Cyan "`nCopy-Item C:\temp\db.bak `"$((Get-Location).Path)\$db.bak`""
            Copy-Item C:\temp\db.bak "$((Get-Location).Path)\$db.bak"
        }
    }
}
end {}
