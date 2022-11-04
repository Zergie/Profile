[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments")]
param(
)
Push-Location $PSScriptRoot

$choices = if (!(Test-Path choices.json)) {
    @{}
} else {
    Get-Content choices.json |
        ConvertFrom-Json |
        ForEach-Object { $_.psobject.properties } |
        ForEach-Object `
            -Begin   { $h=@{} } `
            -Process { $h."$($_.Name)" = $_.Value } `
            -End     { $h }
}

[System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
$fonts = (New-Object System.Drawing.Text.InstalledFontCollection).Families |
            Where-Object { ($_ -like "* NFM*") }

Clear-Host
Write-Host "options: q / n / y"

foreach ($font in $fonts.Name) {
    git restore ./settings.json

    $choice = if ($choices.ContainsKey($font)) {
        $choices[$font]
    } else {
        "?"
    }
    
    switch ($choice) {
        "n" { }
        default {
            Write-Host
            Write-Host "$font -> $choice" -NoNewline

            (Get-Content .\settings.json |Out-String) -split "`n" |
                ForEach-Object { $_.TrimEnd() } |
                ForEach-Object {
                    if ($_ -like "*`"face`": *") {
                        "                `"face`": `"$font`","
                    } else {
                        $_
                    }
                } |
                Set-Content .\settings.json

            $choice = $host.ui.RawUI.ReadKey().Character
            switch ($choice) {
                "q" { exit }
            }
            $choices[$font] = $choice
            $choices | ConvertTo-Json | Set-Content choices.json
        }
    }
}

Pop-Location
