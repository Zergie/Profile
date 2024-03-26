[CmdletBinding()]
param (
)
Start-Process `
    -WindowStyle Minimized `
    -FilePath (Get-ChildItem C:\GIT\QuickAndDirty\bsc\CefSharpDownloader\ -Recurse -Filter CefSharpDownloader.exe |
                    Sort-Object LastWriteTime |
                    Select-Object -Last 1 |
                    ForEach-Object FullName)
$cefDownloader = Get-Process CefSharpDownloader
$cefDownloader.WaitForInputIdle() | Out-Null
$cefDownloader
