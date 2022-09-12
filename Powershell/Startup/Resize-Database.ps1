
    param(
        [Parameter(Mandatory=$true)]
        [string] 
        $Database
    )
Begin {}
Process {
    Invoke-SqlCmd -Database master -Query "
    DECLARE @kill varchar(MAX) = '';  
    
    SELECT @kill = @kill + 'kill ' + CONVERT(varchar(5), session_id) + ';' 
    FROM sys.dm_exec_sessions
    WHERE database_id  = db_id('$Database')
    
    EXEC(@kill);" -Debug

    $old_size = (Invoke-Sqlcmd -Database $Database -Query "SELECT sum(size) FROM sys.database_files").Column1 * 8/1024

    $job = Start-Job -ArgumentList $Database,$PSDefaultParameterValues -ScriptBlock {
        param($Database,$dict)
        $PSDefaultParameterValues = $dict

        $mdf = (Invoke-SqlCmd -Database $Database -Query "SELECT name FROM sys.database_files WHERE type_desc = 'ROWS'").name
        $log = (Invoke-SqlCmd -Database $Database -Query "SELECT name FROM sys.database_files WHERE type_desc = 'LOG'").name

        Invoke-Sqlcmd -Database master -Query "ALTER DATABASE [$Database] SET RECOVERY SIMPLE"

        Invoke-Sqlcmd -Database $Database -Query "DBCC SHRINKFILE ([$mdf], 0)" | Out-Null
        Invoke-Sqlcmd -Database $Database -Query "DBCC SHRINKFILE ([$log], 0)" | Out-Null
        
        Invoke-Sqlcmd -Database master -Query "ALTER DATABASE [$Database] SET RECOVERY FULL"
        Invoke-Sqlcmd -Database master -Query "ALTER DATABASE [$Database] MODIFY FILE (Name=$mdf, MAXSIZE=Unlimited)"
        Invoke-Sqlcmd -Database master -Query "ALTER DATABASE [$Database] MODIFY FILE (Name=$log, MAXSIZE=Unlimited)"
    }
    
    While ($job.State -eq "Running") {
        $request = Invoke-Sqlcmd `
                        -Database master `
                        -Query "SELECT TOP 1 command, percent_complete FROM sys.dm_exec_requests WHERE percent_complete > 0"
        if ($null -ne $request) {
            Write-Progress `
                -Activity $request.command `
                -PercentComplete $request.percent_complete
        }
        Start-Sleep -Seconds 1
    }
    Receive-Job $job

    $new_size = (Invoke-Sqlcmd -Database $Database -Query "SELECT sum(size) FROM sys.database_files").Column1 * 8/1024
    return [pscustomobject] @{
        Database = $Database
        OldSize = [int] $old_size
        NewSize = [int] $new_size
    }
}
End {}

