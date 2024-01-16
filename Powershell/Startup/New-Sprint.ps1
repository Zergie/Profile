[cmdletbinding()]
#Requires -PSEdition Core
param (
    # Specifies a path to one or more locations.
    [Parameter(Mandatory=$false,
               ParameterSetName="ParameterSetName",
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [switch]
    $UpdateLast
)
Process {

    New-Alias -Name "Invoke-RestApi" -Value "$PSScriptRoot\Invoke-RestApi.ps1"

    $global:holidays = Get-TauWorkTogetherHolidays -rocomservice |
                            ForEach-Object holidays
    $team = Invoke-RestApi -Endpoint 'GET https://dev.azure.com/{organization}/_apis/projects/{projectId}/teams/{teamId}/members?api-version=6.0' |
                        ForEach-Object value |
                        ForEach-Object identity |
                        Where-Object displayName -NotLike "*rocom-service*" |
                        Add-Member -PassThru -MemberType ScriptProperty -Name "holidays" -Value { $global:holidays | Where-Object title -eq $this.displayName | ForEach-Object { [datetime]$_.start } }

    $last_sprint = Invoke-RestApi -Endpoint 'GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=6.0' |
                        ForEach-Object value |
                        Select-Object -Last 1 |
                        Add-Member -PassThru -MemberType ScriptProperty -Name "number" -Value { [int](($this.Name | Select-String -Pattern "[0-9]+$").Matches.Value) }
    $last_sprint.attributes.startDate = [datetime]$last_sprint.attributes.startDate
    $last_sprint.attributes.finishDate = [datetime]$last_sprint.attributes.finishDate

    if ($UpdateLast) {
        $new_sprint = $last_sprint
    } else {
        $new_iteration = Invoke-RestApi `
                            -Endpoint 'POST https://dev.azure.com/{organization}/{project}/_apis/wit/classificationnodes/{structureGroup}?api-version=5.0' `
                            -Variables @{ structureGroup="Iterations" } `
                            -Body @{
                                name= "Sprint $($last_sprint.number + 1)"
                                attributes= @{
                                    startDate= $last_sprint.attributes.finishDate.AddDays(3)
                                    finishDate= $last_sprint.attributes.finishDate.AddDays(3).AddDays(11)
                                    timeFrame= "future"
                                }
                            }
        $new_sprint = Invoke-RestApi `
                            -Endpoint 'POST https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=6.0' `
                            -Body @{
                                id= $new_iteration.identifier
                            }
    }

    $team_holidays = @( $new_sprint.attributes.startDate, $new_sprint.attributes.finishDate) |
                        ForEach-Object Year |
                        Group-Object |
                        ForEach-Object Name |
                        ForEach-Object {
                            Invoke-RestMethod https://feiertage-api.de/api/?jahr=$_ |
                                ForEach-Object { $_.BY } |
                                ForEach-Object {
                                    $data = $_
                                    $data |
                                        Get-Member -Type NoteProperty |
                                        ForEach-Object {
                                            $i = $data.$($_.Name)
                                            [pscustomobject]@{
                                                name = $_.Name
                                                datum = [datetime]::Parse($i.datum)
                                                hinweis = $i.hinweis
                                            }
                                        }
                                }
                        } |
                        Where-Object hinweis -NotLike "* nur im Stadtgebiet Augsburg *" |
                        Where-Object datum -GE $new_sprint.attributes.startDate |
                        Where-Object datum -LE $new_sprint.attributes.finishDate |
                        ForEach-Object datum |
                        ForEach-Object `
                            -Begin   { $last = $null} `
                            -Process {
                                if ($null -eq $last)  {
                                    $last = @{start=$_ ; end=$_}
                                } elseif ($last.end -eq $_.AddDays(-1)) {
                                    $last.end = $_
                                } else {
                                    $last
                                    $last = $null
                                }
                            } `
                            -End { $last }

    $holidays = @()
    foreach ($holiday in $team_holidays) {
        $holidays += $holiday
    }
    Invoke-RestApi `
        -Endpoint 'PATCH https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/teamdaysoff?api-version=6.0' `
        -Variables @{ iterationId= $new_sprint.id } `
        -Body @{
            daysOff= $holidays
        }


    foreach ($member in $team) {
        $holidays = @()
        $holidays += $member.holidays |
                        Where-Object { $_ -ge $new_sprint.attributes.startDate -and $_ -le $new_sprint.attributes.finishDate } |
                        ForEach-Object `
                            -Begin   { $last = $null} `
                            -Process {
                                if ($null -eq $last)  {
                                    $last = @{start=$_ ; end=$_}
                                } elseif ($last.end -eq $_.AddDays(-1)) {
                                    $last.end = $_
                                } else {
                                    $last
                                    $last = $null
                                }
                            } `
                            -End { $last }

        Invoke-RestApi `
            -Endpoint 'PATCH https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/capacities/{teamMemberId}?api-version=6.0' `
            -Variables @{
                iterationId= $new_sprint.id
                teamMemberId= $member.id
             } `
             -Body @{
                daysOff= $holidays
                activities= @(@{
                    capacityPerDay= 5
                })
             }
    }

    if (! $UpdateLast) {
        Start-Process "https://dev.azure.com/rocom-service/TauOffice/_sprints/capacity/TauOffice%20Team/TauOffice/$($new_sprint.name -replace " ","%20")"
    }
}
