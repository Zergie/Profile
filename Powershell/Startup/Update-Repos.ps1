[cmdletbinding()]
param(
)

Get-ChildItem -Directory |
    Get-ChildItem -Directory -Filter .git -Force |
    ForEach-Object { $_.Parent } |
    ForEach-Object {
        Write-Host
        Write-Host "cd $($_.FullName) && git pull" -ForegroundColor Cyan
        Push-Location $_
        git pull
        Pop-Location
    }
