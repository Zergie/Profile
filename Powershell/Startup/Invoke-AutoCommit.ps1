[cmdletbinding()]
param(
)

$secrets = (Get-Content "$PSScriptRoot/../secrets.json" | ConvertFrom-Json).'Invoke-AutoCommit'
$env:OPENAI_API_KEY = $secrets.token
. "C:/GIT/Profile/auto-commit/auto-commit-win-x86_64.exe" --review --quiet
$env:OPENAI_API_KEY = $null
