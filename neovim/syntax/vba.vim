" Vim syntax file
" Language:     Visual Basic for Application

" quit when a syntax file was already loaded
if exists("b:current_syntax")
        finish
endif

" VB is case insensitive, but we do not want mix cases in our git repo
" syn case ignore

syn keyword vbOperator AddressOf Eqv Imp In
syn keyword vbOperator Mod Not To Xor

syn match vbBracket "[()]"

syn match vbOperator "[+.,\-/*=&]"
syn match vbOperator "[<>]=\="
syn match vbOperator "<>"
syn match vbOperator "\s\+_$"

syn keyword vbBoolean  True False
syn keyword vbConst Null Nothing

syn keyword vbRepeat Do For ForEach Loop Next
syn keyword vbRepeat Step To Until Wend While

syn keyword vbFunction Abs Array Asc AscB AscW Atn Avg BOF CBool CByte
syn keyword vbFunction CCur CDate CDbl CInt CLng CSng CStr CVDate CVErr
syn keyword vbFunction CVar CallByName Cdec Choose Chr ChrB ChrW Command
syn keyword vbFunction Cos Count CreateObject CurDir DDB Date DateAdd
syn keyword vbFunction DateDiff DatePart DateSerial DateValue Day Dir
syn keyword vbFunction DoEvents Environ Error Exp FV FileAttr
syn keyword vbFunction FileDateTime FileLen FilterFix Fix Format
syn keyword vbFunction FormatCurrency FormatDateTime FormatNumber
syn keyword vbFunction FormatPercent FreeFile GetAllStrings GetAttr
syn keyword vbFunction GetAutoServerSettings GetObject GetSetting Hex
syn keyword vbFunction Hour IIf IMEStatus IPmt InStr Input InputB
syn keyword vbFunction InputBox InstrB Int IsArray IsDate IsEmpty IsError
syn keyword vbFunction IsMissing IsNull IsNumeric IsObject Join LBound
syn keyword vbFunction LCase LOF LTrim Left LeftB Len LenB LoadPicture
syn keyword vbFunction LoadResData LoadResPicture LoadResString Loc Log
syn keyword vbFunction MIRR Max Mid MidB Min Minute Month MonthName
syn keyword vbFunction MsgBox NPV NPer Now Oct PPmt PV Partition Pmt
syn keyword vbFunction QBColor RGB RTrim Rate Replace Right RightB Rnd
syn keyword vbFunction Round SLN SYD Second Seek Sgn Shell Sin Space Spc
syn keyword vbFunction Split Sqr StDev StDevP Str StrComp StrConv
syn keyword vbFunction StrReverse Sum Switch Tab Tan Time
syn keyword vbFunction TimeSerial TimeValue Timer Trim TypeName UBound
syn keyword vbFunction UCase Val Var VarP VarType Weekday WeekdayName
syn keyword vbFunction Year

syn keyword vbStatement Alias Base Beep Call
syn keyword vbStatement Const Declare DefBool DefByte
syn keyword vbStatement DefCur DefDate DefDbl DefDec DefInt DefLng DefObj
syn keyword vbStatement DefSng DefStr DefVar Deftype Dim Do
syn keyword vbStatement Each ElseIf End Enum Erase Error Event Exit
syn keyword vbStatement Explicit For ForEach Function Get GoSub
syn keyword vbStatement GoTo Implements Let LineInput
syn keyword vbStatement Load Lock Loop MkDir Name Next On OnError Open
syn keyword vbStatement Option Preserve Private Property Public Put
syn keyword vbStatement RaiseEvent Randomize ReDim Redim Reset Resume
syn keyword vbStatement Set Static Step Stop Sub
syn keyword vbStatement Type Until Wend While Width With
syn keyword vbStatement Attribute
syn keyword vbStatement Compare Text Binary Database

syn keyword vbKeyword Binary Date Empty Error Get
syn keyword vbKeyword Input Lock New Nothing Null On
syn keyword vbKeyword Option ParamArray Print Private Property
syn keyword vbKeyword Public Resume Seek Debug Assert
syn keyword vbKeyword Set Static Step WithEvents
syn keyword vbKeyword If Then ElseIf Else Select Case

