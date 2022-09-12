#Requires -PSEdition Core

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="IdParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [int[]]
    $Id
)
DynamicParam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param State
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.ParameterSetName = "StateParameterSet"
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        "New"
        "ToDo"
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("State", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

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
    New-Alias -Name "Invoke-RestApi" -Value "$PSScriptRoot\Invoke-RestApi.ps1"
}
process {
    $IterationName = $PSBoundParameters['Iteration']
    $State = $PSBoundParameters['State']

    $downloaded = @()
    if ($IterationName -eq "@Current Iteration") { 
        $missing_ids = Invoke-RestApi `
                -Endpoint "POST https://dev.azure.com/{organization}/{project}/{team}/_apis/wit/wiql?api-version=5.1" `
                -Body @{
                    query = "SELECT [System.Id] FROM WorkItems WHERE [System.State] <> 'Done' AND [System.IterationPath] = @currentIteration('[TauOffice]\TauOffice Team <id:48deb8b1-0e33-40d0-8879-71d5258a79f7>')"
                } |
                ForEach-Object workItems |
                ForEach-Object id
    } elseif ($null -ne $IterationName) {
        if ($IterationName -eq "@Newest Iteration") {
            $IterationName = Invoke-RestApi `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=6.0" |
                ForEach-Object value |
                ForEach-Object path |
                Select-Object -Last 1
            Write-Host "Getting Iteration " -NoNewline
            Write-Host -ForegroundColor Magenta $IterationName
        }

        $Iteration = Invoke-RestApi `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=6.0" |
                ForEach-Object value |
                Where-Object Path -eq $IterationName

        $missing_ids = Invoke-RestApi `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/workitems?api-version=6.0-preview.1" `
                -Variables @{ iterationId = $Iteration.Id } |
                ForEach-Object workItemRelations |
                ForEach-Object target |
                ForEach-Object id
    } elseif ($null -ne $State) {
        $query = switch ($State) {
            "New"   { "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Issue' AND [System.CreatedDate] >= @StartOfDay - 14" }
            "ToDo"  { "SELECT [System.Id] FROM WorkItems WHERE [System.WorkItemType] = 'Issue' AND [System.State] = 'To Do'" }
            default { throw "State '$State' is not implemented!" }
        }
        
        $missing_ids = Invoke-RestApi `
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
            $items = Invoke-RestApi `
                        -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/workitems?ids={ids}&`$expand=relations&api-version=6.0" `
                        -Variables @{ ids = ($missing_ids | Select-Object -First 200) -join "," } |
                        ForEach-Object value
            $downloaded += $items
            $missing_ids = $missing_ids | Select-Object -Skip 200
        }
    }

    $workitems = $downloaded | Where-Object { $_.fields.'System.WorkItemType' -eq "Issue" }
    $workitems | 
        ForEach-Object {
            [PSCustomObject]@{
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