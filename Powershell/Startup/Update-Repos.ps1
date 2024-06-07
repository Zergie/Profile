[cmdletbinding()]
param(
)

Get-ChildItem -Directory |
    Get-ChildItem -Directory -Filter .git -Force |
    ForEach-Object {
        [pscustomobject]@{
            Directory = $_.Parent
            Origin = $(
            Push-Location $_.Parent
            git remote get-url origin
            Pop-Location
            )
        }
    } |
    Where-Object Origin -NotMatch "^(ssh://git@git3.fsoft.com.vn|https://gitlab.es2000.de)" |
    ForEach-Object { $_.Directory } |
    ForEach-Object {
        Write-Host
        Write-Host "cd $($_.FullName) && git pull" -ForegroundColor Cyan
        Push-Location $_
        git pull
        Pop-Location
    }
