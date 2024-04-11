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
                Position=0,
                ParameterSetName="AllParameterSet",
                ValueFromPipeline=$false,
                ValueFromPipelineByPropertyName=$false)]
        [switch]
        $All,

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
        [Parameter(Mandatory=$false,
                ParameterSetName="AllParameterSet",
                ValueFromPipeline=$false,
                ValueFromPipelineByPropertyName=$false)]
        [switch]
        $FormatNice,

        [switch]
        $Wait,

        [switch]
        $KeepBrowser
)
begin {
    $rocom_service_employees = @(
        "Wolfgang Puchinger"
    )
}
process {
}
end {
    $dates = {
        if ($rocom -or $rocomservice -or $All) {
            $dat = (Get-Date)
        } else {
            $dat = [datetime]::new($Year, $Month, 1)
        }
        $dat = $dat.AddDays(-$dat.Day + 1)
        [pscustomobject]@{month = $dat.Month; year = $dat.Year}
        $dat = $dat.AddMonths(1)
        [pscustomobject]@{month = $dat.Month; year = $dat.Year}
    } |
    Invoke-Expression

    Start-Process `
        -WindowStyle Minimized `
        -FilePath (Get-ChildItem C:\GIT\QuickAndDirty\bsc\CefSharpDownloader\ -Recurse -Filter CefSharpDownloader.exe |
                        Sort-Object LastWriteTime |
                        Select-Object -Last 1 |
                        ForEach-Object FullName)
    $cefDownloader = Get-Process CefSharpDownloader
    $cefDownloader.WaitForInputIdle() | Out-Null
    try {
        Invoke-WebRequest -Method Post -Uri http://localhost:8888 | Out-Null
        Invoke-WebRequest -Method Post -Uri http://localhost:8888/get -Body "https://rocom.tau-work-together.de" | Out-Null

        $response = [pscustomobject]@{ logout = $true }
        while ($response.logout -eq $true) {
            $response = $dates |
                        ForEach-Object {
                            try {
                                Invoke-WebRequest -Method Post -Uri http://localhost:8888/post -Body (@(
                                    "https://rocom.tau-work-together.de/api/main/holiday/holidaysview/month"
                                    "{`"date`": `"$($_.year)-$($_.month)-1`"}"
                                ) | Join-String -Separator "?")
                            } catch {
                                Invoke-WebRequest -Method Post -Uri http://localhost:8888/post -Body (@(
                                    "https://rocom.tau-work-together.de/api/main/holiday/holidaysview/month"
                                    "{`"date`": `"$($_.year)-$($_.month)-1`"}"
                                ) | Join-String -Separator "?")
                            }
                        } |
                        ForEach-Object {
                            try {
                                $content = $_.Content
                                $_.Content -replace "^.+<pre[^>]+>|</pre>.+",'' | ConvertFrom-Json
                            } catch {
                                Write-Host -ForegroundColor Yellow $content
                                [pscustomobject]@{
                                    logout = $true
                                }
                            }
                        }

            if ($response.logout -eq $true) {
                Invoke-WebRequest -Method Post -Uri http://localhost:8888/get -Body "https://rocom.tau-work-together.de" | Out-Null
                Start-Sleep -Seconds 2
                $password = Get-Content "$PSScriptRoot\..\secrets.json" |
                                ConvertFrom-Json |
                                ForEach-Object Get-TauWorkTogetherHolidays |
                                ForEach-Object Password
                Invoke-WebRequest -Method Post -Uri http://localhost:8888/js -Body "
                    var pwd = document.querySelectorAll('input[type=password]')[0];
                    pwd.dispatchEvent(new Event('compositionstart', { bubbles: true }));
                    pwd.value = '$password';
                    pwd.dispatchEvent(new Event('compositionend', { bubbles: true }));
                    document.querySelectorAll('button')[0].click();
                    " |
                    ForEach-Object Content
                Start-Sleep -Seconds 2
            }
        }

        if (! $KeepBrowser) {
            Invoke-WebRequest -Method Post -Uri http://localhost:8888/quit | Out-Null
        }
    }
    catch {
        $cefDownloader.Kill()
        throw
    }

    $filter = $response.legend |
        Where-Object Name -Match "(Berufschule|Urlaub)" |
        ForEach-Object color |
        Group-Object |
        ForEach-Object Name
    $response = [pscustomobject]@{
        status   = $response.status
        error    = $response.error
        legend   = $response.legend
        holidays = $response.holidays |
            Where-Object backgroundColor -in $filter
    }

    if ($rocom) {
        $response = [pscustomobject]@{
            status   = $response.status
            error    = $response.error
            legend   = $response.legend
            holidays = $response.holidays |
                Where-Object {
                    $_.event -eq $false -or
                    $_.title -NotIn $rocom_service_employees
                }
        }
    } elseif ($rocomservice) {
        $response = [pscustomobject]@{
            status   = $response.status
            error    = $response.error
            legend   = $response.legend
            holidays = $response.holidays |
                Where-Object {
                    $_.event -eq $false -or
                    $_.title -In $rocom_service_employees
                }
        }
    } else {
        $response = [pscustomobject]@{
            status   = $response.status
            error    = $response.error
            legend   = $response.legend
            holidays = $response.holidays
        }
    }

    # get holidays
    $holidays = (Invoke-RestMethod "https://feiertage-api.de/api/?jahr=$((Get-Date).Year)").BY
    $holidays = $holidays |
                    Get-Member -Type NoteProperty |
                    ForEach-Object{
                        [pscustomobject]@{
                            id     = $null
                            title  = $_.name
                            allDay = $true
                            start  = ([datetime]$holidays.($_.name).datum).ToString("yyyy-MM-dd")
                            backgroundColor = $null
                            event = $false
                        }
                    } |
                    Where-Object {
                        $dat = [datetime]$_.start
                        "$($dat.Year)-$($dat.Month)" -IN ($dates | ForEach-Object { "$($_.year)-$($_.month)" })
                    }
    $response.holidays += $holidays

    if ($FormatNice) {
        $end = [datetime]::new($dates[0].year, $dates[0].month, 1)
        $end = $end.AddMonths(1).AddDays(-1).Day + $end.AddMonths(2).AddDays(-1).Day
        $today = (Get-Date).Date

        $holidays = $response.holidays |
            Where-Object { $_.event -eq $false } |
            ForEach-Object { $_.start }

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
                if($_.date.ToString("yyyy-MM-dd") -in $holidays) {
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

                if ($_.date -ge [datetime]::new($dates[0].year, $dates[0].month, 1)) {
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

        $line_no = 0
        foreach ($employee in $employees) {
            $days_off = @()
            $days_off += $response.holidays |
                                Where-Object { $_.title -eq $employee } |
                                ForEach-Object start

            $days = $columns |
                        ForEach-Object { $_.value = if($_.dateString -in $days_off) {"◆"} else {" "}; $_.text } |
                        Join-String -Separator ''

            $c1 = if ($employee -in $rocom_service_employees) { "rgb(121,135,184)" } else { "rgb(190,95,118)" }
            $c2 = if ($employee -in $rocom_service_employees) { "rgb(171,178,211)" } else { "rgb(218,155,167)" }
            $color = if ($line_no % 2 -eq 0) {$c1} else {$c2}
            $color = "`e[38;2;$(
                        $color |
                            Select-String "\d+" -AllMatches |
                            ForEach-Object { $_.Matches.Value } |
                            Join-String -Separator ";"
                        )m"

            $text = "${color}$($employee.PadRight($longest_title.Length)) │ $($days.Replace("`e[0m", $color)) │`e[0m"
            Write-Host $text
            $line_no += 1
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
            Group-Object { "$($_.start): $($_.title)" } |
            ForEach-Object { $_.Group | Select-Object -First 1 } |
            Sort-Object start |
            ForEach-Object {
                Write-Host "$($_.start): $($_.title)"
            } -End { Write-Host "" }

    } else {
        $response
    }

    if ($Wait) {
        Write-Host "Press ANY KEY to exit."
        $host.UI.RawUI.ReadKey() | Out-Null
        $host.UI.RawUI.ReadKey() | Out-Null
    }
}
