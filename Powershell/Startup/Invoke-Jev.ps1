#Requires -Version 7.0
<#
.SYNOPSIS
    Evaluate content with TypeSafe Jev and return structured decisions.
.DESCRIPTION
    Message (also State or Text) is the content to evaluate. Role (also Question
    or Instructions) defines a Noul, Choice or Score question. Use Questions for
    several named questions in a single request. Pipeline lines are joined into
    one state. Interactive inputs are evaluated independently, without history.

    Authentication uses TYPESAFE_API_KEY first, then Invoke-Jev.token in the
    profile's secrets/secrets.json. No key is written to the output.
    Unlike Invoke-ChatGPT, Jev does not generate translations, commits or PR text.
.PARAMETER Criteria
    Choice: a dictionary mapping option names to descriptions.
    Score: an ordered array of at least two rubric levels.
    Noul: an optional dictionary with 'true' and 'false' descriptions.
.PARAMETER Raw
    Return the complete response, including model and usage, instead of answers.
.PARAMETER IncludeTerminal
    Include the visible terminal buffer in the state sent to TypeSafe.
.EXAMPLE
    Invoke-Jev -Message 'Remote PowerShell project' -Role 'Is this about PowerShell?'
.EXAMPLE
    Get-Content project.txt | Invoke-Jev -Role 'Which work arrangement is offered?' -QuestionType Choice -Criteria @{ remote = 'Fully remote'; onsite = 'On site'; unknown = 'Not specified' }
.EXAMPLE
    Invoke-Jev -Interactive -Role 'How well does this fit PowerShell automation?' -QuestionType Score -Criteria @('No fit', 'Partial fit', 'Strong fit')
.EXAMPLE
    Invoke-Jev -Message 'Project description' -Questions @{ remote = @{ type = 'noul'; instructions = 'Is this fully remote?' }; fit = @{ type = 'score'; instructions = 'Fit for PowerShell automation'; criteria = @('Poor', 'Good') } } -Raw
.LINK
    https://docs.typesafe.ai/api/system-one
#>
[CmdletBinding(DefaultParameterSetName = 'Single')]
param(
    [ValidateNotNullOrEmpty()]
    [string] $Model = 'jev-latest',

    [Parameter(ValueFromPipeline)]
    [Alias('State', 'Text')]
    [string[]] $Message,

    [Parameter(Mandatory, ParameterSetName = 'Single')]
    [Alias('Question', 'Instructions')]
    [ValidateNotNullOrEmpty()]
    [string] $Role,

    [Parameter(ParameterSetName = 'Single')]
    [ValidateSet('Noul', 'Choice', 'Score')]
    [string] $QuestionType = 'Noul',

    [Parameter(ParameterSetName = 'Single')]
    [object] $Criteria,

    [Parameter(Mandatory, ParameterSetName = 'Multiple')]
    [ValidateNotNullOrEmpty()]
    [System.Collections.IDictionary] $Questions,

    [switch] $Interactive,
    [switch] $IncludeTerminal,
    [switch] $Raw,

    [ValidateNotNullOrEmpty()]
    [string] $SecretsPath = (Join-Path $PSScriptRoot '../../secrets/secrets.json'),

    [ValidateRange(1, 3600)]
    [int] $TimeoutSec = 120
)

