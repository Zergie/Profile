$slicer = "C:\ProgramData\chocolatey\lib\orcaslicer\tools\OrcaSlicer\orca-slicer.exe"
$slicer_process = Get-Process ([System.IO.Path]::GetFileNameWithoutExtension($slicer))

$path = Get-ChildItem "$args*" | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object FullName

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

    Set-Clipboard -Value ${path}
    $wshell.SendKeys("^v")
    $wshell.SendKeys("{Enter}")
} else {
    . $slicer "${path}"
}

# Read-Host
