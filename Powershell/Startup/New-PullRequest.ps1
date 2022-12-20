#Requires -PSEdition Core
[CmdletBinding()]
param (
)
Process {
    $sourceRef = git rev-parse --symbolic-full-name HEAD |
                    Select-String "(?:refs/heads/)(.*)" |
                    ForEach-Object { $_.Matches.Groups[1].Value }
    $targetRef = "master"

    $sourceRepositoryId = switch -Regex ((Get-Location).Path) {
        "^C:\\GIT\\TauOffice\\DBMS($|\\.+)" { "9628cf99-3a38-48fd-b4af-ced93fd41111" }
        "^C:\\GIT\\TauOffice($|\\.+)"       { "e4c9e36f-ccf2-4e31-aaa8-df56c116d3a5" }
        default { "e4c9e36f-ccf2-4e31-aaa8-df56c116d3a5" }
    }

#    $lastMessage = git log -1 --pretty=%B
#    if  ($lastMessage -notlike "*Related work items:*") {
#        $workitem = $sourceRef | Select-String -Pattern "\d+$" | ForEach-Object { $_.Matches.Value }
#        @(
#            $lastMessage
#            "Related work items: #$workitem"
#        ) | Out-String -OutVariable message
#        git commit --amend -m $message
#        git push -f
#    }

    $targetRepositoryId = $sourceRepositoryId | Select-Object -First 1
    $url = "https://dev.azure.com/rocom-service/TauOffice/_git/TauOffice/pullrequestcreate?sourceRef=$sourceRef&targetRef=$targetRef&sourceRepositoryId=$sourceRepositoryId&targetRepositoryId=$targetRepositoryId"

    Start-Process $url
}
