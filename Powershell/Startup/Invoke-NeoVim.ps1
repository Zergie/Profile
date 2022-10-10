$editorArgs = @{ Editor="C:/tools/neovim/nvim-win64/bin/nvim.exe" ` }
if ($args.Length  -gt 0) { $editorArgs["Arguments"] = $args  }
if ($input.MoveNext()) {
    $input.Reset()
    $input | Out-String | . "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
} else {
     . "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
}

