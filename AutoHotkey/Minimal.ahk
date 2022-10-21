; 
; remap <TAB> to <ESC> for neovim
;
#IfWinActive [neovim] ahk_exe WindowsTerminal.exe
$Tab up::
Send, {Escape Up}
return

$Tab::
Send, {Escape Down}
KeyWait, Tab
return



