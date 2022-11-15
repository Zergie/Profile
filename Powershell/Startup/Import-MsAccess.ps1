[cmdletbinding()]
param(
    [Parameter(Mandatory = $true,
               ValueFromPipeline = $true,
               ValueFromRemainingArguments = $true)]
    [ValidateNotNullOrEmpty()]
    [Alias("PSPath")]
    [Alias("working")]
    [string[]]
    $Path,

    [Parameter()]
    [switch]
    $ShowDiff = $false,

    [Parameter()]
    [switch]
    $Edit
)
begin {
    $files = @()
}
process {
    $files += Get-ChildItem $Path | Select-Object -First 1
}
end {
    if ($Edit) {
        $args = $($files | Join-String -Separator " ")
        Write-Debug $args
        vi $args
    }

    $script = [System.Text.StringBuilder]::new()
    $script.AppendLine() | Out-Null
    $script.AppendLine('dim stdout : set stdout = CreateObject("Scripting.FileSystemObject").GetStandardStream(1)') | Out-Null
    $script.AppendLine('dim application: set application = GetObject(, "Access.Application")') | Out-Null
    $script.AppendLine('dim currentdb: set currentdb = application.CurrentDb()') | Out-Null
    $script.AppendLine('on error resume next') | Out-Null
    $script.AppendLine() | Out-Null

    foreach ($file in $files) {
        switch ($file.Extension) {
            ".ACREF" {
                throw "$($file.Extension) is not (yet) implemented"
            }
            ".ACQ" {
                if ($ShowDiff) { $script.AppendLine("application.SaveAsText   1, `"$($file.BaseName)`", `"$($file.FullName).old`"") | Out-Null }
                $script.AppendLine("application.LoadFromText 1, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
            }
            ".ACF" {
                if ($ShowDiff) { $script.AppendLine("application.SaveAsText   2, `"$($file.BaseName)`", `"$($file.FullName).old`"") | Out-Null }
                $script.AppendLine("application.LoadFromText 2, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
            }
            ".ACR" {
                if ($ShowDiff) { $script.AppendLine("application.SaveAsText   3, `"$($file.BaseName)`", `"$($file.FullName).old`"") | Out-Null }
                $script.AppendLine("application.LoadFromText 3, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
            }
            ".ACS" {
                if ($ShowDiff) { $script.AppendLine("application.SaveAsText   4, `"$($file.BaseName)`", `"$($file.FullName).old`"") | Out-Null }
                $script.AppendLine("application.LoadFromText 4, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
            }
            ".ACM" {
                if ($ShowDiff) { $script.AppendLine("application.SaveAsText   5, `"$($file.BaseName)`", `"$($file.FullName).old`"") | Out-Null }
                $script.AppendLine("application.LoadFromText 5, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
            }
            ".ACT" {
                if ($ShowDiff) { $script.AppendLine("application.ExportXml `"$($file.FullName).old`", 1") | Out-Null }
                $script.AppendLine("currentdb.TableDefs.Delete `"$($file.BaseName)`"") | Out-Null
                $script.AppendLine("application.ImportXml `"$($file.FullName)`", 1") | Out-Null
            }
            default {
                throw "$($file.Extension) is not implemented"
            }
        }
    }

    $script = $script.ToString()
    Set-Content -Path "$($env:TEMP)\script.vbs" -Value $script
    
    $line = 0
    $script -split "`n" |
        ForEach-Object `
            -Begin   { "== vba script ==" } `
            -Process { $line++; $line.ToString().PadRight(3) + $_ } `
            -End     { "== end vba script ==" } |
        Write-Debug
    
    cscript.exe "$($env:TEMP)\script.vbs" //nologo
    Remove-Item "$($env:TEMP)\script.vbs"

    if ($ShowDiff) {
        foreach ($file in $files) {
            git --no-pager diff --no-index "$($file.FullName)" "$($file.FullName).old"
            Remove-Item "$($file.FullName).old"
        }
    }
}

