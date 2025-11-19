[cmdletbinding()]
param (
        [Parameter(Mandatory=$false,
                   Position=1,
                   ParameterSetName="DefaultParameterSet",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [int[]]
        $Days = @(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31),

        [Parameter(Mandatory=$true,
                   Position=2,
                   ParameterSetName="DefaultParameterSet",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [int]
        $Month,

        [Parameter(Mandatory=$true,
                   Position=3,
                   ParameterSetName="DefaultParameterSet",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [int]
        $Year,

        [Parameter(Mandatory=$false,
                   Position=4,
                   ParameterSetName="DefaultParameterSet",
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [string]
        $Path = "C:\Dokumente\Dokumente\Tätigkeitsnachweis.xlsx",

        [Parameter(Mandatory=$false,
                   ParameterSetName="DefaultParameterSet",
                   ValueFromPipeline=$false,
                   ValueFromPipelineByPropertyName=$false)]
        [ValidateNotNullOrEmpty()]
        [switch]
        $OverviewOnly,

        [Parameter(Mandatory=$false,
                   ParameterSetName="DefaultParameterSet",
                   ValueFromPipeline=$false,
                   ValueFromPipelineByPropertyName=$false)]
        [ValidateNotNullOrEmpty()]
        [switch]
        $Force
)
begin {
    Set-Alias "Get-LocationHistory" "$PSScriptRoot\Get-LocationHistory.ps1"
    Set-Alias "Invoke-CefDownloader" "$PSScriptRoot\Invoke-CefDownloader.ps1"

    function Add-Day {
        param (
            [Parameter(Mandatory=$true, Position=1)]
            [int]
            $Day,

            [Parameter(Mandatory=$true, Position=2)]
            [int]
            $Month,

            [Parameter(Mandatory=$true, Position=3)]
            [int]
            $Year
        )
        Write-Host "adding $Day.$Month.$Year as workday"

        Invoke-WebRequest -Method Post -Uri http://localhost:8888/get -Body "https://rocom.tau-work-together.de/worktime/month/$Month/$Year/21" | Out-Null
        Start-Sleep -Milliseconds 500

        Invoke-WebRequest -Method Post -Uri http://localhost:8888/js -Body "document.querySelectorAll('a.btn')[0].click()" | Out-Null
        Start-Sleep -Milliseconds 500

        Invoke-WebRequest -Method Post -Uri http://localhost:8888/js -Body "
            var input = document.querySelectorAll('input.form-control.datepicker')[0];
            input.dispatchEvent(new Event('compositionstart', { bubbles: true }));
            input.value = '$($Day.ToString("00")).$($Month.ToString("00")).$($Year.ToString("0000"))';
            input.dispatchEvent(new Event('change', { bubbles: true }));
            input.dispatchEvent(new Event('compositionend', { bubbles: true }));
            Array.from(document.querySelectorAll('button.btn-primary')).find(el => el.textContent === 'Arbeitstag speichern').click()
            " |
            Out-Null
        Start-Sleep -Milliseconds 500
    }
}
process {
}
end {
    # get worktimes from 'Tätigkeitsnachweis'
    try {
        $pkgobj = New-Object -TypeName OfficeOpenXml.ExcelPackage -ArgumentList 'C:\Dokumente\Dokumente\Tätigkeitsnachweis.xlsx'
    } catch {
        Install-Module ImportExcel
        Import-Module ImportExcel
        $pkgobj = New-Object -TypeName OfficeOpenXml.ExcelPackage -ArgumentList 'C:\Dokumente\Dokumente\Tätigkeitsnachweis.xlsx'
    }
    $columns = $null
    $WorkTimes = $pkgobj.Workbook.Worksheets["Arbeitszeiten"].Cells |
        Where-Object { $_.Start.Row -ge 3 } |
        Group-Object { $_.Start.Row } |
        ForEach-Object {
            if ($_.Name -eq "3" -and $null -eq $columns) {
                $columns = $_.Group | ForEach-Object { $_.Value.ToString() }
            } else {
                $i = 0
                $obj = @{}
                $_.Group |
                    ForEach-Object {
                        $value = $(if ($null -eq $_.Value) { "" } else { $_.Value })
                        
                        if ($null -ne $columns[$i]) {
                            $obj.Add($columns[$i], $value)
                        }
                        $i += 1
                    }
                $entry = [pscustomobject]$obj
                if ($entry.start -eq "" -and $entry.end -eq "") {
                    Write-Debug "Warning: empty row found at $($entry.date)"
                } else {
                    $entry
                }
           }
        } |
        Where-Object { $_.date.Month -eq $Month } |
        Where-Object { $null -ne $_.start }
    $pkgobj.Dispose()
    Remove-Variable pkgobj, columns

    # add location to worktimes
    $locations = @{}
    Get-LocationHistory |
        Where-Object { $_.date.Year -eq $Year } |
        Where-Object { $_.date.Month -eq $Month } |
        Where-Object org -NotLike "KOMRO *" |
        ForEach-Object { $locations[$_.date.date] = "Büro" }
    $WorkTimes |
        ForEach-Object {
            if ($locations.ContainsKey($_.date.date)) {
                $_ | Add-Member NoteProperty Location $locations[$_.date.date]
            } else {
                $_ | Add-Member NoteProperty Location "Homeoffice"
            }
        }
    Remove-Variable locations

    # remove weekends only
    $Days = $Days | Where-Object { $_ -in $WorkTimes.date.Day }
    if (($Days | Measure-Object).Count -lt 10) {
        if (! $PSBoundParameters.ContainsKey("Days") -and ! $Force) {
            throw "Less than 10 workdays found: $($Days | ConvertTo-Json -Compress)"
        }
    }

    # remove holidays
    $data = (Invoke-RestMethod 'https://feiertage-api.de/api/?jahr=$Year').BY
    $holidays = $data |
        Get-Member -MemberType NoteProperty |
        Where-Object Name -NotLike "Augsburger *" |
        ForEach-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                name = $_
                date = [datetime]::ParseExact($data.$_.datum, "yyyy-MM-dd", $null)
            }
        } |
        Where-Object { $_.date.Month -eq $Month }

    $Days = $Days | Where-Object { $_ -notin $holidays.date.Day }
    Remove-Variable holidays, data

    # open browser
    Write-Host "open new browser .."
    . "$PSScriptRoot/Get-TauWorkTogetherHolidays.ps1" -Year $Year -Month $Month -KeepBrowser |
        Out-Null # reuse login logic

    try {
        if (! $OverviewOnly) {
            # get the current browser state
            Invoke-CefDownloader

            # find days that needs to be created and create them
            Invoke-CefDownloader -Action Get -Body "https://rocom.tau-work-together.de/worktime/month/$Month/$Year/21" | Out-Null
            Start-Sleep -Milliseconds 500
            $Days |
                Where-Object { $_ -notin (
                                            Invoke-CefDownloader -Action Content |
                                                ForEach-Object Content |
                                                Select-String -Pattern "\d{2}\.\d{2}\.$Year" -AllMatches |
                                                ForEach-Object Matches |
                                                ForEach-Object Value |
                                                ForEach-Object { [datetime]::ParseExact($_, "dd.MM.yyyy", $null) } |
                                                Where-Object Month -eq $Month |
                                                ForEach-Object Day
                                         )
                } |
                ForEach-Object {
                    $Day = $_
                    $date = [datetime]::new($Year, $Month, $Day)

                    Add-Day $Day $Month $Year

                    $WorkTimes |
                        Where-Object { $_.date -eq $date } |
                        ForEach-Object {
                            if ($_.duration -gt 6) {
                                $mid = $_.start.Date.AddHours(12).AddMinutes((Get-Random -Minimum -5 -Maximum 60))
                                [pscustomobject] @{
                                    date = $_.date
                                    start = $_.start
                                    end = $mid
                                    location = $_.Location
                                }
                                [pscustomobject] @{
                                    date = $_.date
                                    start = $mid.AddMinutes((Get-Random -Minimum 30 -Maximum 35))
                                    end = $_.end
                                    location = $_.Location
                                }
                            } else {
                                $_
                            }
                        } |
                        ForEach-Object {
                            Write-Host "add workhours ($($_.start.ToString("HH:mm")) - $($_.end.ToString("HH:mm")))"

                            Start-Sleep -Milliseconds 500
                            Invoke-CefDownloader -Action Js `
                                -Body "Array.from(document.querySelectorAll('.btn')).find(el => el.textContent === 'Arbeitszeit erfassen ').click()" | Out-Null

                            Start-Sleep -Milliseconds 500
                            Invoke-CefDownloader -Action Js -Body "
                                var startTime = document.querySelectorAll('input[type=time]')[0]
                                startTime.value = '$($_.start.ToString("HH:mm"))';
                                startTime.dispatchEvent(new Event('change', { bubbles: true }));
                                startTime.dispatchEvent(new Event('input', { bubbles: true }));

                                var endTime = document.querySelectorAll('input[type=time]')[1]
                                endTime.dispatchEvent(new Event('compositionstart', { bubbles: true }));
                                endTime.value = '$($_.end.ToString("HH:mm"))';
                                endTime.dispatchEvent(new Event('change', { bubbles: true }));
                                endTime.dispatchEvent(new Event('input', { bubbles: true }));

                                var workType = document.querySelectorAll('select.form-control')[1];
                                Array.from(workType.options).find(el => el.textContent === '$($_.location)').selected = true
                                workType.dispatchEvent(new Event('change', { bubbles: true }));
                                workType.dispatchEvent(new Event('selectionchange', { bubbles: true }));
                            " | Out-Null

                            Start-Sleep -Milliseconds 500
                            Invoke-CefDownloader -Action Js -Body "
                                Array.from(document.querySelectorAll('button')).find(el => el.textContent === 'Speichern').click()
                            " | Out-Null
                        }
                }
        }

        # create overview for user
        Invoke-CefDownloader -Action Get `
            -Body "https://rocom.tau-work-together.de/worktime/month/$Month/$Year/21" | Out-Null
        Start-Sleep -Milliseconds 1000
        Invoke-CefDownloader -Action Js `
            -Body "Array.from(document.querySelectorAll('tr')).forEach(row => console.log(Array.from(row.children).map(e => e.innerText).join('\t')))" |
            ForEach-Object Content |
            ConvertFrom-Json |
            ForEach-Object console |
            ConvertFrom-Csv -Delimiter `t |
            ForEach-Object `
                -Begin   {
                    $padding0 = "            "
                    Write-Host "$padding0│5   6   7   8   9  10  11  12  13  14  15  16  17  18  19  20│   "
                    Write-Host "$padding0├$("─" * 61)┤   "
                } `
                -Process {
                    $date = $null
                    try { $date = [datetime]::Parse($_.DATUM) } catch {}

                    if ($null -ne $date) {
                        $startEnd = $_.ARBEIT.Split("-")
                        if ($startEnd[0].Trim() -eq "00:00") {
                            $start    = [datetime]::Parse("05:00")
                            $end      = [datetime]::Parse($startEnd[1])
                            # $worktime = $_.ARBEITSZEIT.Split(":")
                            # $start    = $end - [timespan]::new($worktime[0], $worktime[1], 0)
                        } else {
                            $start    = [datetime]::Parse($startEnd[0])
                            $end      = [datetime]::Parse($startEnd[1])
                        }

                        $a        = [Math]::Max(0, ($start - [datetime]::Parse("05:00")).TotalHours * 4)
                        $b        = [Math]::Max(0, ($end - $start).TotalHours * 4)
                        $timeline = "$(" " * $a)$("█" * $b)".PadRight(61)

                        $worktime = ($end - $start).TotalHours

                        $c_DayOfWeek = if ($date.DayOfWeek -eq [System.DayOfWeek]::Sunday) {
                            "`e[31m"
                        } elseif ($date.DayOfWeek -eq [System.DayOfWeek]::Saturday) {
                            "`e[31m"
                        } else {
                            ""
                        }
                        $c_DayOfMonth = if ($null -eq $last) {
                        } elseif ($date.DayOfWeek -eq [System.DayOfWeek]::Monday) {
                        } elseif ($last.date.Day -ne $date.Day - 1) {
                            "`e[31m"
                        } else {
                            ""
                        }
                        $c_WorkTime = if ($worktime -gt 12) {
                            "`e[31m"
                        } elseif ($worktime -lt 6) {
                            "`e[31m"
                        } else {
                            ""
                        }

                        @(
                            "$c_DayOfWeek$($date.ToString("ddd"))`e[0m $c_DayOfMonth$($date.ToString("dd."))`e[0m $($start.ToString("hh:mm"))"
                            "$timeline"
                            "$($end.ToString("HH:mm")) => $c_WorkTime$($worktime.ToString("0.0 h").PadLeft(6))`e[0m"
                        ) |
                            Join-String -Separator "│" |
                            Write-Host

                        $last = [pscustomobject]@{
                            date = $date
                        }
                    }
                } `
                -End     {
                    Write-Host "$padding0└$("─" * 61)┘   "
                } `

        # close browser
        Invoke-CefDownloader -Action Quit | Out-Null
    }
    catch {
        Invoke-CefDownloader -Kill
        throw
    }
}
