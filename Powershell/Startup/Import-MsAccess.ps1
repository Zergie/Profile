[cmdletbinding()]
param(
    [Parameter(Mandatory = $true,
               ParameterSetName="PathParameterSet",
               ValueFromPipeline = $true,
               ValueFromRemainingArguments = $true,
               HelpMessage="Path to one or more locations.")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Path,

    [Parameter(Mandatory=$false,
               Position=0,
               ParameterSetName="ObjectParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to one or more locations.")]
    [ValidateNotNullOrEmpty()]
    [PSCustomObject[]]
    $InputObject,

    [Parameter()]
    [switch]
    $ShowDiff,

    [Parameter()]
    [switch]
    $Edit
)
begin {
    $pathes = @()
}
process {
    if (($null -eq $Path) -and ($null -eq $InputObject)) {
        $InputObject = Get-GitStatus
    }

    if ($null -ne $Path) {
        $pathes += $Path | Get-ChildItem
    } elseif ($null -ne $InputObject) {
        $pathes += $InputObject | Get-ChildItem -ErrorAction SilentlyContinue
        $pathes += @(
                        $InputObject.Working
                        $InputObject.Index
                    )
                    | Where-Object { $null -ne $_ }
                    | ForEach-Object { [System.IO.Path]::Combine($InputObject.GitDir, "..", $_) }
                    | Where-Object { Test-Path $_ -PathType Leaf }
                    | Get-ChildItem
    }

    Write-Debug "PSBoundParameters: $($PSBoundParameters | ConvertTo-Json)"
    Write-Debug "pathes: $($pathes.FullName | ConvertTo-Json)"
}
end {
    if ($Edit) {
        $arguments = $($pathes | Join-String -Separator " ")
        Write-Debug $arguments
        vi $arguments
    }

    $script = [System.Text.StringBuilder]::new()
    $script.AppendLine() | Out-Null
    $script.AppendLine('dim stdout : set stdout = CreateObject("Scripting.FileSystemObject").GetStandardStream(1)') | Out-Null
    $script.AppendLine('dim application: set application = GetObject(, "Access.Application")') | Out-Null
    $script.AppendLine('dim currentdb: set currentdb = application.CurrentDb()') | Out-Null
    $script.AppendLine('on error resume next') | Out-Null
    $script.AppendLine() | Out-Null

    Write-Host
    foreach ($file in $pathes) {
        Write-Host "Importing $($file.Name) .." -NoNewline
        $warning = ""

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
            ".xml" {
                $warning = "ignored"
            }
            default {
                throw "$($file.Extension) is not implemented"
            }
        }

        Write-Host " $warning" -ForegroundColor Yellow
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
        foreach ($file in $pathes) {
            git --no-pager diff --no-index "$($file.FullName)" "$($file.FullName).old"
            Remove-Item "$($file.FullName).old"
        }
    }
}

