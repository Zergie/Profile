#Requires -PSEdition Core
[CmdletBinding()]
param (
)
dynamicparam {
    Set-Alias "New-DynamicParameter" "$PSScriptRoot\New-DynamicParameter.ps1"
    Set-Alias "Invoke-RestApi" "$PSScriptRoot\Invoke-RestApi.ps1"
    @(
        [pscustomobject]@{
            Position = 0
            Type = [string[]]
            Name = "Issues"
            ParameterSetName = "IssuesParameterSet"
            ValidateSet = Invoke-RestApi `
                -Endpoint "POST https://dev.azure.com/{organization}/{project}/_apis/wit/workitemsbatch?api-version=7.0" `
                -Body @{
                    ids= @() + (Invoke-RestApi `
                            -Endpoint "POST https://dev.azure.com/{organization}/{project}/{team}/_apis/wit/wiql?api-version=7.0" `
                            -Body @{ query = "SELECT [System.Id] FROM WorkItems WHERE [System.State] == 'Doing' AND [System.WorkItemType] <> 'Task' AND [System.IterationPath] = @currentIteration('[TauOffice]\TauOffice Team <id:48deb8b1-0e33-40d0-8879-71d5258a79f7>')" }).workItems.id
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
    ) | New-DynamicParameter
}
begin {
    $Issues = $PSBoundParameters['Issues']
}
process {
    $sourceRef = git rev-parse --symbolic-full-name HEAD |
                    Select-String "(?:refs/heads/)(.*)" |
                    ForEach-Object { $_.Matches.Groups[1].Value }
    $targetRef = git log --color --graph --pretty=format:'%C(auto)%h%C(reset) - %s%C(auto)%d%C(reset)' --abbrev-commit -40 |
                    Select-String "origin/(master|main|release/[\d-]+)\b" |
                    ForEach-Object { $_.Matches.Groups[1].Value } |
                    Select-Object -First 1

    if ($sourceRef -match ("^(main|master|release/)")) {
        throw "Can not create a pull request for $sourceRef"
    }

    $sourceRepositoryUrl = (git ls-remote --get-url origin).Trim()
    $sourceRepositoryId = . "$PSScriptRoot\Invoke-RestApi.ps1" `
        -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/git/repositories?api-version=7.0" |
            ForEach-Object value |
            Where-Object remoteUrl -EQ $sourceRepositoryUrl |
            ForEach-Object id

    # $sourceRepositoryId = switch -Regex ((Get-Location).Path) {
    #     "^C:\\GIT\\TauOffice\\DBMS($|\\.+)" { "9628cf99-3a38-48fd-b4af-ced93fd41111" }
    #     "^C:\\GIT\\TauOffice($|\\.+)"       { "e4c9e36f-ccf2-4e31-aaa8-df56c116d3a5" }
    #     "^C:\\GIT\\TauServer($|\\.+)"       { "79497b7c-776d-4a4b-ab8c-848b132137b6" }
    #     default { "e4c9e36f-ccf2-4e31-aaa8-df56c116d3a5" }
    # }

    $lastMessage = git log -1 --pretty=%B
    if ($null -ne $Issues) {
        $workitem = $sourceRef | Select-String -Pattern "\d+$" | ForEach-Object { $_.Matches.Value }
        @(
            $lastMessage
            $Issues |
                Select-String -Pattern "^(\d+)" |
                ForEach-Object { $_.Matches.Value } |
                ForEach-Object { "Related work items: #$_" } |
                Where-Object { $_ -notin $lastMessage }
        ) | Out-String -OutVariable message
        git commit --amend -m $message
        git push -f
    } elseif (($lastMessage|Join-String -Separator ' ') -notlike '*Related work items:*') {
        $workitem = $sourceRef | Select-String -Pattern "\d+$" | ForEach-Object { $_.Matches.Value }
        if ($workitem.Length -gt 0) {
            @(
                $lastMessage
                "Related work items: #$workitem"
            ) | Out-String -OutVariable message
            git commit --amend -m $message
        }
        git push -f
    } else {
        git push
    }

    $targetRepositoryId = $sourceRepositoryId | Select-Object -First 1
    $url = "https://$((git config --get remote.origin.url) -split "@" | Select-Object -Last 1)/pullrequestcreate?sourceRef=$sourceRef&targetRef=$targetRef&sourceRepositoryId=$sourceRepositoryId&targetRepositoryId=$targetRepositoryId"

    Start-Process $url

    if ($sourceRef -match "^users/[^/]+/\d+") {
        # Push-Location $PSScriptRoot
        # $workitem = ./Get-Issues.ps1 -Id ($sourceRef.Split("/") | Select-Object -Last 1)
        #
        # $ids = ./Get-Issues.ps1 -Iteration $workitem.fields.'System.IterationPath' |
        #     ForEach-Object Id
        #
        # $iterationPath = ./Invoke-RestApi `
        #     -Endpoint 'GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=7.0' |
        #         ForEach-Object value |
        #         Where-Object path -EQ $workitem.fields.'System.IterationPath'
        #
        # $daysOff = ./Invoke-RestApi `
        #         -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/capacities?api-version=7.1-preview.3" `
        #         -Variables @{ iterationId = $iteration.Id } |
        #         ForEach-Object daysOff
        #
        #
        # $iteration
        # 0 .. ($iteration.attributes.finishDate - $iteration.attributes.startDate).Days |
        #     ForEach-Object { $iteration.attributes.startDate.AddDays($_) } |
        #
        # $page = ./Invoke-RestApi.ps1 `
        #     -Endpoint 'GET https://dev.azure.com/{organization}/{project}/_apis/wit/reporting/workitemrevisions?startDateTime={startDateTime}&fields={fields}&api-version=7.0' `
        #     -Variables @{
        #             startDateTime = $iteration.attributes.startDate.ToString("yyyy-MM-dd")
        #             fields = "System.Id,Microsoft.VSTS.Scheduling.Effort,System.ChangedDate,System.State"
        #     }
        # $items = $page.values
        # while (!$page.isLastBatch -and $null -eq $page.nextLink) {
        #     $page = ./Invoke-RestApi.ps1 -Endpoint "GET $($page.nextLink)"
        #     $items += $page.values
        # }
        # $items |
        #     Where-Object id -in $ids |
        #     Group-Object { $_.fields.'System.ChangedDate'.Date }
        #
        # Pop-Location
    }
}
