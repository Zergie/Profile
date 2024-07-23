$builtin    = @("-b", "--background")
$servername = "127.0.0.1:6789"
$cmdline    = "vi $($args | Join-String -Separator ' ') "

if ($null -eq (Get-Process -Name nvim -ErrorAction SilentlyContinue)) {
    wt new-tab "C:/tools/neovim/nvim-win64/bin/nvim.exe" --listen $servername
    $new_process = $true
} else {
    $new_process = $false
}

$editorArgs = @{
    Editor="C:/Python311/python.exe"
    Arguments=@(
        "C:/Python311/Lib/site-packages/nvr/nvr.py"

        "--servername"
        "$servername"

        # close terminal window
        "-cc"
        "lua require('FTerm').close()"

        if ($cmdline -match "\s(-b|--background)\s") {
            # defocus editor
            "-cc"
            "silent !wt focus-tab -t 0"
        } elseif ($new_process) {
            # new process are already focused
        } else {
            # focus editor
            "-cc"
            "silent !wt focus-tab -t 1"
        }
    ) + $args | Where-Object { $_ -notin $builtin }
}

if ($input.MoveNext()) {
    $input.Reset()
    $input | Out-String | . "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
} else {
     . "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
}
