[cmdletbinding()]
param (
#        [Parameter(Mandatory=$true,
#                   Position=1,
#                   ParameterSetName="DefaultParameterSet",
#                   ValueFromPipeline=$true,
#                   ValueFromPipelineByPropertyName=$true)]
#        [int[]]
#        $Days,
#
#        [Parameter(Mandatory=$true,
#                   Position=2,
#                   ParameterSetName="DefaultParameterSet",
#                   ValueFromPipeline=$true,
#                   ValueFromPipelineByPropertyName=$true)]
#        [int]
#        $Month,
#
#        [Parameter(Mandatory=$true,
#                   Position=3,
#                   ParameterSetName="DefaultParameterSet",
#                   ValueFromPipeline=$true,
#                   ValueFromPipelineByPropertyName=$true)]
#        [int]
#        $Year,
#
#        [Parameter(Mandatory=$true,
#                   Position=4,
#                   ParameterSetName="DefaultParameterSet",
#                   ValueFromPipeline=$true,
#                   ValueFromPipelineByPropertyName=$true)]
#        [string]
#        $Path
)
begin {
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

        Invoke-WebRequest -Method Post -Uri http://localhost:8888/js -Body "document.querySelectorAll('a.btn')[0].click()"

        Invoke-WebRequest -Method Post -Uri http://localhost:8888/js -Body "
            var input = document.querySelectorAll('input.form-control.datepicker')[0];
            input.dispatchEvent(new Event('compositionstart', { bubbles: true }));
            input.value = '$($Day.ToString("00")).$($Month.ToString("00")).$($Year.ToString("0000"))';
            input.dispatchEvent(new Event('change', { bubbles: true }));
            input.dispatchEvent(new Event('compositionend', { bubbles: true }));
            Array.from(document.querySelectorAll('button.btn-primary')).find(el => el.textContent === 'Arbeitstag speichern').click()
            " |
            ForEach-Object Content
        Start-Sleep -Milliseconds 500

    }
}
process {
}
end {
    $Days  = @(1,2,3,4,5,6)
    $Month = 3
    $Year  = 2023
    $Path  = 'D:\Dokumente\Tätigkeitsnachweis.xlsx'

    # get worktimes from 'Tätigkeitsnachweis'
    $WorkTimes = Import-Excel -Path $Path -WorksheetName Arbeitszeiten -StartRow 2 |
                    Where-Object { $_.date.Month -eq $Month }

    # remove weekends only
    $Days = $Days | Where-Object { $_ -in $WorkTimes.date.Day }

    # open browser
    Write-Host "open new browser .."
    . "$PSScriptRoot/Get-TauWorkTogetherHolidays.ps1" -Year $Year -Month $Month | Out-Null # reuse login logic
    $cefDownloader = Get-Process CefSharpDownloader

    try {
        # get the current browser state
        Invoke-WebRequest -Method Post -Uri http://localhost:8888 | ForEach-Object Content

        # find days that needs to be created and create them
        Invoke-WebRequest -Method Post -Uri http://localhost:8888/get -Body "https://rocom.tau-work-together.de/worktime/month/$Month/$Year/21" | Out-Null
        Start-Sleep -Milliseconds 500
        $Days |
            Where-Object { $_ -notin (
                                        Invoke-WebRequest -Method Post -Uri http://localhost:8888/content |
                                            ForEach-Object Content |
                                            Select-String -Pattern "\d{2}\.\d{2}\.$Year" -AllMatches |
                                            ForEach-Object Matches |
                                            ForEach-Object Value |
                                            ForEach-Object { [datetime]::ParseExact($_, "dd.MM.yyyy", $null) } |
                                            Where-Object Month -eq $Month |
                                            ForEach-Object Day
                                     )
            } |
            ForEach-Object { Add-Day $_ $Month $Year }

        # add workhours to workday
        $WorkTimes |
            Where-Object { $_.date.Day -in $Days } |
            ForEach-Object {
                throw "not implemented"
            }

        # close browser
        Invoke-WebRequest -Method Post -Uri http://localhost:8888/quit | ForEach-Object Content
    }
    catch {
        $cefDownloader.Kill()
        throw
    }
}
