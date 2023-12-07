#Requires -PSEdition Core
[cmdletbinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="IdParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $WorkitemId,

    [Parameter(Mandatory=$true,
               ParameterSetName="NewParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [Alias('n')]
    [switch]
    $New,

    [Parameter(Mandatory=$true,
               ParameterSetName="BranchesParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [Alias('b')]
    [switch]
    $Branches,

    [Parameter(Mandatory=$true,
               ParameterSetName="TodoParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [Alias('t')]
    [switch]
    $ToDo,

    [Parameter(Mandatory=$true,
               ParameterSetName="DoingParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [Alias('d')]
    [switch]
    $Doing,

    [Parameter(Mandatory=$true,
               ParameterSetName="StartParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [DateTime]
    $Start,

    [Parameter(Mandatory=$true,
               ParameterSetName="StartParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [DateTime]
    $End,

    [Parameter(Mandatory=$false,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [switch]
    $BeginWork,

    [Parameter(Mandatory=$false,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [Alias('u')]
    [switch]
    $Update,

    [Parameter(Mandatory=$false,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [Alias('a')]
    [switch]
    $Assign,

    [Parameter(Mandatory=$false,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [Alias('o')]
    [switch]
    $Online,

    [Parameter(Mandatory=$false,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [Alias('p')]
    [switch]
    $Pdf
)
DynamicParam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Iteration
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.ParameterSetName = "IterationParameterSet"
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        & "$PSScriptRoot\Invoke-RestApi.ps1" `
                    -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=6.0" |
                    ForEach-Object value |
                    ForEach-Object path
        "@Newest Iteration"
        "@Current Iteration"
    ))
    $AttributeCollection.Add($ValidateSetAttribute)
    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Iteration", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    # param Query
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.ParameterSetName = "QueryParameterSet"
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        & "$PSScriptRoot\Invoke-RestApi.ps1" `
                    -Endpoint 'GET https://dev.azure.com/{organization}/{project}/_apis/wit/queries?$depth=1&api-version=7.0' |
                    ForEach-Object value |
                    ForEach-Object children |
                    ForEach-Object name
    ))
    $AttributeCollection.Add($ValidateSetAttribute)
    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Query", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    # param Name
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $false
    $ParameterAttribute.ParameterSetName = "NameParameterSet"
    $AttributeCollection.Add($ParameterAttribute)

    $ids = & "$PSScriptRoot\Invoke-RestApi.ps1" `
                -Endpoint "POST https://dev.azure.com/{organization}/{project}/{team}/_apis/wit/wiql?api-version=6.0" `
                -Body @{
                    query = "SELECT [System.Id] FROM WorkItems WHERE [System.State] <> 'Done' AND [System.WorkItemType] <> 'Task' AND [System.TeamProject] = 'TauOffice'"
                } |
                ForEach-Object workItems |
                ForEach-Object id
    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        & "$PSScriptRoot\Invoke-RestApi.ps1" `
                -Endpoint "POST https://dev.azure.com/{organization}/{project}/_apis/wit/workitemsbatch?api-version=6.0" `
                -Body @{
                    ids= $ids
                    fields= @(
                        "System.Id"
                        "System.Title"
                     )
                } |
                ForEach-Object value |
                ForEach-Object fields |
                ForEach-Object { "$($_.'System.Id') - $($_.'System.Title')" } |
                Sort-Object
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Name", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}
begin {
    ${Invoke-RestApi}  = "$PSScriptRoot\Invoke-RestApi.ps1"
    ${Get-Attachments} = "$PSScriptRoot\Get-Attachments.ps1"
    ${New-Attachments} = "$PSScriptRoot\New-Attachments.ps1"
    ${ConvertTo-Pdf}   = "$PSScriptRoot\ConvertTo-Pdf.ps1"
    $PSDefaultParameterValues["ForEach-Object:WhatIf"] = $false

    @("User.WorkItem", "User.WorkItemPdf") |
    ForEach-Object {
        if ($null -eq (Get-FormatData -TypeName $_)) {
            Update-FormatData -PrependPath "$PSScriptRoot\..\Format\${_}.ps1xml"
        }
    }
}
process {
    $IterationName = $PSBoundParameters['Iteration']
    $Query         = $PSBoundParameters['Query']
    $Name          = $PSBoundParameters['Name']

    $downloaded = @()
    if ($IterationName -eq "@Current Iteration") {
        $missing_ids = . ${Invoke-RestApi} `
                -Endpoint "POST https://dev.azure.com/{organization}/{project}/{team}/_apis/wit/wiql?api-version=5.1" `
                -Body @{
                    query = "SELECT [System.Id] FROM WorkItems WHERE [System.State] <> 'Done' AND [System.IterationPath] = @currentIteration('[TauOffice]\TauOffice Team <id:48deb8b1-0e33-40d0-8879-71d5258a79f7>')"
                } |
                ForEach-Object workItems |
                ForEach-Object id
    } elseif ($null -ne $IterationName) {
        if ($IterationName -eq "@Newest Iteration") {
            $IterationName = . ${Invoke-RestApi} `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=6.0" |
                ForEach-Object value |
                ForEach-Object path |
                Select-Object -Last 1
            Write-Host "Getting Iteration " -NoNewline
            Write-Host -ForegroundColor Magenta $IterationName
        }

        $Iteration = . ${Invoke-RestApi} `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=6.0" |
                ForEach-Object value |
                Where-Object Path -eq $IterationName

        $missing_ids = . ${Invoke-RestApi} `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/workitems?api-version=6.0-preview.1" `
                -Variables @{ iterationId = $Iteration.Id } |
                ForEach-Object workItemRelations |
                ForEach-Object target |
                ForEach-Object id
    } elseif ($null -ne $Name) {
        $missing_ids = $Name |
            ForEach-Object { $_.Split("-")[0] }
    } elseif ($null -ne $WorkitemId) {
        $missing_ids = $WorkitemId |
            ForEach-Object { if ($_.Contains("-")) { $_.Split("-")[0] } else { $_ } }
    } else {
        $wiql = if ($New) {
                "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Issue'" +
                                                   " AND [System.State] = 'To Do'" +
                                                   " AND [System.ChangedBy] <> @Me " +
                                                   " AND [System.TeamProject] = 'TauOffice'" +
                                                   " AND [System.CreatedDate] >= @StartOfDay - 14"
            } elseif ($ToDo) {
                "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Issue'" +
                                                   " AND [System.State] = 'To Do'" +
                                                   " AND [System.TeamProject] = 'TauOffice'"
            } elseif ($Doing) {
                "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Issue'" +
                                                   " AND [System.State] = 'Doing'" +
                                                   " AND [System.TeamProject] = 'TauOffice'"
            } elseif ($Branches) {
                "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Issue' AND [System.Id] IN ($(
                    git branch |
                            Select-String -pattern "users/.*/(\d+)" |
                            ForEach-Object{ $_.Matches.Groups[1].Value } |
                            Join-String -Separator ","
                    ))"
            } elseif ($null -ne $Query) {
                . ${Invoke-RestApi} `
                    -Endpoint 'GET https://dev.azure.com/{organization}/{project}/_apis/wit/queries?$depth=1&$expand=wiql&api-version=7.0' |
                    ForEach-Object value |
                    ForEach-Object children |
                    Where-Object name -EQ $Query |
                    ForEach-Object wiql
            } elseif ($null -ne $Start) {
                "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Issue'" +
                                                   " AND [System.ChangedDate] >= '$($Start.ToString("o"))'" +
                                                   " AND [System.ChangedDate] <= '$($End.ToString("o"))'"
            } else {
                throw "Not implemented!"
            }

        Write-Debug $wiql
        $missing_ids = . ${Invoke-RestApi} `
                -Endpoint "POST https://dev.azure.com/{organization}/{project}/{team}/_apis/wit/wiql?api-version=5.1" `
                -Body @{
                    query = $wiql
                } |
                ForEach-Object workItems |
                ForEach-Object id
    }

    while ($missing_ids.Count -gt 0) {
        while ($missing_ids.Count -gt 0) {
            $items = . ${Invoke-RestApi} `
                        -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/workitems?ids={ids}&`$expand=relations&api-version=6.0" `
                        -Variables @{ ids = ($missing_ids | Select-Object -First 200) -join "," } |
                        ForEach-Object value
            $downloaded += $items
            $missing_ids = $missing_ids | Select-Object -Skip 200
        }
    }

    $workitems = $downloaded |
        Where-Object { $_.fields.'System.WorkItemType' -eq "Issue" -or $null -ne $Id } |
        ForEach-Object {
            $_.PSObject.TypeNames.Insert(0, 'User.WorkItem')
            $_
        }

    if ($Pdf) {
        Push-Location $env:TEMP
        $workitems |
            ForEach-Object {
                $file = . "$PSScriptRoot/Get-Attachments.ps1" -Id $_.Id -Filter "^.+\.pdf$"

                Add-Member -InputObject $_ -NotePropertyName 'HasPdf' -NotePropertyValue ($null -ne $file)
                $_.PSObject.TypeNames.Insert(0, 'User.WorkItemPdf')

                $file
            } |
            ForEach-Object { Start-Process $_ }
        Pop-Location
    }

    if ($Update -or $Assign -or $BeginWork) {
        if ($Update) {
            $workitems |
                . ${Get-Attachments} -Filter ".(docx)$" |
                . ${ConvertTo-Pdf} -OutVariable pdfs |
                Out-Null

            if ($PSCmdlet.ShouldProcess($workitems.Id, "New-Attachments")) {
                if ($pdfs.Length -gt 0) {
                    $pdfs | . ${New-Attachments}
                }
            }
        }

        $patches = @{}
        $workitems | ForEach-Object { $patches.Add($_.Id, @()) }

        $workitems |
            ForEach-Object {
                if ($Update -or $BeginWork) {
                    $subtasks = $_.relations |
                                Where-Object rel -EQ "System.LinkTypes.Hierarchy-Forward" |
                                Add-Member -MemberType ScriptProperty `
                                           -Name 'Id' `
                                           -Value { [int]($this.url -split '/' | Select-Object -Last 1) } `
                                           -Force `
                                           -PassThru
                }

                if ($Update) {
                    $patches[$_.Id] += @(
                                        $_.fields.'System.Description' | Select-String "ID:?(\d{3,5})" -AllMatches
                                        $_.fields.'System.Title' | Select-String "DevOpsID:\s*(\d+)\s*"
                                        $_.fields.'System.Title' | Select-String "^ID:\s*(\d+)\s*"
                        ) |
                        ForEach-Object Matches |
                        ForEach-Object {$_.Groups[1].Value} |
                        Group-Object |
                        ForEach-Object {[int]$_.name} |
                        Where-Object { $_ -notin ($_.relations.url | ForEach-Object { [int]($_ -split '/' | Select-Object -last 1)}) } |
                        ForEach-Object {
                            [ordered]@{
                                op    = "add"
                                path  = "/relations/-"
                                value = [ordered]@{
                                    rel = "System.LinkTypes.Related"
                                    url = "https://dev.azure.com/rocom-service/22af98ac-669d-4f9a-b415-3eb69c863d24/_apis/wit/workItems/$_"
                                    }
                            }
                        }

                    $patches[$_.Id] += [ordered]@{
                            op    = "replace"
                            path  = "/fields/System.Title"
                            value = $_.fields.'System.Title' `
                                        -replace 'Korrektur (?:auf|aus) Aufgabe (?:ID |ID: )?\d+ \(DevOpsID:\s*(\d+)\s*\)', 'Erweiterung von #$1' `
                                        -replace 'Korrektur (?:auf|aus)(?: Aufgabe ID:?| Aufgabe)? (\d+)', 'Erweiterung von #$1' `
                                        -replace 'ID:(\d+) .+', 'Erweiterung von #$1' `
                                        -replace '(Aufgabe siehe Word),?\s*', '' `
                                        -replace '[.!]\s*$', '' `
                                        -replace ' Fehler$', ' Weiterentwicklung' `
                                        -replace '(Zusatzschleife|Nachbesserung)\b', 'Weiterentwicklung'
                    }

                    $patches[$_.Id] += [ordered]@{
                            op    = "replace"
                            path  = "/fields/System.Description"
                            value = $_.fields.'System.Description' `
                                        -replace 'Korrektur auf Aufgabe ID \d+ \(DevOpsID: (\d+)\)' `
                                               , 'Erweiterung von <a href="https://dev.azure.com/rocom-service/22af98ac-669d-4f9a-b415-3eb69c863d24/_workitems/edit/$1"
                                                              data-vss-mention="version:1.0">#$1</a>' `
                                        -replace "<p>&nbsp; </p>`n", '' `
                                        -replace 'Beheben (in|bis)(:|)', 'Umsetzen $1 ' `
                                        -replace 'Fehler (siehe) ', 'Aufgabe $1 ' `
                                        -replace 'Fehlerbeschreibung ', 'Aufgabenbeschreibung ' `
                                        -replace '(Hallo) Wolfgang', '$1'
                    }

                    if ($Update -and ($subtasks | Measure-Object).Count -eq 0) {
                        $task = . ${Invoke-RestApi} `
                            -Endpoint "POST https://dev.azure.com/{organization}/{project}/_apis/wit/workitems/`${type}?api-version=7.0" `
                            -Variables @{ type = "task" } `
                            -PatchBody @([ordered]@{
                                    op    = "add"
                                    path  = "/fields/System.Title"
                                    from  = "null"
                                    value = "Implementierung und Test"
                                }
                                [ordered]@{
                                    op    = "add"
                                    path  = "/fields/System.IterationPath"
                                    from  = "null"
                                    value = $_.fields.'System.IterationPath'
                                }
                                if ($Assign) {
                                    [ordered]@{
                                        op    = "add"
                                        path  = "/fields/System.AssignedTo"
                                        from  = "null"
                                        value = (Get-LocalUser -Name $env:USERNAME).FullName
                                    }
                                } elseif ($null -ne $_.fields.'System.AssignedTo') {
                                    [ordered]@{
                                        op    = "add"
                                        path  = "/fields/System.AssignedTo"
                                        from  = "null"
                                        value = $_.fields.'System.AssignedTo'
                                    }
                                })
                        $patches[$_.Id] += [ordered]@{
                                op    = "add"
                                path  = "/relations/-"
                                value = [ordered]@{
                                    rel = "System.LinkTypes.Hierarchy-Forward"
                                    url = $task.url
                                }
                        }
                    }
                }
                if ($Assign) {
                    $patch = [ordered]@{
                        op    = "replace"
                        path  = "/fields/System.AssignedTo"
                        from  = "null"
                        value = (Get-LocalUser -Name $env:USERNAME).FullName
                    }
                    $patches[$_.Id] += $patch
                    $subtasks |
                        ForEach-Object {
                            $patches.Add($_.Id, @())
                            $patches[$_.Id] += $patch
                        }
                }
                if ($BeginWork) {
                    If ($_.fields.'System.State' -ne 'Done') {
                        $patch= [ordered]@{
                            op    = "replace"
                            path  = "/fields/System.State"
                            from  = "null"
                            value = "Doing"
                        }
                        $patches[$_.Id] += $patch
                        if (($subtasks | Measure-Object).Count -eq 1) {
                            $subtasks |
                                ForEach-Object {
                                     $patches.Add($_.Id, @())
                                     $patches[$_.Id] += [ordered]@{
                                            op    = "replace"
                                            path  = "/fields/System.State"
                                            from  = "null"
                                            value = "Doing"
                                    }
                                }
                        }
                    }
                }
            }

        $patches.Clone().Keys | ForEach-Object { $patches[$_] = $patches[$_] | Where-Object value -ne $null }

        $patches.GetEnumerator() |
            Where-Object { $_.Value.Length -gt 0 } |
            ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.Key, "apply patch: $($_.Value | ConvertTo-Json -Compress)")) {
                    . ${Invoke-RestApi} `
                        -Endpoint "PATCH https://dev.azure.com/{organization}/{project}/_apis/wit/workitems/{id}?api-version=7.0" `
                        -Variables @{ id = $_.Key } `
                        -PatchBody $_.Value
                }
            } |
            ForEach-Object {
                $_.PSObject.TypeNames.Insert(0, 'User.WorkItem')
                $_
            } |
            Sort-Object Id

        if ($Update) {
            $pdfs |
                ForEach-Object Directory |
                Remove-Item -Force -Recurse
        }
    } else {
        $workitems
    }

    if ($Online) {
        $workitems |
            ForEach-Object { $_.url.Replace("/_apis/wit/workItems/", "/_workitems/edit/") } |
            ForEach-Object { Start-Process $_ }
    }
}
end {
    $PSDefaultParameterValues.Remove("ForEach-Object:WhatIf")
}
