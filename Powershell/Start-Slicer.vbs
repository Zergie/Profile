Set oShell = CreateObject ("Wscript.Shell")

cmd = "powershell -NoProfile C:\GIT\Profile\Powershell\Start-Slicer.ps1"
For i = 0 to Wscript.Arguments.Count -1
    cmd = cmd & " " & Wscript.Arguments.Item(i)
Next

'wscript.echo cmd
oShell.Run cmd, 0, false
