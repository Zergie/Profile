[cmdletbinding()]
param(
)
begin {
    function Invoke-Expression2 {
        param([string] $Expression)
        Write-Host -ForegroundColor Cyan $Expression
        Invoke-Expression $Expression
    }

    $data_folder = "C:\Dokumente\Daten\temp"
}
process {

    # FileSystem
    Invoke-Expression2 "Remove-Item -Recurse -Force `"$data_folder`" -ErrorAction SilentlyContinue" | Out-Null
    Invoke-Expression2 "New-Item -ErrorAction SilentlyContinue -ItemType Directory `"$data_folder`"" | Out-Null
    Invoke-Expression2 "New-Item -ErrorAction SilentlyContinue -ItemType Directory `"$data_folder\temp`"" | Out-Null
    Invoke-Expression2 "New-Item -ErrorAction SilentlyContinue -ItemType Directory `"$data_drive\INI\`"" | Out-Null
    Invoke-Expression2 "New-Item -ErrorAction SilentlyContinue -ItemType File      `"$data_drive\INI\Mandant.ini`"" | Out-Null

    # SqlServer
    Invoke-Expression2 "docker ps -a --no-trunc --format json 2> nul" |
        ConvertFrom-json |
        Where-Object {@("mssql", "").Contains($_.Names)} |
        ForEach-Object {
            Invoke-Expression2 "docker stop $($_.ID)" | Out-Null
            Invoke-Expression2 "docker rm $($_.ID)" | Out-Null
        }

    Invoke-Expression2 ". `"$PSScriptRoot\Start-SqlServer.ps1`""
}
