#Requires -PSEdition Core
param (
    [Parameter(Mandatory=$true,
               ParameterSetName="WorkitemIdParameterSetName",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [Alias("Id")]
    [ValidateNotNullOrEmpty()]
    [int[]]
    $Workitem,

    [Parameter(Mandatory=$true,
               ParameterSetName="AllParameterSetName",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [switch]
    $All,

    [Parameter(Mandatory=$false,
               ParameterSetName="AllParameterSetName",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [int[]]
    $Exclude,

    [Parameter(Mandatory=$true,
               Position=1,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [ValidateSet(1,2,3,4,5,6,7,8,9,10,11,12)]
    [int]
    $Month
)
DynamicParam {
    $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

    #region dynamic parameter 'Tag'
    $ParameterName = 'Tag'

    # Create the collection of attributes
    $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]

    # Create and set the parameters attributes
    $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.ParameterSetName = "TagParameterSet"
    # $ParameterAttribute.HelpMessage = ""
    $AttributeCollection.Add($ParameterAttribute)

    # Generate and set the ValidateSet
    $collection = & "$PSScriptRoot\Invoke-RestApi.ps1" `
                            -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/tags?api-version=6.0-preview.1" |
                            ForEach-Object value |
                            ForEach-Object name
    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($collection)
    $AttributeCollection.Add($ValidateSetAttribute)
    
    # Create and return the dynamic parameter
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
    #endregion

    #region dynamic parameter 'Year'
    $ParameterName = 'Year'

    # Create the collection of attributes
    $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]

    # Create and set the parameters attributes
    $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.Position = 0
    $AttributeCollection.Add($ParameterAttribute)

    # Generate and set the ValidateSet
    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        (Get-Date).Year - 1
        (Get-Date).Year
        (Get-Date).Year + 1
    ))
    $AttributeCollection.Add($ValidateSetAttribute)
    
    # Create and return the dynamic parameter
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
    #endregion

    return $RuntimeParameterDictionary
}
Process {
    if ($PSBoundParameters.Debug) { $ErrorActionPreference = 'Break' }
    $Tag = $PSBoundParameters['Tag']
    $Year = $PSBoundParameters['Year']

    $start_date = [datetime]::new($Year, $Month, 1)
    $end_date   = $start_date.AddMonths(1).AddDays(-1)

    New-Alias -Name "Get-Issues" -Value "$PSScriptRoot\Get-Issues.ps1" -ErrorAction SilentlyContinue
    New-Alias -Name "Invoke-RestApi" -Value "$PSScriptRoot\Invoke-RestApi.ps1" -ErrorAction SilentlyContinue
    New-Alias -Name "Get-TauWorkTogetherHolidays" -Value "$PSScriptRoot\Get-TauWorkTogetherHolidays.ps1" -ErrorAction SilentlyContinue

    if ($All) {
        $Workitem = Get-Issues -Start $start_date -End ($end_date.AddDays(14)) |
                        Where-Object Id -NotIn $Exclude |
                        ForEach-Object Id
    }

    Write-Host "Getting holidays from https://rocom.tau-work-together.de/"
    $tauWorkTogether = 0..($start_date-$end_date).TotalDays |
                        ForEach-Object { $start_date.AddDays($_) } |
                        Group-Object {"$($_.Year)-$($_.Month)"} |
                        ForEach-Object { $_.Group[0] } |
                        ForEach-Object { Get-TauWorkTogetherHolidays -Month $_.Month -Year $_.Year }
    $tauWorkTogether.holidays |
        Where-Object { $_.event -eq $false -or ($_.event -eq $true -and $_.title -EQ "Wolfgang Puchinger") } |
        ForEach-Object Start |
        ConvertTo-Json -Compress |
        Write-Host -ForegroundColor Green

    Write-Host "Downloading parents.."
    if ($Workitem.Count -gt 0) {
        $query = "SELECT [System.ID] FROM WorkItems WHERE [System.Id] IN ($($Workitem -join ','))"
    } else {
        $query = "SELECT [System.ID] FROM WorkItems WHERE [System.Tags] CONTAINS '$Tag'"
    }
    $parent_ids = Invoke-RestApi `
                    -Endpoint "POST https://dev.azure.com/{organization}/{project}/{team}/_apis/wit/wiql?api-version=6.0" `
                    -Body @{ query = $query } |
                    ForEach-Object workItems |
                    ForEach-Object id
    $parent_ids | ConvertTo-Json -Compress | Write-Host -ForegroundColor Green

    Write-Host "Downloading children.."
    $downloaded = @()
    $missing_ids = @() + $parent_ids
    while ($missing_ids.Count -gt 0) {
        while ($missing_ids.Count -gt 0) {
            $items = Invoke-RestApi `
                        -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/workitems?ids={ids}&`$expand=relations&api-version=6.0" `
                        -Variables @{ ids = ($missing_ids | Select-Object -First 200) -join "," } |
                        ForEach-Object value
            $downloaded += $items
            $missing_ids = $missing_ids | Select-Object -Skip 200
        }

        $missing_ids += $items.relations.url |
                    Select-String "/workItems/(?<id>\d+)$" |
                    ForEach-Object { [int]::Parse($_.Matches.Groups[1].Value) } |
                    Where-Object { $downloaded.id -notcontains $_ }

    }
    $downloaded.id | ConvertTo-Json -Compress | Write-Host -ForegroundColor Green

    Write-Host "Removeing false positives.."
    $downloaded = $downloaded | Where-Object { $_.fields.'System.ChangedDate' -ge $start_date }
    $downloaded.id | ConvertTo-Json -Compress | Write-Host -ForegroundColor Green

    $activity = "Building relations"
    $progess = 0
    $collection = $downloaded.relations
    foreach ($rel in $downloaded.relations) {
        $progess++; Write-Progress -Activity $activity -PercentComplete (100*($progess / $collection.Count))

        if ($null -ne $rel) {
            $w = $rel.url |
                    Select-String "/workItems/(?<id>\d+)$" |
                    ForEach-Object { [int]::Parse($_.Matches.Groups[1].Value) } |
                    ForEach-Object { $id=$_; $downloaded | Where-Object { $_.id -eq $id } }
            
            Add-Member `
                -InputObject $rel `
                -NotePropertyName "workitem" `
                -NotePropertyValue $w
        }
    }
    Write-Progress -Activity $activity -Completed
    Write-Host "$activity.." -NoNewline
    "done" | Write-Host -ForegroundColor Green


    $activity = "Downloading revisions"
    $progess = 0
    $collection = $downloaded | Where-Object { $_.fields.'System.ChangedDate' -gt $start_date }
    foreach ($item in $collection) {
        $progess++; Write-Progress -Activity $activity -PercentComplete (100*($progess / $collection.Count))

        Add-Member `
                -InputObject $item `
                -NotePropertyName "revisions" `
                -NotePropertyValue @()

        foreach ($rev in 1..$item.rev) {
            $rev = $item.rev - $rev + 1
            $workitem_revision = Invoke-RestApi `
                            -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/workItems/{id}/revisions/{revisionNumber}?api-version=6.0" `
                            -Variables @{ id = $item.id; revisionNumber = $rev }
            $item.revisions += $workitem_revision
            
            if ($workitem_revision.fields.'System.State' -in 'Done','To Do') {
                if ($workitem_revision.fields.'System.ChangedDate' -lt $start_date) {
                    break
                }
            }
        }
    }
    Write-Progress -Activity $activity -Completed
    Write-Host "$activity.." -NoNewline
    "done" | Write-Host -ForegroundColor Green
    

    $activity = "Gettting days off"
    Write-Progress -Activity $activity -PercentComplete 1
    $iterationPaths = $downloaded.fields.'System.IterationPath' + $downloaded.revisions.fields.'System.IterationPath'
    $iterations = Invoke-RestApi `
                    -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=6.0" |
                    ForEach-Object value |
                    Where-Object { $_.path -in $iterationPaths }

    $daysOff = $iterations |
        ForEach-Object {
            Invoke-RestApi `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/capacities?api-version=7.1-preview.3" `
                -Variables @{ iterationId = $_.Id }
        } |
        ForEach-Object teamMembers |
        Where-Object { $_.daysOff.count -gt 0 }
        
    $team_daysOff = $iterations |
                        ForEach-Object {
                            Invoke-RestApi `
                                -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/teamdaysoff?api-version=6.0" `
                                -Variables @{ iterationId = $_.Id }
                        } |
                        ForEach-Object daysOff |
                        ForEach-Object {
                            $d = $_.start
                            $end = $_.end
                            while ($d -le $end) {
                                $d.Date
                                $d = $d.AddDays(1)
                            }
                        }
    
    
    $team_daysOff += $tauWorkTogether.holidays | Where-Object event -EQ $false
    
    $teamMembers = $downloaded.fields.'System.AssignedTo' | Group-Object { $_.id } | ForEach-Object { $_.Group[0] }
    $daysOff = $daysOff | ForEach-Object `
                            -Process {$_} `
                            -End {
                                    $tauWorkTogether.holidays |
                                    Where-Object event -EQ $true |
                                    Where-Object title -in $teamMembers.displayName |
                                    ForEach-Object {
                                        $i=$_
                                        [pscustomobject] @{
                                            teamMember=$teamMembers | Where-Object displayName -eq $i.title
                                            daysOff = [pscustomobject]@{start=$i.start;end=$i.start}
                                        }
                                    }
                            }
    Write-Progress -Activity $activity -Completed
    Write-Host "$activity.." -NoNewline
    "done" | Write-Host -ForegroundColor Green

    $activity = "Createing report.."
    Write-Progress -Activity $activity -PercentComplete 1
    $downloaded |
        Where-Object { $_.fields.'System.WorkItemType' -ne 'Epic' } |
        ForEach-Object {
            $ret = $null
            foreach ($rev in $_.revisions | Sort-Object rev) {
                if ($null -eq $ret) {
                    $ret = [pscustomobject]@{ workitem = $_; ToDo = $null; Doing = $null; Done = $null; }
                }

                if ($rev.fields.'System.State' -eq 'To Do' -and $null -eq $ret.ToDo) {
                    $ret.ToDo = $rev.fields.'System.ChangedDate'.Date
                }
                if ($rev.fields.'System.State' -eq 'Doing' -and $null -eq $ret.Doing) {
                    $ret.Doing = $rev.fields.'System.ChangedDate'.Date
                }
                if ($rev.fields.'System.State' -eq 'Done' -and $null -eq $ret.Done) {
                    if ($null -ne $ret.Doing -or $null -ne $ret.ToDo) {
                        $ret.Done = $rev.fields.'System.ChangedDate'.Date
                        $ret
                        $ret = $null
                    }
                }
            }
            if ($null -ne $ret) {
                if ($null -ne $ret.Doing `
                -or $null -ne $ret.ToDo `
                -or $null -ne $ret.Done) {
                    $ret
                }
            }
        } |
        ForEach-Object {
            Add-Member -InputObject $_ -NotePropertyName "Start" -NotePropertyValue $null
            Add-Member -InputObject $_ -NotePropertyName "End" -NotePropertyValue $null
            
            if ($_.Doing -ne $null) {
                $ret.Start = $_.Doing
                $ret.End = $_.Done
            } else {
                $ret.Start = $_.Done
                $ret.End = $_.Done
            }

            $ret
        } |
        Where-Object { $_.Start -ne $null } |
        Where-Object { $_.workitem.fields.'System.WorkItemType' -eq 'Task' } |
        ForEach-Object {
            $w = $_.workitem
            $date = $start_date

            while ($date -le $end_date) {
                if ($date.DayOfWeek -eq [System.DayOfWeek]::Saturday) {
                }
                elseif ($date.DayOfWeek -eq [System.DayOfWeek]::Sunday) {
                }
                elseif ($_.Start -le $date -and $_.End -ge $date) {
                    $dayOff = $daysOff |
                                Where-Object { $_.teamMember.Id -EQ $w.fields.'System.AssignedTo'.Id } |
                                Where-Object { $_.daysOff.start -le $date -and $_.daysOff.end -ge $date }
                    
                    if ($dayOff.Count -eq 0 -and $date -notin $team_daysOff) {
                        [pscustomobject]@{
                            Datum          = $date
                            Activated      = $w.fields.'Microsoft.VSTS.Common.ActivatedDate'
                            Closed         = $w.fields.'Microsoft.VSTS.Common.ClosedDate'
                            Oberpunkt      = $downloaded | Where-Object id -EQ $w.fields.'System.Parent' | ForEach-Object { "$($_.fields.'System.Title') ($($_.fields.'System.WorkItemType') $($_.id))" }
                            Arbeitsschritt = "$($w.fields.'System.Title') ($($w.fields.'System.WorkItemType') $($w.id))"
                            Mitarbeiter    = $w.fields.'System.AssignedTo'.displayName
                        }
                    }
                }

                $date = $date.AddDays(1)
            }
        } |
        Group-Object Datum, Oberpunkt, Arbeitsschritt |
        ForEach-Object { $_.Group[0] } |
        Sort-Object Datum, Oberpunkt, Arbeitsschritt |
        ConvertTo-Csv -Delimiter `t |
        Set-Clipboard
    Write-Progress -Activity $activity -Completed
    Write-Host "$activity.." -NoNewline
    "done" | Write-Host -ForegroundColor Green

    "" | Write-Host -ForegroundColor Green
    "data is copied to clipboard" | Write-Host -ForegroundColor Green
    "" | Write-Host -ForegroundColor Green
    
    "All done, exiting.." | Write-Host -ForegroundColor Green
}
