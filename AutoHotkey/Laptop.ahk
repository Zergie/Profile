!LButton::MButton
!RButton::+MButton

Capslock::SEND "{ESCAPE}"

#HotIf WinActive("ahk_exe MSACCESS.EXE")
F12::Send "{CtrlBreak}"
F10::Send "+{F8}"
F11::Send "{F8}"

; Configure F24 as the dictation shortcut in ChatGPT/Codex.
; Forward F11 only while a ChatGPT/Codex window is active.
; #HotIf WinActive("ahk_exe Codex.exe") || WinActive("ahk_exe ChatGPT.exe")
; F11::Send "{F24}"
; #HotIf
