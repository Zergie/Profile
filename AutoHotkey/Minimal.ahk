;
; remap <TAB> to <ESC> for neovim
;

; add my custom   vv console title
GroupAdd, neovim, [neovim] ahk_exe WindowsTerminal.exe
; also add        vv for pyright
GroupAdd, neovim, C:\WINDOWS\system32\cmd.exe ahk_exe WindowsTerminal.exe

#IfWinActive ahk_group neovim
$Tab up::
Send, {Escape Up}
return

#IfWinActive ahk_group neovim
$Tab::
Send, {Escape Down}
KeyWait, Tab
return



