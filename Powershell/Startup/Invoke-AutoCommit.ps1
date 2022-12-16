[cmdletbinding()]
param(
)

$secrets = (Get-Content "$PSScriptRoot/../../secrets/secrets.json" | ConvertFrom-Json).'Invoke-AutoCommit'
$env:OPENAI_API_KEY = $secrets.token
. "$PSScriptRoot/../../auto-commit/auto-commit-win-x86_64.exe" --review
$env:OPENAI_API_KEY = $null
