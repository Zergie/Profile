; -------------------------------+
                                ; \ remap <TAB> to <ESC> for neovim
                                ;  +---------------------------------------------------------------
GroupAdd, neovim, [neovim] ahk_exe WindowsTerminal.exe
GroupAdd, neovim, C:\WINDOWS\system32\cmd.exe ahk_exe WindowsTerminal.exe
#IfWinActive ahk_group neovim

$Tab up::
Send, {Escape Up}
return
                                                                          
$Tab::
Send, {Escape Down}
KeyWait, Tab
return
; -------------------------------+
                                ; \ End Of File
                                ;  +---------------------------------------------------------------
