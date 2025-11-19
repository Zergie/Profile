[cmdletbinding()]
param (
    [string]
    $Path = ".",

    [string[]]
    $Extensions = @('.cs','.acm','.acf','.acr','.bas','.cls','.xaml')
)

$Path = (Resolve-Path $Path).Path

$sum = 0
Get-ChildItem -Recurse -File -Path $Path |
    Where-Object Extension -In $Extensions |
    ForEach-Object {
        $f = $_
        if ($f.FullName -notmatch "\\(obj|bin)\\") {
            switch -regex ($f.Extension) {
                "^.ac[rf]$" {
                    $found = $false

                    $lines = (Get-Content $f |
                        ForEach-Object {
                            if ($found) {
                                $_
                            } elseif ($_ -match "CodeBehindForm") {
                                $found = $true
                            }
                        }).Count
                }
                Default {
                    $lines = (Get-Content $f).Count
                }
            }

            [PSCustomObject]@{
                FullName = $f.FullName.Substring($Path.Length).TrimStart('\')
                Lines    = $lines
            }
            $sum += $lines
        }
    }

Write-Host "Total lines of code: $($sum.ToString("0,000"))"