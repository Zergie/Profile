$slicer = @(
    "$env:PROGRAMDATA\chocolatey\lib\orcaslicer\tools\OrcaSlicer\orca-slicer.exe"
    "$env:PROGRAMFILES\OrcaSlicer\orca-slicer.exe"
    ) | Get-Item -ErrorAction SilentlyContinue |
        Sort-Object CreationTime |
        Select-Object -Last 1
$slicer_process = Get-Process ([System.IO.Path]::GetFileNameWithoutExtension($slicer))
$path = Get-ChildItem ("$args*" -replace '(\[|\])','``$1') | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object FullName

$Debug = $false
$Debug = $Debug -or $path.Length -eq 0
if ($Debug) {
    Write-Host -ForegroundColor Yellow "`$slicer=$slicer"
    Write-Host -ForegroundColor Yellow "`$slicer_process=$($slicer_process.Id)"
    Write-Host -ForegroundColor Yellow "`$args=" -NoNewline
    $args | ConvertTo-Json | Write-Host -ForegroundColor Yellow
    Write-Host -ForegroundColor Yellow "`$Path=$path"
}

if ($null -ne $slicer_process) {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class NativeMethods {
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool PostMessage(IntPtr hWnd, UInt32 Msg, int wParam, int lParam);
    }
"@

    [NativeMethods]::SetForegroundWindow((Get-Process Fusion360).MainWindowHandle)
    [NativeMethods]::SetForegroundWindow($slicer_process.MainWindowHandle)
    $wshell = New-Object -ComObject wscript.shell;
    $wshell.SendKeys("^i")

    Start-Sleep -Milliseconds 750

    $old = Get-Clipboard
    Set-Clipboard -Value ${path}
    $wshell.SendKeys("^v")
    $wshell.SendKeys("{Enter}")

    Start-Sleep -Milliseconds 200

    $wshell.SendKeys("+A")

    Start-Sleep -Seconds 1
    [NativeMethods]::SetForegroundWindow((Get-Process Fusion360).MainWindowHandle)
    Set-Clipboard $old
} else {
    . $slicer "${path}"
}

if ($Debug) { Read-Host }
