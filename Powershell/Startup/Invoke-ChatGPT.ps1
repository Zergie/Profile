<#
.SYNOPSIS
    This script will let you have a conversation with ChatGPT.
    It shows how to keep a history of all previous messages and feed them into the REST API in order to have an ongoing conversation.
#>
[cmdletbinding()]
param(
    [Parameter(ParameterSetName="ChatParameterSet")]
    [ValidateSet("gpt-4o", "gpt-4", "gpt-4-turbo", "gpt-3.5-turbo")]
    [string]
    $Model = "gpt-4o",

    [Parameter(ParameterSetName="ChatParameterSet",
               ValueFromPipeline)]
    [string[]]
    $Message,

    [Parameter(ParameterSetName="ChatParameterSet")]
    [string]
    $Role = "You are a helpful assistant",

    [Parameter(ParameterSetName="ChatParameterSet")]
    [switch]
    $Interactive,

    [Parameter(ParameterSetName="EMailResponseParameterSet")]
    [switch]
    $WriteEMailResponse,

    [Parameter(ParameterSetName="PullRequestParameterSet")]
    [switch]
    $WritePullRequest,

    [Parameter(ParameterSetName="GitCommitParameterSet")]
    [switch]
    $WriteGitCommit
)
if ($WritePullRequest) {
    $Role = "Write a short pull request with title and bullet points. Do not include 'Title' or 'Bullet Points'. It should summerizes the given commits"
    $Message = @(
                    git blog |
                            Select-String '(?<=[^-]- )[^(]+' -AllMatches |
                            ForEach-Object{$_.Matches.Value} |
                            Join-String -Separator `n
                    "copy"
                )
} elseif ($WriteEMailResponse) {
    $Role = "Write a friendly and professional e-mail response. Do not thank for the e-mail. Do not summerize the e-mail. Simply respond."
    $Message = @(
                    Get-Clipboard |
                    Join-String -Separator `n
                )
} elseif ($WriteGitCommit) {
    $json =Get-Content C:\git\Profile\neovim\lua\user\chatgpt.json | ConvertFrom-Json
    $Role = $json.commit.opts.template
    $Model = $json.commit.opts.params.model
    $commit = git diff --staged -B -M | Join-String -Separator `n
    if ($commit.Length -gt 100000) {
        $commit = git diff --staged -B -M --numstat | Join-String -Separator `n
    }
    $Message = @(
                    $commit
                    '!git commit -m "$_"'
                )
}

$ApiEndpoint = "https://api.openai.com/v1/chat/completions"
$ApiKey = $env:OPENAI_API_KEY
$userMessage = "reset"

# we use this list to store the system message and will add any user prompts and ai responses as the conversation evolves.
$MessageHistory = [System.Collections.Generic.List[Hashtable]]::new()
$MessageStack = [System.Collections.Generic.Stack[string]]::new()

if ($Message.Count -gt 0) {
    [Array]::Reverse($Message)
    $Message | ForEach-Object { $MessageStack.Push($_) }
}

# Main loop
while ($true) {
    # Check if user wants to exit or reset
    switch -Regex ($userMessage){
        "^(r|reset)$" {
            Write-Host "Enter your prompt to continue. (type 'exit' to quit, 'copy' to copy or 'reset' to start a new chat)"

            # Reset the message history so we can start with a clean slate
            $MessageHistory.Clear()
            $MessageHistory.Add(@{"role" = "system"; "content" = $Role}) | Out-Null
        }
        "^$" { }
        "^(q|exit)$" {
            Write-Host "Exiting.." -ForegroundColor Magenta
            exit
        }
        "^(c|copy)$" {
            Set-Clipboard $aiResponse
            Write-Host "Copied to clipboard!" -ForegroundColor Magenta
        }
        "^[!]" {
            $cmd = $userMessage.Substring(1).Replace('$_', "$aiResponse")
            Invoke-Expression $cmd
        }
        default {
            # Add new user prompt to list of messages
            $MessageHistory.Add(@{"role"="user"; "content"=$userMessage})

            # Query ChatGPT
            $response = Invoke-RestMethod `
                -Method POST `
                -Uri $ApiEndpoint `
                -Headers @{
                    "Content-Type" = "application/json"
                    "Authorization" = "Bearer $ApiKey"
                } `
                -Body (@{
                    "model" = $Model
                    "messages" = $MessageHistory
                    "max_tokens" = 1000 # Max amount of tokens the AI will respond with
                    "temperature" = 0.7 # Lower is more coherent and conservative, higher is more creative and diverse.
                } | ConvertTo-Json)

            $aiResponse = $response.choices[0].message.content

            # Show response
            if ($Message.Count -ne 0 -and !$Interactive) {
                Write-Output $aiResponse
            } else {
                Write-Host $aiResponse -ForegroundColor Magenta
            }

            # Add ChatGPT response to list of messages
            $MessageHistory.Add(@{"role"="assistant"; "content"=$aiResponse})
        }
    }

    # Capture user input
    if ($MessageStack.Count -ne 0) {
        $userMessage = $MessageStack.Pop()
        Write-Host ">: $userMessage" -ForegroundColor Yellow
    } elseif ($Message.Count -ne 0 -and !$Interactive) {
        exit
    } else {
        $userMessage = Read-Host "`n>"
    }
}
