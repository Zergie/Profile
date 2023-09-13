$nvim = (Get-Process -Id $PID).Parent.Parent

if ($nvim.Name -ne "nvim") {
    $editorArgs = @{ Editor="C:/tools/neovim/nvim-win64/bin/nvim.exe" ` }
    if ($args.Length  -gt 0) { $editorArgs["Arguments"] = $args  }
} else {
    $editorArgs = @{
        Editor="python"
        Arguments=@(
            "C:/Python311/Lib/site-packages/nvr/nvr.py"

            # close terminal window
            "-cc"
            "lua require('FTerm').close()"
        ) + $args
    }
}

if ($input.MoveNext()) {
    $input.Reset()
    $input | Out-String | . "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
} else {
     . "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
}
