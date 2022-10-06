$editorArgs = @{ Editor="C:/tools/neovim/nvim-win64/bin/nvim.exe" ` }
if ($args.Length -gt 0) { $editorArgs["Arguments"] = $args  }
. "$PsScriptRoot\Invoke-Editor.ps1" ` @editorArgs
