[cmdletBinding()]
param (
    [Parameter(Mandatory,
               ParameterSetName="OutputParameterSet")]
    [ValidateNotNullOrEmpty()]
    [Alias("Description")]
    [string]
    $ProjectDescription,

    [Parameter(ParameterSetName="UpdateParameterSet")]
    [switch]
    $UpdateCv,

    [Parameter(ParameterSetName="OutputParameterSet")]
    [switch]
    $Silent
)

$ErrorActionPreference = "Break"
$Model = "gpt-5-nano"
$PathToCv = "C:\Dokumente\Dokumente\Lebenslauf_2025.pdf"
$CvFileId = "file-U9H84pJqMGu7j1va454F39"


if ($UpdateCv) {
    # Add-Type -AssemblyName System.IO.Compression.FileSystem
    # $zip = [System.IO.Compression.ZipFile]::OpenRead($PathToCv)
    # try {
    #     $documentXml = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' }
    #     if ($documentXml) {
    #         $stream = $documentXml.Open()
    #         $reader = New-Object System.IO.StreamReader($stream)
    #         $content = $reader.ReadToEnd()
    #         $reader.Close()
    #         $stream.Close()

    #          $CVText = ([xml]$content).SelectNodes("//*[local-name() = 't' and namespace-uri() = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main']").'#text' |
    #             Join-String -Separator " "
    #     } else {
    #         Write-Host -ForegroundColor Red "document.xml not found in the docx file."
    #     }
    # } finally {
    #     $zip.Dispose()
    # }

    Invoke-RestMethod `
        -Method DELETE `
        -Uri "https://api.openai.com/v1/files/$CvFileId" `
        -Headers @{
            "Authorization" = "Bearer $env:OPENAI_API_KEY"
        } | Out-Null

    Invoke-RestMethod `
        -Method POST `
        -Uri "https://api.openai.com/v1/files" `
        -Headers @{
            "Authorization" = "Bearer $env:OPENAI_API_KEY"
        } `
        -Form @{
            "purpose" = "assistants"
            file = Get-Item -Path $PathToCv
        }

    exit 0
}

# $prompt = @"
# Bitte bewerte die Eignung meines Lebenslaufs für das folgende Projekt auf einer Skala von 0 bis 100, wobei 0 bedeutet, dass ich überhaupt nicht geeignet bin, und 100 bedeutet, dass ich perfekt geeignet bin.
# Berücksichtige dabei meine Fähigkeiten, Erfahrungen und Qualifikationen im Vergleich zu den Anforderungen des Projekts.

# Lebenslauf:
# ```
# $CVText
# ```

# Projektbeschreibung:
# ```
# $ProjectDescription
# ```
# "@
$prompt = @"
Bitte bewerte die Eignung meines Lebenslaufs für das folgende Projekt auf einer Skala von 0 bis 100, wobei 0 bedeutet, dass ich überhaupt nicht geeignet bin, und 100 bedeutet, dass ich perfekt geeignet bin.
Berücksichtige dabei meine Fähigkeiten, Erfahrungen und Qualifikationen im Vergleich zu den Anforderungen des Projekts.

Projektbeschreibung:
```
$ProjectDescription
```
"@

if ($ProjectDescription.Length -lt 20) {
    Write-Host -ForegroundColor Red "Project description is too short to evaluate."
} else {
    $response = Invoke-RestMethod `
        -Method POST `
        -Uri "https://api.openai.com/v1/responses" `
        -Headers @{
            "Content-Type" = "application/json"
            "Authorization" = "Bearer $env:OPENAI_API_KEY"
        } `
        -OperationTimeoutSeconds (60 * 5) `
        -Body ([ordered]@{
            "model" = $Model
            "input" = @(
                [ordered]@{
                    "role"    = "user"
                    "content" = @(
                        [ordered]@{"type" = "input_text"; "text" = $prompt}
                    )
                }
                [ordered]@{
                    "role"    = "user"
                    "content" = @(
                        [ordered]@{ "type" = "input_file"; "file_id" = $CvFileId }
                    )
                }
            )
            "max_tool_calls" = 2
            # "max_output_tokens" = 1000
            "store" = $false
        } | ConvertTo-Json -Depth 10)


    $scoreDescription = $response.output.content.text
    $score = $scoreDescription |
        Select-String '(\d{1,3})\s*(von\s*)?\/?\s*100' |
        ForEach-Object { $_.Matches.Groups[1].Value }

    if ($null -eq $score) {
        $score = $scoreDescription |
            Select-String '[:=]\s*(\d{1,3})' |
            ForEach-Object { $_.Matches.Groups[1].Value }
    }


    if (!$Silent) {
        Write-Host "🧍 $($prompt.Substring(0,80))..."
        Write-Host "🤖 Score: $score"
        Write-Host "🤖 $($response.output.content.text)"
    }

    [PSCustomObject]@{
        Score = [int]$score
        Description = $response.output.content.text
    }
}