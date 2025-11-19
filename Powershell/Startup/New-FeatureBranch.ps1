[CmdletBinding()]
param (
    [Parameter(Position=0, ParameterSetName="WorkitemIdParameterSet")]
    [Parameter()]
    [string]
    $WorkitemId,

    [Parameter(ParameterSetName="ForceNameParameterSet")]
    [Parameter()]
    [string]
    $ForceName,

    [Parameter()]
    [switch]
    $DoNotStart,

    [Parameter()]
    [switch]
    $BaseOnThisBranch
)
dynamicparam {
    Set-Alias "New-DynamicParameter" "$PSScriptRoot\New-DynamicParameter.ps1"
    Set-Alias "Invoke-RestApi" "$PSScriptRoot\Invoke-RestApi.ps1"
    @(
        [pscustomobject]@{
            Position = 0
            Type = [string]
            Name = "Name"
            ParameterSetName = "NameParameterSet"
            ValidateSet = Invoke-RestApi `
                -Endpoint "POST https://dev.azure.com/{organization}/{project}/_apis/wit/workitemsbatch?api-version=7.0" `
                -Body @{
                    ids= @() + (Invoke-RestApi `
                            -Endpoint "POST https://dev.azure.com/{organization}/{project}/{team}/_apis/wit/wiql?api-version=7.0" `
                            -Body @{ query = "SELECT [System.Id] FROM WorkItems WHERE [System.State] <> 'Done' AND [System.WorkItemType] <> 'Task' AND [System.IterationPath] = @currentIteration('[TauOffice]\TauOffice Team <id:48deb8b1-0e33-40d0-8879-71d5258a79f7>')" }).workItems.id
                    fields= @(
                        "System.Id"
                        "System.Title"
                     )
                } |
                ForEach-Object value |
                ForEach-Object fields |
                ForEach-Object { "$($_.'System.Id') - $($_.'System.Title')" } |
                Sort-Object
        }
        [pscustomobject]@{
            Position = 1
            Type = [string]
            Name = "Branch"
            ValidateSet = git branch --list | Select-String "release(/[^/ ]+)+" |ForEach-Object {$_.Matches.Value}
        }
    ) | New-DynamicParameter
}
begin {
}
process {

    $Name = if ($ForceName.Length -gt 0) { $ForceName }
            elseif ($WorkitemId.Length -gt 0) { $WorkitemId }
            else { $PSBoundParameters['Name'] }

    $username = $env:USERNAME
    $issue = $Name | Select-String -Pattern "^(\d+)" | ForEach-Object { $_.Matches.Value }

    if ($BaseOnThisBranch) {
        $branch = "users/$username/$issue-on-$((git rev-parse --abbrev-ref HEAD).Replace('/','-'))"
    } else {
        $branch = "users/$username/$issue"
    }

    Write-Host -ForegroundColor Cyan "Branch will be $branch"

    if (!$BaseOnThisBranch) {
        git checkout master
        if ($LASTEXITCODE -ne 0) {
            git checkout main
        }
    }

    @(
        if ($branch -in $(git branch --no-color | ForEach-Object { $_.trim(' ', '*')})) {
            "git checkout $branch"
        } else {
            "git pull"
            "git checkout -b $branch"
            "git push --set-upstream origin $branch"
        }
        if (!$DoNotStart) { "Get-Issues -WorkitemId $issue -Pdf -BeginWork" }
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
}
