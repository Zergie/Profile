<#
.SYNOPSIS
    This script will let you have a conversation with ChatGPT.
    It shows how to keep a history of all previous messages and feed them into the REST API in order to have an ongoing conversation.
#>
[cmdletbinding(DefaultParameterSetName="ChatParameterSet")]
param(
    [Parameter(ParameterSetName="ChatParameterSet")]
    [Parameter(ParameterSetName="GitCommitParameterSet")]
    [ValidateSet("gpt-5.1", "gpt-5", "gpt-5 mini", "gpt-5-nano", "gpt-4o-mini")]
    [string]
    $Model = "gpt-5-nano",

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

    [Parameter(ParameterSetName="ChatParameterSet")]
    [switch]
    $IncludeTerminal,

    [Parameter(ParameterSetName="PullRequestParameterSet")]
    [switch]
    $WritePullRequest,

    [Parameter(ParameterSetName="TranslationParameterSet")]
    [switch]
    $WriteTranslation,

    [Parameter(ParameterSetName="TranslationParameterSet",
               ValueFromPipeline)]
    [string[]]
    $Text,


    [Parameter(ParameterSetName="GitCommitParameterSet")]
    [switch]
    $WriteGitCommit
)

function Get-VisibleTerminalText {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]
        $RawUi = $Host.UI.RawUI
    )

    try {
        if ($null -eq $rawUi) {
            throw "The active PowerShell host does not expose RawUI."
        }

        $windowPosition = $rawUi.WindowPosition
        $windowSize = $rawUi.WindowSize
        if ($windowSize.Width -le 0 -or $windowSize.Height -le 0) {
            throw "The active PowerShell host reported an invalid visible window size."
        }

        $rectangle = [System.Management.Automation.Host.Rectangle]::new(
            $windowPosition.X,
            $windowPosition.Y,
            $windowPosition.X + $windowSize.Width - 1,
            $windowPosition.Y + $windowSize.Height - 1
        )
        $cells = $rawUi.GetBufferContents($rectangle)
        if ($null -eq $cells) {
            throw "The active PowerShell host returned no screen-buffer contents."
        }

        $lines = for ($row = 0; $row -lt $windowSize.Height; $row++) {
            $characters = [char[]]::new($windowSize.Width)
            for ($column = 0; $column -lt $windowSize.Width; $column++) {
                $characters[$column] = $cells[$row, $column].Character
            }
            (-join $characters).TrimEnd()
        }

        return $lines -join [Environment]::NewLine
    } catch {
        throw [System.InvalidOperationException]::new(
            "Cannot include terminal context because this PowerShell host cannot read its visible screen buffer. Run the command in a console host that supports RawUI.GetBufferContents(), or omit -IncludeTerminal. No API request was sent.",
            $_.Exception
        )
    }
}

function Add-VisibleTerminalContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $UserMessage
    )

    $terminalText = Get-VisibleTerminalText
    return "[TERMINAL OUTPUT - VISIBLE SCREEN]$([Environment]::NewLine)$terminalText$([Environment]::NewLine)[END TERMINAL OUTPUT]$([Environment]::NewLine)$([Environment]::NewLine)$UserMessage"
}

function Invoke-ChatGPTConversation {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName="ChatParameterSet")]
        [Parameter(ParameterSetName="GitCommitParameterSet")]
        [ValidateSet("gpt-5.1", "gpt-5", "gpt-5 mini", "gpt-5-nano", "gpt-4o-mini")]
        [string]
        $Model = "gpt-5-nano",

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

        [Parameter(ParameterSetName="ChatParameterSet")]
        [switch]
        $IncludeTerminal,

        [Parameter(ParameterSetName="PullRequestParameterSet")]
        [switch]
        $WritePullRequest,

        [Parameter(ParameterSetName="TranslationParameterSet")]
        [switch]
        $WriteTranslation,

        [Parameter(ParameterSetName="TranslationParameterSet",
                   ValueFromPipeline)]
        [string[]]
        $Text,

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
} elseif ($WriteTranslation) {
    $Role = @(
                "You are a helpful assistant that translates text to English."
                "Only respond with the translation and nothing else. Do not include 'Translation:' or any other text."
    )
    $Message = @(
                    "Translate the following text to English: " + $Text
                    "copy"
                )
} elseif ($WriteGitCommit) {
    $Model = "gpt-4o-mini"
    $Role = "Write a commit message for the following git diff. Do not write anything else. Do not include ```. Git diff: {{input}}"
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
        return
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
            return
        }
        "^(c|copy)$" {
            Set-Clipboard $aiResponse
            Write-Host "Copied to clipboard!" -ForegroundColor Magenta
        }
        "^[!]" {
            $aiResponse = $aiResponse.Replace('`', '``').Replace('"','`"')
            $cmd = $userMessage.Substring(1).Replace('$_', "$aiResponse")
            Write-Debug $cmd
            try {
                Invoke-Expression $cmd
            } catch {
                Write-Host -ForegroundColor Yellow $cmd
                throw
            }
        }
        default {
            if ($IncludeTerminal) {
                $userMessage = Add-VisibleTerminalContext -UserMessage $userMessage
            }

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
                    # "max_completion_tokens" = 1000 # Max amount of tokens the AI will respond with
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
        Write-Debug ">: $userMessage"
    } elseif ($Message.Count -ne 0 -and !$Interactive) {
        return
    } else {
        $userMessage = Read-Host "`n>"
    }
}
}

# A transient test module sets this private script variable before dot-sourcing.
# Normal dot-sourced profile invocations do not set it and retain command behavior.
if ($script:InvokeChatGPTImportOnly) {
    return
}

Invoke-ChatGPTConversation @PSBoundParameters
exit
