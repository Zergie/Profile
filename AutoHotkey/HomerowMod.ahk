; -------------------------------+
                                ; \ homerow modifiers
                                ;  +---------------------------------------------------------------
#IfWinActive
$+;::
    global homerow_shift_r
    IfNotEqual, homerow_shift_r, 0, return
    Send, :
return

$;::
    global homerow_shift_r
    IfNotEqual, homerow_shift_r, 0, return
    Send,;
    KeyWait,;, t0.15
    If ErrorLevel {
        homerow_shift_r := 1
        Send, {Backspace}{Shift Down}
        KeyWait,;
        Send, {Shift Up}
        homerow_shift_r := 0
    }
return

$+a::
    global homerow_shift_l
    IfNotEqual, homerow_shift_l, 0, return
    Send, A
return

$a::
    global homerow_shift_l
    IfNotEqual, homerow_shift_l, 0, return
    Send, a
    KeyWait, a, t0.15
    If ErrorLevel {
        homerow_shift_l := 1
        Send, {Backspace}{Shift Down}
        KeyWait, a
        Send, {Shift Up}
        homerow_shift_l := 0
    }
return
; -------------------------------+
                                ; \ End Of File
                                ;  +---------------------------------------------------------------