begin {
    $messages = [System.Collections.Generic.List[string]]::new()

    function Test-JevQuestions {
        param([System.Collections.IDictionary] $Definitions)

        if ($Definitions.Count -eq 0) { throw 'Questions must contain at least one named question.' }
        foreach ($name in $Definitions.Keys) {
            $question = $Definitions[$name]
            if ([string]::IsNullOrWhiteSpace([string]$name) -or
                $question -isnot [System.Collections.IDictionary]) {
                throw 'Each question must have a nonempty name and a dictionary definition.'
            }
            if ($question['type'] -cnotin @('noul', 'choice', 'score')) {
                throw "Question '$name' must use type noul, choice or score."
            }
            if ($null -eq $question['instructions'] -or
                ($question['instructions'] -is [string] -and [string]::IsNullOrWhiteSpace($question['instructions']))) {
                throw "Question '$name' needs instructions."
            }
            switch ($question['type']) {
                'choice' {
                    if ($question['criteria'] -isnot [System.Collections.IDictionary] -or $question['criteria'].Count -lt 2) {
                        throw "Choice question '$name' needs a criteria dictionary with at least two options."
                    }
                }
                'score' {
                    if ($question['criteria'] -isnot [array] -or $question['criteria'].Count -lt 2 -or $question['criteria'].Count -gt 10) {
                        throw "Score question '$name' needs an ordered criteria array with two to ten levels."
                    }
                }
                'noul' {
                    if ($null -ne $question['criteria'] -and $question['criteria'] -isnot [System.Collections.IDictionary]) {
                        throw "Noul question '$name' criteria must be a dictionary."
                    }
                }
            }
        }
    }

    function Get-JevTerminalText {
        try {
            $rawUi = $Host.UI.RawUI
            $position = $rawUi.WindowPosition
            $size = $rawUi.WindowSize
            if ($size.Width -le 0 -or $size.Height -le 0) { throw 'Invalid visible window size.' }
            $rectangle = [System.Management.Automation.Host.Rectangle]::new(
                $position.X, $position.Y, $position.X + $size.Width - 1, $position.Y + $size.Height - 1
            )
            $cells = $rawUi.GetBufferContents($rectangle)
            if ($null -eq $cells) { throw 'No terminal buffer available.' }
            $lines = for ($row = 0; $row -lt $size.Height; $row++) {
                $characters = for ($column = 0; $column -lt $size.Width; $column++) {
                    $cells[$row, $column].Character
                }
                (-join $characters).TrimEnd()
            }
            $lines -join [Environment]::NewLine
        } catch {
            throw 'Cannot read the visible terminal buffer. Omit -IncludeTerminal. No API request was sent.'
        }
    }

    if ($PSCmdlet.ParameterSetName -eq 'Single') {
        $definition = @{ type = $QuestionType.ToLowerInvariant(); instructions = $Role }
        if ($PSBoundParameters.ContainsKey('Criteria')) { $definition.criteria = $Criteria }
        $Questions = @{ result = $definition }
    }
    Test-JevQuestions $Questions
}

process {
    foreach ($line in $Message) { $messages.Add($line) }
}

end {
    $state = $messages -join [Environment]::NewLine
    if (-not $Interactive -and [string]::IsNullOrWhiteSpace($state)) {
        throw 'Supply -Message, pipeline input, or -Interactive.'
    }

    $apiKey = $env:TYPESAFE_API_KEY
    if ([string]::IsNullOrWhiteSpace($apiKey) -and (Test-Path -LiteralPath $SecretsPath)) {
        try {
            $secrets = Get-Content -LiteralPath $SecretsPath -Raw -Encoding utf8 -ErrorAction Stop |
                ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $entry = $secrets['Invoke-Jev']
            if ($entry -is [System.Collections.IDictionary]) { $apiKey = $entry['token'] }
        } catch {
            throw 'Cannot read Invoke-Jev.token from SecretsPath. Check the file or set TYPESAFE_API_KEY.'
        } finally {
            $secrets = $null
            $entry = $null
        }
    }
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'Set TYPESAFE_API_KEY or add Invoke-Jev.token to SecretsPath.'
    }

    try {
        while ($true) {
            if ([string]::IsNullOrWhiteSpace($state)) {
                $state = Read-Host 'State (exit to quit)'
                if ($state -match '^(q|exit)$') { break }
                if ([string]::IsNullOrWhiteSpace($state)) { continue }
            }
            $requestState = $state
            if ($IncludeTerminal) {
                $terminalText = Get-JevTerminalText
                $requestState = "[TERMINAL OUTPUT - VISIBLE SCREEN]`n$terminalText`n[END TERMINAL OUTPUT]`n`n$state"
            }
            $body = @{ model = $Model; state = $requestState; questions = $Questions } |
                ConvertTo-Json -Depth 100 -Compress -WarningAction Stop
            try {
                $response = Invoke-RestMethod -Method Post -Uri 'https://api.typesafe.ai/v1/systemone' `
                    -Headers @{ Authorization = "Bearer $apiKey" } `
                    -ContentType 'application/json; charset=utf-8' `
                    -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
                    -TimeoutSec $TimeoutSec -ErrorAction Stop -Verbose:$false -Debug:$false
            } catch {
                # Do not forward request headers, response bodies or credential-bearing exceptions.
                $status = 0
                $responseProperty = $_.Exception.PSObject.Properties['Response']
                if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {
                    $status = [int]$responseProperty.Value.StatusCode
                }
                $hint = switch ([int]$status) {
                    401 { 'Check the API key.' }
                    402 { 'Check available credits in the TypeSafe console.' }
                    422 { 'Check question definitions and criteria.' }
                    429 { 'Rate limit reached; retry later.' }
                    529 { 'TypeSafe is overloaded; retry later.' }
                    default { 'Check connectivity, credits and request parameters.' }
                }
                throw "TypeSafe request failed (HTTP $([int]$status)). $hint"
            }
            if ($null -eq $response -or $null -eq $response.PSObject.Properties['answers']) {
                throw 'TypeSafe returned no answers.'
            }
            if ($Raw) { Write-Output $response } else { Write-Output $response.answers }
            if (-not $Interactive) { break }
            $state = ''
        }
    } finally {
        $apiKey = $null
    }
}
