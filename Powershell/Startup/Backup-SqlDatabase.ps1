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
    function exec {
        param(
            [string]
            $Query
        )
        #Write-Host -ForegroundColor Cyan "`n$Query"
        Invoke-Sqlcmd "$Query" -Verbose
    }


    foreach ($db in $Database) {
        $mdf = (exec "USE [$db]; SELECT name FROM sys.database_files WHERE type_desc = 'ROWS'").name
        $log = (exec "USE [$db]; SELECT name FROM sys.database_files WHERE type_desc = 'LOG'").name
        exec "USE master"
        $mdf

        exec "USE master; ALTER DATABASE [$db] SET RECOVERY SIMPLE" | Out-Null
        exec "USE [$db]; DBCC SHRINKDATABASE ([$db], 0)" | Out-Null
        exec "USE [$db]; DBCC SHRINKFILE ([$mdf], 0)" | Out-Null
        exec "USE [$db]; DBCC SHRINKFILE ([$log], 0)" | Out-Null

        #exec "USE master"
        exec "USE master; ALTER DATABASE [$db] SET RECOVERY FULL" | Out-Null
        exec "USE master; ALTER DATABASE [$db] MODIFY FILE (Name=N'$mdf', MAXSIZE=Unlimited)" | Out-Null
        exec "USE master; ALTER DATABASE [$db] MODIFY FILE (Name=N'$log', MAXSIZE=Unlimited)" | Out-Null

        if ($credentials.IsInstalledOnHost) {
            Write-Host -ForegroundColor Cyan "Remove-Item `"C:\temp\db.bak`" -Force -ErrorAction SilentlyContinue"
            Remove-Item "C:\temp\db.bak" -Force -ErrorAction SilentlyContinue

            exec "USE master; BACKUP DATABASE [$db] TO DISK='C:\temp\db.bak' WITH INIT"

            Write-Host -ForegroundColor Cyan "`nCopy-Item C:\temp\db.bak `"$((Get-Location).Path)\$db.bak`""
            Copy-Item C:\temp\db.bak "$((Get-Location).Path)\$db.bak"
        } else {
            Write-Host -ForegroundColor Cyan "`ndocker exec -t uname -a"
            docker exec -t mssql uname -a >nul
            Write-Host $(if ($LASTEXITCODE -eq 0) {"ok"} else {"failed"})

            if ($LASTEXITCODE -eq 0) {
                Write-Host -ForegroundColor Cyan "`ndocker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak"
                docker exec -t  --privileged --user root mssql rm -f /tmp/$db.bak

                exec "USE master; BACKUP DATABASE [$db] TO DISK='/tmp/$db.bak' WITH INIT"

                Write-Host -ForegroundColor Cyan "`ndocker cp mssql:/tmp/$db.bak `"$docker((Get-Location).Path)\$db.bak`""
                docker cp mssql:/tmp/$db.bak "$((Get-Location).Path)\$db.bak"
            } else {
                $IsHypervContainer = $true
                Write-Host -ForegroundColor Cyan "`ndocker exec -t cmd /c del C:\$db.bak"
                docker exec -t mssql cmd /c del C:\temp\*.bak >nul
                Write-Host $(if ($LASTEXITCODE -eq 0) {"ok"} else {"failed"})

                exec "USE master; BACKUP DATABASE [$db] TO DISK='C:\$db.bak' WITH INIT"
            }
        }
    }
}
end {
    if ($IsHypervContainer) {
        Write-Host -ForegroundColor Cyan "`ndocker stop mssql"
        docker stop mssql >nul
        Write-Host $(if ($LASTEXITCODE -eq 0) {"ok"} else {"failed"})

        foreach ($db in $Database) {
            Write-Host -ForegroundColor Cyan "`ndocker cp `"mssql:/$db.bak`" `"$docker((Get-Location).Path)\$db.bak`""
            docker cp "mssql:/$db.bak" "$((Get-Location).Path)\$db.bak"
        }

        Write-Host -ForegroundColor Cyan "`ndocker start mssql"
        docker start mssql >nul
        Write-Host $(if ($LASTEXITCODE -eq 0) {"ok"} else {"failed"})
    }
}
