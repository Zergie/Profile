$location = Get-Location
Get-ChildItem "C:\Program Files*\Microsoft Visual Studio\**\Community\Common7\Tools\Microsoft.VisualStudio.DevShell.dll" |
    Select-Object -First 1 |
    Import-Module

$VsInstanceId = [string]::new(((Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Visual Studio *\Visual Studio Tools\Dev*PowerShell*.lnk" | Select-Object -First 1 | cat | Out-String).ToCharArray() |? { ([int]($_)) -ge 32 -and ([int]($_)) -le 122 })) |
    Select-String -Pattern "Enter-VsDevShell ([a-z0-9]+)"|
    ForEach-Object Matches |
    ForEach-Object Groups |
    Select-Object -Last 1

Enter-VsDevShell $VsInstanceId
Set-Location $location

function Prompt { "DEV $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) " }