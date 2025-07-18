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
    $WriteGitCommit,

    [Parameter(ParameterSetName="JobApplicationParameterSet")]
    [ValidateScript({
        if ($_ -match 'https?://www.freelancermap.de') {
            return $true
        } else {
            throw "Please provide a valid freelancermap.de URL."
        }
    })]
    [string]
    $WriteJobApplication
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
    $binaryonly = (git diff --staged --name-only |
        Where-Object { ! $_.EndsWith(".pdf") } |
        Measure-Object
        ).Count -eq 0
    $commit = git diff --staged -B -M | Join-String -Separator `n
    if ($binaryonly -or $commit.Length -gt 30000) {
        $commit = git diff --staged -B -M --name-status | Join-String -Separator `n
    }
    if ($commit.Length -eq 0) {
        Write-Host -ForegroundColor Red "Could not write a commit message. Are there staged files?"
        exit
    }
    $Message = @(
                    $commit
                    '!git commit -m "$_"'
                )
} elseif ($WriteJobApplication.Length -gt 0) {
    $Role = "Wir schreiben eine bewerbung auf ein Projekt als freelancer:"
    $html = ConvertFrom-HTML -Engine AngleSharp -Url $WriteJobApplication

    $text = $html.QuerySelector(".card").QuerySelectorAll("dt").TextContent | 
        ForEach-Object { [pscustomobject]@{Name=$_.Trim(@(" ", ":")); Value=$null}}
    $i  =0
    $html.QuerySelector(".card").QuerySelectorAll("dd") | 
        ForEach-Object{
            $text[$i].Value = $_.TextContent.Split() | Where-Object Length -gt 0 | Join-String -Separator " "
            $i+=1 
        }
    

    $Message = @(
                    # "Mein Lebenslauf:"
                    # Get-PdfRender C:\Dokumente\Dokumente\Lebenslauf_2025.pdf -As txt | ForEach-Object Converted
                    # ""
                    "Titel:"
                    $($html.QuerySelector("*[data-translatable=title]").TextContent.Trim())
                    $text.GetEnumerator() | ForEach-Object { "$($_.Name):`n$($_.Value)`n"}
                    $html.QuerySelector("*[data-translatable=description]").TextContent.Trim()
                ) | Out-String
    
    $Message | Set-Clipboard
    Write-Host "Copied to clipboard!" -ForegroundColor Magenta
    Start-Process "https://chatgpt.com/c/670641eb-0890-800c-80ce-f87c1b0dee69"
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
            if ($Message.Count -eq 0) {
                Write-Host "Enter your prompt to continue. (type 'exit' to quit, 'copy' to copy or 'reset' to start a new chat)"
            }

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
            $aiResponse = $aiResponse.Replace('`', '``').Replace('"','`"')
            $cmd = $userMessage.Substring(1).Replace('$_', "$aiResponse")
            Write-Debug $cmd
            Write-Host -ForegroundColor Yellow $cmd
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
