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
    $wshell = New-Object -ComObject wscript.shell;
    $wshell.AppActivate($slicer_process.MainWindowTitle)
    $wshell.SendKeys("^i")
    $wshell.SendKeys($Destination)
    $wshell.SendKeys("{Enter}")
} else {
    . $slicer "${Destination}"
}

#pause
