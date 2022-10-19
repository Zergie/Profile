" Vim syntax file
" Language:     Tau-Office Eval Expression

" quit when a syntax file was already loaded
if exists("b:current_syntax")
    finish
endif

" .. is case insensitive
syn case ignore



syn match Bracket "[()]"
syn match Operator "[+.,\-/*=&]"
syn match Operator "[<>]=\="
syn match Operator "<>"
syn match Operator "\s\+_$"

syn keyword Boolean True False

syn keyword Keyword LIKE AND OR NOT

" Headers
syn match Comment "^==.\+$"
syn match Comment "^--.\+$"

" Function calls
syn match Identifier "\zs\w\+\ze("

" Placeholder
syn region TSConstMacro start=+{+ end=+}+ 

" Numbers
syn match Number "\<\d\+\>"
syn match Number "\<\d\+\.\d*\>"
syn match Number "\.\d\+\>"
syn match Number "{[[:xdigit:]-]\+}\|&[hH][[:xdigit:]]\+&"
syn match Number ":[[:xdigit:]]\+"
syn match Number "[-+]\=\<\d\+\>"
syn match Float  "[-+]\=\<\d\+[eE][\-+]\=\d\+"
syn match Float  "[-+]\=\<\d\+\.\d*\([eE][\-+]\=\d\+\)\="
syn match Float  "[-+]\=\<\.\d\+\([eE][\-+]\=\d\+\)\="

" String and Character constants
syn region String start=+"+ end=+"\|$+ contains=TSConstMacro
syn region String start=+'+ end=+'\|$+ contains=TSConstMacro

let b:current_syntax = "article"

" vim: ts=8
