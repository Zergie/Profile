$slicer = "C:\ProgramData\chocolatey\lib\orcaslicer\tools\OrcaSlicer\orca-slicer.exe"
$slicer_process = Get-Process ([System.IO.Path]::GetFileNameWithoutExtension($slicer))

$path = Get-ChildItem "$args*" | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object FullName
$filename = [System.IO.Path]::GetFileNameWithoutExtension($path)
$extension = [System.IO.Path]::GetExtension($path)

$Destination = "${env:USERPROFILE}\Downloads\${filename.Replace(" ", "")}_$((Get-Date).ToString("yyyy-MM-dd"))${extension}"

@{
    Path = $path
    Destination = $Destination
}
Copy-Item -Path "${path}" -Destination "${Destination}" -Force

if ($null -ne $slicer_process) {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class NativeMethods {
        [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
                public static extern bool SetForegroundWindow(IntPtr hWnd);
    }
"@

    [NativeMethods]::SetForegroundWindow($slicer_process.MainWindowHandle)

    $wshell = New-Object -ComObject wscript.shell;
    $wshell.SendKeys("^i")

    Start-Sleep -Milliseconds 500

    $wshell.SendKeys($Destination)
    $wshell.SendKeys("{Enter}")
} else {
    . $slicer "${Destination}"
}

# Read-Host
