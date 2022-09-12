
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_})]
        [string] 
        $Path
    )

    $FullPath = Resolve-Path $Path
    
    if ((Invoke-SqlCmd -Query "SELECT @@Version AS version").version.Contains(" on Linux"))
    {
        if ($FullPath.Path.ToLower().StartsWith("c:\tau-office_daten\"))
        {
            $FullPath = "/var/opt/mssql/tau-office-daten/" + $FullPath.Path.Substring("c:\tau-office_daten\".Length).Replace('\', '/')
        }
        else
        {
            Copy-Item $FullPath "C:\tau-office_daten\test.bak"
            $FullPath = "/var/opt/mssql/tau-office-daten/test.bak" 
        }
    }

    $data = Invoke-SqlCmd @p -Query "RESTORE HEADERONLY FROM DISK = N'$FullPath' WITH NOUNLOAD;"

    $result = New-Object -TypeName PSCustomObject
    if ($data.SoftwareVersionMajor -eq 10 -and $data.SoftwareVersionMinor -lt 25) {
        $Software = 'SQL Server 2008'
    }
    elseif ($data.SoftwareVersionMajor -eq 10 -and $data.SoftwareVersionMinor -lt 50) {
        $Software = 'SQL Server Azure'
    }
    elseif ($data.SoftwareVersionMajor -eq 10) {
        $Software = 'SQL Server 2008 R2'
    }
    else{
        $Software = @(
            'UNKNOWN',
            'SQL Server 1.0',
            'UNKNOWN',
            'UNKNOWN',
            'SQL Server 4.21',
            'UNKNOWN',
            'SQL Server 6.0',
            'SQL Server 7.0',
            'SQL Server 2000',
            'SQL Server 2005',
            'SQL Server 2008',
            'SQL Server 2012',
            'SQL Server 2014',
            'SQL Server 2016',
            'SQL Server 2017',
            'SQL Server 2019')[$data.SoftwareVersionMajor]
    }

    Add-Member -InputObject $result -MemberType NoteProperty -Name "Software" -Value $Software

    foreach ($p in $data | Get-Member -Type Property) {
        Add-Member -InputObject $result -MemberType NoteProperty -Name $p.Name -Value $data.$($p.Name) 
    }

    Get-ChildItem C:\tau-office_daten\test.bak -ErrorAction SilentlyContinue | Remove-Item -Force

    $result

