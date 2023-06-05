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
    $Edit,

    [Parameter()]
    [switch]
    $Compile
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
                Write-Host "$($file.Extension) is not implemented" -ForegroundColor Red
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

    if ($Compile) {
        $wshell = New-Object -ComObject wscript.shell;

        $wshell.AppActivate("Microsoft Visual Basic for Applications") | Out-Null
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
            # $wshell.SendKeys('%{TAB}')

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
            $wshell.SendKeys('%{TAB}')
        }
    }

    if ($ShowDiff) {
        foreach ($file in $pathes) {
            git --no-pager diff --no-index "$($file.FullName)" "$($file.FullName).old"
            Remove-Item "$($file.FullName).old"
        }
    }
}

