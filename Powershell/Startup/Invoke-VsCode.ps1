$editorArgs = @{ Editor="C:\Program Files\Microsoft VS Code\bin\code.cmd" ` }
if ($args.Length -gt 0) { $editorArgs["Arguments"] = $args  }
. "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs