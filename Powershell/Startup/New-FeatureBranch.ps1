[CmdletBinding()]
param (
    [Parameter(Mandatory=$false,
        Position=0,
        ParameterSetName="WorkitemIdParameterSet")]
    [string]
    $WorkitemId,

    [Parameter(Mandatory=$false,
        Position=0,
        ParameterSetName="ForceNameParameterSet",
        ValueFromRemainingArguments=$true)]
    [string[]]
    $ForceName
)
dynamicparam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

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
                    query = "SELECT [System.Id] FROM WorkItems WHERE [System.State] <> 'Done' AND [System.WorkItemType] <> 'Task' AND [System.IterationPath] = @currentIteration('[TauOffice]\TauOffice Team <id:48deb8b1-0e33-40d0-8879-71d5258a79f7>')"
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
        ""
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Name", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}
begin {
    # save $PSDefaultParameterValues
    $OldPSDefaultParameterValues = $PSDefaultParameterValues.Clone()
        $PSDefaultParameterValues = @{
            'Write-Error:CategoryActivity' = $MyInvocation.MyCommand.Name
            'Write-Progress:Activity'      = $MyInvocation.MyCommand.Name
        }
}
process {
    $Name = if ($null -ne $ForceName) { $ForceName } 
            elseif ($null -ne $WorkitemId) { $WorkitemId }
            else { $PSBoundParameters['Name'] }
            
    $username = $env:USERNAME
    $issue = $Name | Select-String -Pattern "^(\d+)" | ForEach-Object { $_.Matches.Value }

    $branch = "users/$username/$issue"
    Write-Host -ForegroundColor Cyan "New branch will be $branch"
    
    git checkout master 
    if ($LASTEXITCODE -ne 0) {
        git checkout main
    }

    @(
        "git pull"
        "git checkout -b $branch"
        "git push --set-upstream origin $branch"
    ) | 
        ForEach-Object {
            $cmd = $_
            Write-Host -ForegroundColor Cyan $cmd
            Invoke-Expression $cmd
            if ($LASTEXITCODE -ne 0) {
                Write-Error ""
            }
        }
}
end {
    # restore $PSDefaultParameterValues
    foreach ($key in @($PSDefaultParameterValues.Keys)) {
        if ($key -in $OldPSDefaultParameterValues.Keys) {
            $PSDefaultParameterValues[$key] = $OldPSDefaultParameterValues.$key
        } else {
            $PSDefaultParameterValues.Remove($key)
        }
    }
}