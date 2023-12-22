<#
.SYNOPSIS
    This script will let you have a conversation with ChatGPT.
    It shows how to keep a history of all previous messages and feed them into the REST API in order to have an ongoing conversation.
#>
[cmdletbinding()]
param(
    # User message.
    # You can use this to give the AI instructions on what to do, how to act or how to respond to future prompts.
    # If a message is defined, the script will run non interactive.
    [Parameter()]
    [string[]]
    $Message,

    # System message.
    # You can use this to give the AI instructions on what to do, how to act or how to respond to future prompts.
    # Default value for ChatGPT = "You are a helpful assistant."
    [Parameter()]
    [string]
    $Role = "You are a helpful assistant",

    # Forces interactive behaviour
    [Parameter()]
    [switch]
    $Interactive
)

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
        "^reset$" {
            if ($Message.Count -eq 0) {
                # Show startup text
                Write-Host "Enter your prompt to continue. (type 'exit' to quit or 'reset' to start a new chat)"
            }

            # Reset the message history so we can start with a clean slate
            $MessageHistory.Clear()
            $MessageHistory.Add(@{"role" = "system"; "content" = $Role}) | Out-Null
        }
        "^$" { }
        "^(q|exit)$" { exit }
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
                    "model" = "gpt-3.5-turbo"
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
