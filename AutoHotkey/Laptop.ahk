!LButton::MButton
!RButton::+MButton

#HotIf WinActive("ahk_exe MSACCESS.EXE")
F12::Send "{CtrlBreak}"
F10::Send "+{F8}"
F11::Send "{F8}"
