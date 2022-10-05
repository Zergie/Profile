[CmdletBinding()]
param (
        [Parameter(Mandatory=$true,
                Position=0,
                ParameterSetName="RocomParameterSet",
                ValueFromPipeline=$false,
                ValueFromPipelineByPropertyName=$false)]
        [switch]
        $rocom,

        [Parameter(Mandatory=$true,
                Position=0,
                ParameterSetName="RocomServiceParameterSet",
                ValueFromPipeline=$false,
                ValueFromPipelineByPropertyName=$false)]
        [switch]
        $rocomservice,

        [Parameter(Mandatory=$true,
                   Position=1,
                   ParameterSetName="DefaultParameterSet",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Month,

        [Parameter(Mandatory=$true,
                   Position=2,
                   ParameterSetName="DefaultParameterSet",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Year,

        [Parameter(Mandatory=$false,
                ParameterSetName="RocomParameterSet",
                ValueFromPipeline=$false,
                ValueFromPipelineByPropertyName=$false)]
        [Parameter(Mandatory=$false,
                ParameterSetName="RocomServiceParameterSet",
                ValueFromPipeline=$false,
                ValueFromPipelineByPropertyName=$false)]
        [Parameter(Mandatory=$false,
                ParameterSetName="DefaultParameterSet",
                ValueFromPipeline=$false,
                ValueFromPipelineByPropertyName=$false)]
        [switch]
        $FormatNice
)
begin {
    $rocom_service_employees = @(
        "Wolfgang Puchinger"
        "Michel Gierich"
    )
}
process {
}
end {
    $dates = {
        if ($rocom -or $rocomservice) {
            $dat = (Get-Date)
            $dat = $dat.AddDays(-$dat.Day + 1)
            [PSCustomObject]@{month = $dat.Month; year = $dat.Year}
            $dat = $dat.AddMonths(1)
            [PSCustomObject]@{month = $dat.Month; year = $dat.Year}
        } else {
            [PSCustomObject]@{month = $Month; year = $Year}
        }
    } | 
    Invoke-Expression

    Start-Process -FilePath (Get-ChildItem C:\GIT\QuickAndDirty\bsc\CefSharpDownloader\ -Recurse -Filter CefSharpDownloader.exe | 
                                    Sort-Object LastWriteTime | 
                                    Select-Object -Last 1 |
                                    ForEach-Object FullName)
    $cefDownloader = Get-Process CefSharpDownloader
    try {    
        Invoke-WebRequest -Method Post -Uri http://localhost:8888 | ForEach-Object Content
        Invoke-WebRequest -Method Post -Uri http://localhost:8888/get -Body "https://rocom.tau-work-together.de" | Out-Null

        $response = [PSCustomObject]@{ logout = $true }
        while ($response.logout -eq $true) {
            $response = $dates |
                        ForEach-Object { 
                            Invoke-WebRequest -Method Post -Uri http://localhost:8888/get -Body ("https://rocom.tau-work-together.de/api/main/holiday/holidaysview/dayGridMonth?" + "{`"date`":`"$($_.year)-$($_.month)-1`"}")
                        } | 
                        ForEach-Object { 
                            $_.Content -replace "^.+<pre[^>]+>|</pre>.+",'' | ConvertFrom-Json  
                        }

            if ($response.logout -eq $true) {
                Invoke-WebRequest -Method Post -Uri http://localhost:8888/get -Body "https://rocom.tau-work-together.de" | Out-Null
                Write-Host "You are logged out. Please login again and press enter." -ForegroundColor Red -NoNewline
                Read-Host 
            }
        }
        
        Invoke-WebRequest -Method Post -Uri http://localhost:8888/quit | ForEach-Object Content 
    }
    catch {
        $cefDownloader.Kill()
        throw
    }
    
    if ($rocom) {
        $response = [PSCustomObject]@{
            status=$response.status
            error=$response.error
            legend=$response.legend
            holidays=$response.holidays |
                Where-Object { 
                    $_.event -eq $false -or
                    $_.title -NotIn $rocom_service_employees
                }
        }
    } elseif ($rocomservice) {
        $response = [PSCustomObject]@{
            status=$response.status
            error=$response.error
            legend=$response.legend
            holidays=$response.holidays |
                Where-Object { 
                    $_.event -eq $false -or
                    $_.title -In $rocom_service_employees
                }
        }
    }

    if ($FormatNice) {
        $end = [datetime]::new($dates[0].year, $dates[0].month, 1)
        $end = $end.AddMonths(1).AddDays(-1).Day + $end.AddMonths(2).AddDays(-1).Day
        $today = (Get-Date).Date

        $holidays = $response.holidays |
            Where-Object { $_.event -eq $false } |
            ForEach-Object { [int]::Parse($_.start.SubString(8)) }
        
        $weekcolor = "`e[48;2;30;30;30m"
        $columns = 1..$end | 
            ForEach-Object {
                [pscustomobject] @{
                    index = $_
                    start = $weekcolor
                    end = "`e[0m"
                    value = " "
                    holiday = $false
                    date = [datetime]::new($dates[0].year, $dates[0].month, 1).AddDays($_ - 1)
                }   
            } |
            ForEach-Object {
                if($_.index -in $holidays) {
                    $_.holiday = $true
                } elseif($_.date.DayOfWeek -eq [System.DayOfWeek]::Saturday) {
                    $_.holiday = $true
                } elseif($_.date.DayOfWeek -eq [System.DayOfWeek]::Sunday) {
                    $_.holiday = $true
                } 
                
                if($_.date.DayOfWeek -eq [System.DayOfWeek]::Monday) {
                    if ($weekcolor -eq "`e[48;2;30;30;30m") {
                        $weekcolor = "`e[48;2;20;20;20m"
                    } else {
                        $weekcolor = "`e[48;2;30;30;30m"
                    }
                    $_.start = $weekcolor
                }
                
                if ($_.date -ge [datetime]::new($dates[1].year, $dates[1].month, 1)) {
                    $_.start = $_.start -replace ";30m", ";45m" -replace ";20m", ";35m"
                }

                if($_.date -eq $today) {
                    $_.start = $_.start -replace ";\d+m", ";160m"
                }
                $_
            } |
            ForEach-Object {
                Add-Member -InputObject $_ -MemberType NoteProperty -Name "DateString" -Value ( $_.date.ToString("yyyy-MM-dd") )
                Add-Member -InputObject $_ -MemberType NoteProperty -Name "MonthName"  -Value ( $_.date.ToString("MMMM").PadLeft(15).PadRight(30) )
                Add-Member -InputObject $_ -MemberType NoteProperty -Name "lines_0"    -Value ( $_.start + $_.MonthName[$_.index % $_.MonthName.Length] + $_.end )
                Add-Member -InputObject $_ -MemberType NoteProperty -Name "lines_1"    -Value ( $_.start + $_.date.Day.ToString().PadLeft(2, ' ').Substring(0,1) + $_.end )
                Add-Member -InputObject $_ -MemberType NoteProperty -Name "lines_2"    -Value ( $_.start + $_.date.Day.ToString().PadLeft(2, ' ').Substring(1,1) + $_.end )
                Add-Member -InputObject $_ -MemberType NoteProperty -Name "lines_3"    -Value ( $_.start + "─" + $_.end )

                Add-Member -InputObject $_ -MemberType ScriptProperty -Name "text"    -Value { 
                    if ($this.holiday) {
                        ($this.start -replace "m",";38;2;60;60;60m" ) + "◆" + $this.end
                    } else {
                        $this.start + $this.value + $this.end
                    } 
                }

                $_
            }

        $longest_title = $response.holidays.title | Sort-Object { $_.Length } | Select-Object -Last 1
        $pad = [string]::new(" ", $longest_title.Length)

        

        
        Write-Host 
        Write-Host "$pad │ $($columns.lines_0 | Join-String -Separator '') │"
        Write-Host "$pad │ $($columns.lines_1 | Join-String -Separator '') │"
        Write-Host "$pad │ $($columns.lines_2 | Join-String -Separator '') │"
        Write-Host "$pad ├─$($columns.lines_3 | Join-String -Separator '')─┤"
        
        $employees = $response.holidays | Where-Object { $_.event -eq $true } | Group-Object title | ForEach-Object Name

        foreach ($employee in $employees) {
            $days_off = @()
            $days_off += $response.holidays |
                                Where-Object { $_.title -eq $employee } |
                                ForEach-Object start

            $days = $columns | 
                        ForEach-Object { $_.value = if($_.dateString -in $days_off) {"◆"} else {" "}; $_.text } | 
                        Join-String -Separator ''
            
            $text = "$($employee.PadRight($longest_title.Length)) │ $days │"
            Write-Host $text 
        }

        if ($employees.Count -gt 5) {
            Write-Host "$pad ├─$($columns.lines_3 | Join-String -Separator '')─┤"
            Write-Host "$pad │ $($columns.lines_2 | Join-String -Separator '') │"
            Write-Host "$pad │ $($columns.lines_1 | Join-String -Separator '') │"
        } else 
        {
            Write-Host "$pad └─$($columns.lines_3 | Join-String -Separator '')─┘"
        }
        Write-Host 

        $employees = $response.holidays |
            Where-Object { $_.event -eq $false } |
            Sort-Object start |
            ForEach-Object {
                Write-Host "$($_.start): $($_.title)"
            } -End { Write-Host "" }

    } else {
        $response
    }
}