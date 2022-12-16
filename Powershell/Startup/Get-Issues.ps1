#Requires -PSEdition Core
[cmdletbinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="IdParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [int[]]
    $Id,

    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="NewParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [switch]
    $New,

    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="TodoParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [switch]
    $ToDo,

    [Parameter(Mandatory=$false,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [switch]
    $Update
)
DynamicParam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Iteration
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
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



    return $RuntimeParameterDictionary
}
begin {
    ${Invoke-RestApi}  = "$PSScriptRoot\Invoke-RestApi.ps1"
    ${Get-Attachments} = "$PSScriptRoot\Get-Attachments.ps1"
    ${New-Attachments} = "$PSScriptRoot\New-Attachments.ps1"
    ${ConvertTo-Pdf}   = "$PSScriptRoot\ConvertTo-Pdf.ps1"
    $PSDefaultParameterValues["ForEach-Object:WhatIf"] = $false
}
process {
    $IterationName = $PSBoundParameters['Iteration']

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
    } elseif ($New -or $ToDo) {
        $query = if ($New) {
                "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Issue'" +
                                                   " AND [System.State] = 'To Do'" +
                                                   " AND [System.ChangedBy] <> @Me " +
                                                   " AND [System.TeamProject] = 'TauOffice'" +
                                                   " AND [System.CreatedDate] >= @StartOfDay - 14"
            } elseif ($ToDo) {
                "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Issue'" +
                                                   " AND [System.State] = 'To Do'" +
                                                   " AND [System.TeamProject] = 'TauOffice'"
            } else {
                throw "State '$State' is not implemented!"
            }
        
        $missing_ids = . ${Invoke-RestApi} `
                -Endpoint "POST https://dev.azure.com/{organization}/{project}/{team}/_apis/wit/wiql?api-version=5.1" `
                -Body @{
                    query = $query
                } |
                ForEach-Object workItems |
                ForEach-Object id
    } elseif ($null -ne $Id) {
        $missing_ids = $Id
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

    $workitems = $downloaded | Where-Object { $_.fields.'System.WorkItemType' -eq "Issue" }

    if ($Update) {
        $workitems |
            . ${Get-Attachments} -Filter ".(docx)$" |
            . ${ConvertTo-Pdf} -OutVariable pdfs

        if ($PSCmdlet.ShouldProcess($workitems.Id, "New-Attachments")) {
            . ${New-Attachments} -Path $pdfs
        }

        $patches = @{}
        $workitems | ForEach-Object { $patches.Add($_.Id, @()) }

        $workitems |
            ForEach-Object {
                $patches[$_.Id] += [ordered]@{
                        op    = "add"
                        path  = "/fields/Microsoft.VSTS.Common.Priority"
                        value = $_.fields.'System.Description' |
                                Select-String -Pattern "Priorität: [^\d]+(\d+)" |
                                ForEach-Object { $_.Matches.Groups[1].Value }

                    }
                $patches[$_.Id] += [ordered]@{
                        op    = "replace"
                        path  = "/fields/System.Title"
                        value = $_.fields.'System.Title' -replace 'Korrektur (auf|aus) Aufgabe (ID )?\d+ \(DevOpsID:\s*(\d+)\s*\)', 'Erweiterung von #$3'
                    }
                $patches[$_.Id] += [ordered]@{
                        op    = "replace"
                        path  = "/fields/System.Description"
                        value = $_.fields.'System.Description' `
                                    -replace 'Korrektur auf Aufgabe ID \d+ \(DevOpsID: (\d+)\)'`
                                           , 'Erweiterung von <a href="https://dev.azure.com/rocom-service/22af98ac-669d-4f9a-b415-3eb69c863d24/_workitems/edit/$1"
                                                          data-vss-mention="version:1.0">#$1</a>'
                    }
            }
        
        $patches.Keys | ForEach-Object { $patches[$_] = $patches[$_] | Where-Object value -ne "" }

        $patches.GetEnumerator() |
            Where-Object { $_.Value.Length -gt 0 } |
            ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.Key, "apply patch: $($_.Value | ConvertTo-Json -Compress)")) {
                    . ${Invoke-RestApi} ` -Endpoint "PATCH https://dev.azure.com/{organization}/{project}/_apis/wit/workitems/{id}?api-version=7.0" `
                        -Variables @{ id = $_.Key } `
                        -PatchBody $_.Value
                }
            }
            
    } else {
        $workitems |
            ForEach-Object {
                [pscustomobject]@{
                    id=             $_.id
                    rev=            $_.rev
                    "System.State"= $_.fields.'System.State'
                    "System.Title"= $_.fields.'System.Title'
                    "System.AssignedTo"=
                                    $_.fields.'System.AssignedTo'.DisplayName
                    "fields"=       $_.fields
                    "relations"=    $_.relations
                    "url"=          $_.url
                }
            }
    }
}
end {
    $PSDefaultParameterValues.Remove("ForEach-Object:WhatIf")
}
