if ($null -eq (Get-Process -Name nvim -ErrorAction SilentlyContinue)) {
    wt new-tab "C:/tools/neovim/nvim-win64/bin/nvim.exe" --listen 127.0.0.1:6789
}

$editorArgs = @{
    Editor="python"
    Arguments=@(
        "C:/Python311/Lib/site-packages/nvr/nvr.py"
        "--servername"
        "127.0.0.1:6789"

        # close terminal window
        "-cc"
        "lua require('FTerm').close()"

        # focus editor
        "-cc"
        "silent !wt focus-tab -t 2"
    ) + $args
}

if ($input.MoveNext()) {
    $input.Reset()
    $input | Out-String | . "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
} else {
     . "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
}
