#Include %A_LineFile%\..\libs\WinClipAPI.ahk
#Include %A_LineFile%\..\libs\WinClip.ahk
#Include %A_LineFile%\..\HomerowMod-vars.ahk
#Include %A_LineFile%\..\EscapeMod.ahk
#Include %A_LineFile%\..\HomerowMod.ahk

CoordMode, Mouse, Window
SetKeyDelay -1
SetBatchLines -1

;SetTitleMatchMode RegEx
;#if, WinActive("([1-9][.]xlsx - Excel)$")!
;^1:: Send {CtrlUp}%A_Hour%:%A_Min%{Enter}
;return

SetTitleMatchMode 2
#IfWinActive ahk_class FWinForm131072
^1::SendInput puchinger{tab}wolfgang{enter}

#IfWinActive ahk_class SHREWSOFT_CON
^1::SendInput Puchinger{tab}pO4nVt434QxlVMsnc4iD{enter}

#IfWinActive Datenbank öffnen
^1::SendInput T€chn{!}k1{enter}

#IfWinActive Open Database
^1::SendInput T€chn{!}k1{enter}

#IfWinActive C:\Users\Puchinger.ROCOM.000\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\AutoHotkey.ahk
~^s::
sleep 100
reload
return

; #IfWinActive ahk_exe WindowsTerminal.exe
; ::;;::
; suspend On
; SendInput $(s )
; suspend Off
; Send {left}
; return

#IfWinActive
^1::
Send, {CtrlUp}
ClipSave := Clipboard
SendInput %ClipSave%
return

^2::
Send, ^c

Gui, New
Gui, Add, Button, gradioSelected w150, Fehlerbehebung Tau-Office
Gui, Add, Button, gradioSelected w150, Weiterentwicklung Tau-Office
Gui, Add, Button, gradioSelected w150, Hotlineunterstützung
Gui, Add, Button, gradioSelected w150, Konzeption Tau-Office
Gui, Show, w170
return

radioSelected:
Gui, Submit, NoHide
sText = * %A_GuiControl%
Gui, Destroy

Send, {CtrlUp}{F2}
if StrLen(Clipboard) > 5 {
    Send, {AltDown}{Enter}{AltUp}
}
Send, %sText%
Send, {Delete}{Enter}
return

^+v::
ClipSave := Clipboard
Clipboard:= ClipSave
Send ^v
return


;
; volume control with <LWIN> & mouse wheel
;
LWin & WheelUp::
SoundSet, +4
Send, {Blind} {Volume_Up}
return

LWin & WheelDown::
SoundSet, -4
Send {Blind} {Volume_Down}
return


#Include %A_LineFile%\..\Minimal.ahk

#IfWinNotActive ahk_exe WindowsTerminal.exe
;
; shortcuts
;
::;i::
Suspend, On
InputBox, a

sText = #%a%
sLink = https://dev.azure.com/rocom-service/TauOffice/_workitems/edit/%a%

IfWinActive, ahk_exe Teams.exe
{
    ClipSave := ClipboardAll

    WinClip.SetHTML("<a href='" sLink "'>" sText "</a>")
    Send, ^v
    Sleep, 200
    
    clipboard := ClipSave
}

IfWinActive, ahk_exe OUTLOOK.EXE
{
     olApp := ComObjActive("Outlook.Application")
     ;olApp.ActiveInspector.CurrentItem.BodyFormat := 2
     objSel := olApp.ActiveInspector.WordEditor.Application.Selection
     objLink := olApp.ActiveInspector.WordEditor.Hyperlinks.Add(objSel.range, sLink, "", "", sText, "")
     objLink.Range.Font.Name := "Arial"
 }
Suspend, Off
return

::;ii::
suspend On
SendInput Implementierung und Test
suspend Off
Send {left}{left}
return

::;sd::
suspend On
SendInput rcExecute GLBdB.GdB, buildDelete("")
suspend Off
Send {left}{left}
return

::;si::
suspend On
SendInput rcExecute GLBdB.GdB, buildInsert("")
suspend Off
Send {left}{left}
return

::;su::
suspend On
SendInput rcExecute GLBdB.GdB, buildUpdate("")
suspend Off
Send {left}{left}
return

::;do::
SendInput Do Until rs.EOF{Enter}
SendInput {Enter}
SendInput {Enter}
SendInput {tab}rs.movenext{Enter}
SendInput {BackSpace}Loop{Enter}
SendInput rs.Close{Enter}
SendInput {up}
SendInput {up}
SendInput {up}
SendInput {up}
SendInput {up}
SendInput {tab}
return

::;dim rs::
SendInput Dim rs As Recordset{space}
return

::;set rs::
suspend On
SendInput set rs = rcOpenRecordset(GLBdB.GdB, buildselect("*", ""))
suspend Off
send {left}{left}{left}
return

::;dim sb::
SendInput Dim sb As ChilkatStringBuilder{space}
return

::;with sb::
SendInput With New ChilkatStringBuilder{Enter}
SendInput {tab}.Append ""{Enter}
SendInput {Enter}
SendInput _  = .GetAsString(){Enter}
SendInput {BackSpace}End With{Enter}
SendInput {up}
SendInput {up}
SendInput {Home}
SendInput {ShiftDown}{Right}{ShiftUp}
return

::;set sb::
SendInput set sb = New ChilkatStringBuilder{space}
return

::;n::
SendInput vbNullString
return

::;gl::
suspend On
SendInput Get_Label("")
suspend Off
send {left}{left}
return

::;oer::
SendInput On Error Resume Next
return

::;oe0::
SendInput On Error Goto 0
return

::;al::
SendRaw, '#
SendInput, TO_BUILD ALLOW_SPELLING
Send, {Del}
Send, {Space}
return

::;ss::
SendInput, Stop ' {#}TO_BUILD FAIL
return

::;fail::
SendInput '{#}TO_BUILD FAIL
return

::;ps::
SendInput Profiler_start ""
Send {left}
return

::;pe::
SendInput Profiler_end ""
Send {left}
return

; map Mouse
XButton1::
Send {Blind}{CtrlDown}{LWinDown}{Left}{LWinUp}{CtrlUp}
return

XButton2::
Send, {Blind}{CtrlDown}{LWinDown}{Right}{LWinUp}{CtrlUp}
return

; Shift + Wheel for horizontal scrolling

; Scroll to the left
+WheelUp::
MouseGetPos,,,id, fcontrol,1
SendMessage, 0x114, 0, 0, %fcontrol%, ahk_id %id% ; 0x114 is WM_HSCROLL and the 0 after it is SB_LINERIGHT.
return

;Scroll to the right
+WheelDown::
MouseGetPos,,,id, fcontrol,1
SendMessage, 0x114, 1, 0, %fcontrol%, ahk_id %id% ;  0x114 is WM_HSCROLL and the 1 after it is SB_LINELEFT.
return


;
; GUI
;
GuiEscape:
Gui, Destroy
Return
