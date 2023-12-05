$slicer = "C:\ProgramData\chocolatey\lib\orcaslicer\tools\orca-slicer.exe"
$slicer_process = Get-Process ([System.IO.Path]::GetFileNameWithoutExtension($slicer))

$path = $args
$filename = [System.IO.Path]::GetFileNameWithoutExtension($path)
$extension = [System.IO.Path]::GetExtension($path)

$Destination = "${env:USERPROFILE}\Downloads\${filename}_$((Get-Date).ToString("yyyy-MM-dd"))${extension}"

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
    $wshell.SendKeys($Destination)
    $wshell.SendKeys("{Enter}")
} else {
    . $slicer "${Destination}"
}

# Read-Host
