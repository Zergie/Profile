[cmdletbinding()]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [ValidateNotNullOrEmpty()]
    [Alias("PSPath")]
    [Alias("working")]
    [string[]]
    $Path
)
begin {
    $script = [System.Text.StringBuilder]::new()
    $script.AppendLine() | Out-Null
    $script.AppendLine('dim stdout : set stdout = CreateObject("Scripting.FileSystemObject").GetStandardStream(1)') | Out-Null
    $script.AppendLine('dim application: set application = GetObject(, "Access.Application")') | Out-Null
    $script.AppendLine('dim currentdb: set currentdb = application.CurrentDb()') | Out-Null
    $script.AppendLine() | Out-Null
}
process {
    $file = Get-ChildItem $Path | Select-Object -First 1

    switch ($file.Extension) {
        ".ACREF" {
            throw "$($file.Extension) is not (yet) implemented"
        }
        ".ACQ" {
            $script.AppendLine("application.LoadFromText 1, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
        }
        ".ACF" {
            $script.AppendLine("application.LoadFromText 2, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
        }
        ".ACR" {
            $script.AppendLine("application.LoadFromText 3, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
        }
        ".ACS" {
            $script.AppendLine("application.LoadFromText 4, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
        }
        ".ACM" {
            $script.AppendLine("application.LoadFromText 5, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
        }
        ".ACT" {
            $script.AppendLine("currentdb.TableDefs.Delete `"$($file.BaseName)`"") | Out-Null
            $script.AppendLine("application.ImportXml `"$($file.FullName)`", 1") | Out-Null
        }
        default {
            throw "$($file.Extension) is not implemented"
        }
    }
}
end {
    Write-Debug $script.ToString()

function Invoke-VBScript {
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $script
    )
    $path = "$($env:TEMP)\script.vbs"
    Set-Content -Path "$path" -Value $script
    
    $line = 0
    $script -split "`n" |
        ForEach-Object `
            -Begin   {"== vba script ==" } `
            -Process {
                $line++
                $line.ToString().PadRight(3) + $_.ToString()
             } `
            -End     { "== end vba script ==" } |
        Write-Verbose
    
    cscript.exe "$path" //nologo
    Remove-Item "$path"
}

    Invoke-VBScript $script.ToString()
}

