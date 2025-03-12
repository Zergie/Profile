$editorArgs = @{
    Editor    = "$env:windir\System32\OpenSSH\ssh.exe"
    Arguments = @(
        "u266601-sub2@u266601-sub2.your-storagebox.de"
        "-p23"
    ) + $args
    DoNotTransformPaths = $true
}

if ($input.MoveNext()) {
    $input.Reset()
    $input | Out-String | . "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
} else {
     . "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
}