syn keyword vbControl Optional ByRef ByVal And Or Is Like As TypeOf

syn keyword vbTodo contained    TODO

" Functions
syn match vbFunction "\v(Function|Sub|Property (G|L|S)et) @<=\w[a-z0-9_]*"

" Datatypes
syn match vbType  "\v( (As|Is) )@<=\w[a-z0-9_]*"

" Numbers
" integer number, or floating point number without a dot.
syn match vbNumber "\<\d\+\>"
" floating point number, with dot
syn match vbNumber "\<\d\+\.\d*\>"
" floating point number, starting with a dot
syn match vbNumber "\.\d\+\>"
syn match  vbNumber            "{[[:xdigit:]-]\+}\|&[hH][[:xdigit:]]\+&"
syn match  vbNumber            ":[[:xdigit:]]\+"
syn match  vbNumber            "[-+]\=\<\d\+\>"
syn match  vbFloat             "[-+]\=\<\d\+[eE][\-+]\=\d\+"
syn match  vbFloat             "[-+]\=\<\d\+\.\d*\([eE][\-+]\=\d\+\)\="
syn match  vbFloat             "[-+]\=\<\.\d\+\([eE][\-+]\=\d\+\)\="

" String and Character constants
syn region  vbString		start=+"+  end=+"\|$+
syn region  vbComment		start="\(^\|\s\)REM\s" end="$" contains=vbTodo
syn region  vbComment		start="\(^\|\s\)\'"   end="$" contains=vbTodo
syn match   vbLineLabel		"^\h\w\+:"
syn match   vbLineNumber	"^\d\+\(:\|\s\|$\)"

" Conditional Compilation
syn match  vbPreProc "^#const\>"
syn region vbPreProc matchgroup=PreProc start="^#if\>"     end="\<then\>" transparent contains=TOP
syn region vbPreProc matchgroup=PreProc start="^#elseif\>" end="\<then\>" transparent contains=TOP
syn match  vbPreProc "^#else\>"
syn match  vbPreProc "^#end\s*if\>"

" Form Controls
syn region vbCodeBehindForm start="Version =\d\+" end="CodeBehindForm" contains=vbFormEnd,vbFormControls,vbFormVersion,vbNumber
syn keyword vbFormVersion Version contained
syn keyword vbFormVersion VersionRequired contained
syn keyword vbFormVersion Checksum contained
syn region vbFormControls start="Begin \w\+" end="End" contained contains=vbFormBegin,vbFormKey,vbNumber,vbString,vbFormNumber,vbFormBoolean
" syn region vbFormNumber start="Begin\r" end="End" contained contains=vbFormBegin,vbFormEnd
syn keyword vbFormBegin Begin contained
syn keyword vbFormEnd End contained
syn keyword vbFormBoolean NotDefault Default contained
syn match vbFormKey   "\v^\s+\w[^ ]+" contained

" Define the default highlighting.
" Only when an item doesn't have highlighting yet

hi def link vbBoolean           Boolean
hi def link vbLineNumber        Comment
hi def link vbLineLabel         Comment
hi def link vbComment           Comment
hi def link vbConst             Constant
hi def link vbDefine            Constant
hi def link vbError             Error
hi def link vbFunction          Identifier
hi def link vbNumber            Number
hi def link vbFloat             Float
hi def link vbMethods           PreProc
hi def link vbBracket           TSText
hi def link vbOperator          Operator
hi def link vbRepeat            Repeat
hi def link vbString            String
hi def link vbStatement         TSKeyword
hi def link vbKeyword           TSKeyword
hi def link vbTodo              Todo
hi def link vbType              TSType
hi def link vbTypeSpecifier     TSType
hi def link vbPreProc           PreProc
hi def link vbControl           TSConditional
hi def link vbFormKey           Identifier
hi def link vbFormVersion       Identifier
hi def link vbFormBegin         TSKeyword
hi def link vbFormEnd           TSKeyword
hi def link vbFormNumber        Number
hi def link vbFormBoolean       Boolean

let b:current_syntax = "vba"

" vim: ts=8
