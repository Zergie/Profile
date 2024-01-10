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
    $Edit,

    [Parameter()]
    [switch]
    $Compile,

    [Parameter()]
    [switch]
    $Force
)
begin {
    $pathes = @()

    function Invoke-VbScript {
        param($script)
        $script = $script.ToString()

        Set-Content -Path "$($env:TEMP)\script.vbs" -Value $script

        $line = 0
        $script -split "`n" |
            ForEach-Object `
                -Begin   { "== vba script ==" } `
                -Process { $line++; $line.ToString().PadRight(3) + $_ } `
                -End     { "== end vba script ==" } |
            Write-Debug

        $wshell = New-Object -ComObject wscript.shell
        $wshell.AppActivate(((Get-Process MSACCESS).MainWindowTitle)) | Out-Null
        cscript.exe "$($env:TEMP)\script.vbs" //nologo
        Remove-Item "$($env:TEMP)\script.vbs"

    }
}
process {
    if (($null -eq $Path) -and ($null -eq $InputObject)) {
        $InputObject = Get-GitStatus
    }

    if ($null -ne $Path) {
        $pathes += $Path |
            ForEach-Object { if ($_.StartsWith("file://")) { $_.Substring(8) } else { $_ }} |
            Get-ChildItem
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

    $pathes = $pathes |
        Group-Object |
        ForEach-Object { $_.Group[0] } |
        Where-Object Extension -NE ".old"

    $ignored = $()
    foreach ($file in $pathes) {
        $warning = ""

        switch -regex ($file.Extension) {
            "^\.(ACQ|ACF|ACR|ACM|ACS|ACT)$" { }
            "^\.(ACREF)$" {
                throw "$($file.Extension) is not (yet) implemented"
            }
            "^\.(xml|pfx)$" {
                $ignored += @($file)
                $warning = "ignored"
            }
            default {
                Write-Host " $($file.Extension) is not implemented" -ForegroundColor Red -NoNewline
            }
        }

        Write-Host " $warning" -ForegroundColor Yellow
    }
    $pathes = $pathes | Where-Object { $_ -notin $ignored }

    Write-Debug "PSBoundParameters: $($PSBoundParameters | ConvertTo-Json)"
    Write-Debug "pathes: $($pathes.FullName | ConvertTo-Json)"
}
end {
    if ($Edit) {
        $arguments = $($pathes | Join-String -Separator " ")
        Write-Debug $arguments
        vi $arguments
    }

    Get-Process msaccess |
        Where-Object MainWindowHandle -eq 0 |
        Stop-Process

    $scriptPreamble = [System.Text.StringBuilder]::new()
    $scriptPreamble.AppendLine() | Out-Null
    $scriptPreamble.AppendLine('dim stdout : set stdout = CreateObject("Scripting.FileSystemObject").GetStandardStream(1)') | Out-Null
    $scriptPreamble.AppendLine('dim application: set application = GetObject(, "Access.Application")') | Out-Null
    $scriptPreamble.AppendLine('dim currentdb: set currentdb = application.CurrentDb()') | Out-Null
    $scriptPreamble.AppendLine('dim vbcomponents : set vbcomponents = application.VBE.ActiveVBProject.VBComponents') | Out-Null
    $scriptPreamble.AppendLine('dim codemodule') | Out-Null
    $scriptPreamble.AppendLine('on error resume next') | Out-Null
    $scriptPreamble.AppendLine() | Out-Null
    Write-Host

    $scriptExport = [System.Text.StringBuilder]::new()
    $scriptExport.Append($scriptPreamble) | Out-Null
    foreach ($file in $pathes) {
        Write-Host "Exporting $($file.Name) .." -NoNewline

        switch -regex ($file.Extension) {
            "^\.(ACQ)$" {
                $scriptExport.AppendLine("application.SaveAsText   1, `"$($file.BaseName)`", `"$($file.FullName).old`"") | Out-Null
            }
            "^\.(ACF)$" {
                $scriptExport.AppendLine("DoCmd.Close 2, `"$($file.BaseName)`", 2") | Out-Null
                $scriptExport.AppendLine("application.SaveAsText   2, `"$($file.BaseName)`", `"$($file.FullName).old`"") | Out-Null
            }
            "^\.(ACR)$" {
                $scriptExport.AppendLine("DoCmd.Close 3, `"$($file.BaseName)`", 2") | Out-Null
                $scriptExport.AppendLine("application.SaveAsText   3, `"$($file.BaseName)`", `"$($file.FullName).old`"") | Out-Null
            }
            "^\.(ACS)$" {
                $scriptExport.AppendLine("application.SaveAsText   4, `"$($file.BaseName)`", `"$($file.FullName).old`"") | Out-Null
            }
            "^\.(ACM)$" {
                $scriptExport.AppendLine("application.SaveAsText   5, `"$($file.BaseName)`", `"$($file.FullName).old`"") | Out-Null
            }
            "^\.(ACT)$" {
                $scriptExport.AppendLine("application.ExportXml `"$($file.FullName).old`", 1") | Out-Null
            }
        }

        Write-Host
    }
    Invoke-VbScript $scriptExport

    $scriptImport = [System.Text.StringBuilder]::new()
    $scriptImport.Append($scriptPreamble) | Out-Null
    foreach ($file in $pathes) {
        Write-Host "Importing $($file.Name) .." -NoNewline

        if ($Force) {
            switch -regex ($file.Extension) {
                "^\.(ACQ)$" {
                    $scriptImport.AppendLine("application.LoadFromText 1, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
                }
                "^\.(ACF)$" {
                    $scriptImport.AppendLine("application.LoadFromText 2, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
                }
                "^\.(ACR)$" {
                    $scriptImport.AppendLine("application.LoadFromText 3, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
                }
                "^\.(ACS)$" {
                    $scriptImport.AppendLine("application.LoadFromText 4, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
                }
                "^\.(ACM)$" {
                    $scriptImport.AppendLine("application.LoadFromText 5, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
                }
                "^\.(ACT)$" {
                    $scriptImport.AppendLine("currentdb.TableDefs.Delete `"$($file.BaseName)`"") | Out-Null
                    $scriptImport.AppendLine("application.ImportXml `"$($file.FullName)`", 1") | Out-Null
                }
            }
        } else {
            switch -regex ($file.Extension) {
                "^\.(ACQ)$" {
                    $scriptImport.AppendLine("application.LoadFromText 1, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
                }
                "^\.(ACS)$" {
                    $scriptImport.AppendLine("application.LoadFromText 4, `"$($file.BaseName)`", `"$($file.FullName)`"") | Out-Null
                }
                "^\.(ACT)$" {
                    $scriptImport.AppendLine("currentdb.TableDefs.Delete `"$($file.BaseName)`"") | Out-Null
                    $scriptImport.AppendLine("application.ImportXml `"$($file.FullName)`", 1") | Out-Null
                }
                "^\.(ACF|ACR|ACM)$" {
                    $foundCodeBehindForm = [System.IO.Path]::GetExtension($file) -notin @(".ACF", ".ACR")
                    $VbLine = 0
                    $new = Get-Content $file |
                        ForEach-Object {
                            [pscustomobject]@{
                                Line = if ($_.StartsWith("Attribute ")) {
                                    0
                                } elseif ($foundCodeBehindForm) {
                                    $VbLine += 1; $VbLine
                                } elseif ($_ -eq "CodeBehindForm") {
                                    $foundCodeBehindForm = $true; 0
                                }
                                Code = $_
                            }
                        }

                    $foundCodeBehindForm = [System.IO.Path]::GetExtension($file) -notin @(".ACF", ".ACR")
                    $VbLine = 0
                    $old = Get-Content "$($file.FullName).old" |
                        ForEach-Object {$_} -End {""} |
                        ForEach-Object {
                            [pscustomobject]@{
                                Line = if ($_.StartsWith("Attribute ")) {
                                    0
                                } elseif ($foundCodeBehindForm) {
                                    $VbLine += 1; $VbLine
                                } elseif ($_ -eq "CodeBehindForm") {
                                    $foundCodeBehindForm = $true; 0
                                }
                                Code = $_
                            }
                        }

                    $count = [Math]::Max(($new | Measure-Object).Count, ($old | Measure-Object).Count)
                    $vbcomponent_name = switch ($file.Extension) {
                        ".ACM" { $scriptImport.AppendLine("set codemodule = vbcomponents(`"$($file.BaseName)`").CodeModule")        | Out-Null }
                        ".ACF" { $scriptImport.AppendLine("set codemodule = vbcomponents(`"Form_$($file.BaseName)`").CodeModule")   | Out-Null }
                        ".ACR" { $scriptImport.AppendLine("set codemodule = vbcomponents(`"Report_$($file.BaseName)`").CodeModule") | Out-Null }
                    }

                    $i = 0
                    $j = 0
                    $changes = 0
                    $changesBehindForm = 0
                    while ($j -lt $count) {
                        $new_lines = -1
                        $del_lines = -1

                        try {
                            while ($old[$i].Code.Trim() -eq "NoSaveCTIWhenDisabled =1") { $i += 1 }
                            while ($new[$j].Code.Trim() -eq "NoSaveCTIWhenDisabled =1") { $j += 1 }
                        } catch {
                        }

                        try {
                            if ($old[$i].Code.StartsWith("Checksum =") -and $new[$j].Code.StartsWith("Checksum =")) {
                                $new_lines = 0
                                $del_lines = 0
                            } elseif ($old[$i].Code -eq $new[$j].Code) {
                                $new_lines = 0
                                $del_lines = 0
                            } else {
                                foreach ($d in 1..99) {
                                    if ($old[$i].Code -eq $new[$j+$d].Code) {
                                        $new_lines = $d
                                        break;
                                    }
                                    if ($old[$i+$d].Code -eq $new[$j].Code) {
                                        $del_lines = $d
                                        break;
                                    }
                                }
                            }
                        } catch {
                        }

                        while ($new_lines -gt 0) {
                            Write-Host "$($new[$j].Line): " -NoNewline
                            Write-Host -ForegroundColor Green $new[$j].Code -NoNewline
                            Write-Host -ForegroundColor Magenta " (new line)"
                            $changes += 1
                            if ($new[$j].Line -gt 0) {
                                $changesBehindForm += 1
                                $scriptImport.AppendLine("codemodule.InsertLines $($new[$j].Line), `"$( $new[$j].Code.Replace('"','`"`"') )`"") | Out-Null
                            }
                            $new_lines -= 1
                            $j += 1
                        }
                        while ($del_lines -gt 0) {
                            Write-Host "$($old[$j].Line): " -NoNewline
                            Write-Host -ForegroundColor Red $old[$i].Code -NoNewline
                            Write-Host -ForegroundColor Magenta " (deleted line)"
                            $changes += 1
                            if ($old[$j].Line -gt 0) {
                                $changesBehindForm += 1
                                $scriptImport.AppendLine("codemodule.DeleteLines $($old[$j].Line)") | Out-Null
                            }
                            $del_lines -= 1
                            $i += 1
                        }

                        if ($new_lines -eq -1 -and $del_lines -eq -1) {
                            if ($old[$i].Code -ne $new[$j].Code) {
                                Write-Host "$($new[$j].Line): " -NoNewline
                                Write-Host -ForegroundColor Red $old[$i].Code -NoNewline
                                Write-Host -ForegroundColor Green $new[$j].Code -NoNewline
                                Write-Host -ForegroundColor Magenta " (replace)"
                                $changes += 1
                                if ($new[$j].Line -gt 0) {
                                    $changesBehindForm += 1
                                    $scriptImport.AppendLine("codemodule.ReplaceLine $($new[$j].Line), `"$( $new[$j].Code.Replace('"','`"`"') )`"") | Out-Null
                                }
                            }
                        }

                        $i += 1
                        $j += 1
                    }
                    Write-Host -ForegroundColor Magenta "${file}: $changes changes ($changesBehindForm changes in VBA)"

                    # git --no-pager diff --no-index "$($file.FullName)" "$($file.FullName).old"
                    Remove-Item "$($file.FullName).old"
                }
            }
        }

        Write-Host
    }
    Invoke-VbScript $scriptImport



    if ($Compile) {
        Write-Host "Compiling.."

        $wshell.AppActivate((Get-Process MSACCESS).MainWindowTitle) | Out-Null
        $wshell.SendKeys("%{f11}")
        while (-not $wshell.AppActivate("Microsoft Visual Basic for Applications")) { Start-Sleep .25 }
        $wshell.SendKeys("%")
        $wshell.SendKeys("{RIGHT}{RIGHT}{RIGHT}{RIGHT}{DOWN}")
        $wshell.SendKeys("{ENTER}")
        while (-not $wshell.AppActivate("Microsoft Visual Basic for Applications")) { Start-Sleep .25 }

        $message = Start-Job {
            Add-Type '
                using System;
                using System.Runtime.InteropServices;
                using System.Collections.Generic;
                using System.Text;

                public class winapi
                {
                    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
                    public static extern int GetWindowText(IntPtr hwnd,StringBuilder lpString, int cch);

                    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
                    public static extern IntPtr GetForegroundWindow();

                    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
                    public static extern Int32 GetWindowThreadProcessId(IntPtr hWnd,out Int32 lpdwProcessId);

                    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
                    public static extern Int32 GetWindowTextLength(IntPtr hWnd);

                    [DllImport("user32")]
                    [return: MarshalAs(UnmanagedType.Bool)]
                    public static extern bool EnumChildWindows(IntPtr window, EnumWindowProc callback, IntPtr i);
                    public static List<IntPtr> GetChildWindows(IntPtr parent)
                    {
                    List<IntPtr> result = new List<IntPtr>();
                    GCHandle listHandle = GCHandle.Alloc(result);
                    try
                    {
                        EnumWindowProc childProc = new EnumWindowProc(EnumWindow);
                        EnumChildWindows(parent, childProc,GCHandle.ToIntPtr(listHandle));
                    }
                    finally
                    {
                        if (listHandle.IsAllocated)
                            listHandle.Free();
                    }
                    return result;
                }
                    private static bool EnumWindow(IntPtr handle, IntPtr pointer)
                {
                    GCHandle gch = GCHandle.FromIntPtr(pointer);
                    List<IntPtr> list = gch.Target as List<IntPtr>;
                    if (list == null)
                    {
                        throw new InvalidCastException("GCHandle Target could not be cast as List<IntPtr>");
                    }
                    list.Add(handle);
                    //  You can modify this to check to see if you want to cancel the operation, then return a null here
                    return true;
                }
                    public delegate bool EnumWindowProc(IntPtr hWnd, IntPtr parameter);
                }
            '

            foreach ($hwnd in ([winapi]::GetChildWindows([winapi]::GetForegroundWindow()))) {
                $len = [winapi]::GetWindowTextLength($hwnd)
                if($len -gt 0){
                    $sb = [System.Text.StringBuilder]::new($len + 1)
                    [winapi]::GetWindowText($hwnd,$sb,$sb.Capacity) | Out-Null
                    $sb.tostring()
                }
            }
        } | Wait-Job | Receive-Job

        if ($message[0] -eq "Ok") {
            $message = ($message | Select-Object -Skip 2) -replace '\r?\n',' '
            # $wshell.SendKeys("{ENTER}")
            # $wshell.AppActivate($host.UI.RawUI.WindowTitle)

            $name = ((Get-Process -Name MSACCESS).MainWindowTitle | Select-String "\[([^](]+)").Matches.Groups[1].Value.Trim()
            $file = switch -Regex ($name) {
                "^Form_"   { $name.SubString(5) + ".ACF" }
                "^Report_" { $name.SubString(7) + ".ACR" }
                default    { $name + ".ACM" }
            }

            Write-Host "`e[38;5;238m───────┬─$([string]::new('─', $host.UI.RawUI.WindowSize.Width-9))`e[0m"
            Write-Host "`e[38;5;238m       │`e[0m File: ${file}"
            Write-Host "`e[38;5;238m───────┼─$([string]::new('─', $host.UI.RawUI.WindowSize.Width-9))`e[0m"
            Write-Host "`e[38;5;238m       │`e[0m`e[31m $message`e[0m"
            Write-Host "`e[38;5;238m───────┴─$([string]::new('─', $host.UI.RawUI.WindowSize.Width-9))`e[0m"
        } else {
            $wshell.AppActivate((Get-Process WindowsTerminal).MainWindowTitle) | Out-Null
        }
    }
}
