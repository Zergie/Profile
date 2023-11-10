$slicer = "C:\ProgramData\chocolatey\lib\orcaslicer\tools\orca-slicer.exe"

$path = $args
$filename = [System.IO.Path]::GetFileNameWithoutExtension($path)
$extension = [System.IO.Path]::GetExtension($path)

$Destination = "${env:USERPROFILE}\Downloads\${filename}_$((Get-Date).ToString("yyyy-MM-dd"))${extension}"

@{
    Path = $path
    Destination = $Destination
}
Copy-Item -Path "${path}" -Destination "${Destination}" -Force

#pause
