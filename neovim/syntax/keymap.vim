" Vim syntax file
" Language:     ZMK Keymap

" quit when a syntax file was already loaded
if exists("b:current_syntax")
    finish
endif

runtime! syntax/c.vim

syn match Key contained " \w\+"
syn region Behavior start=+<&+ end=+>+ contains=Key
syn match  Behavior "&\w+"

hi def link Behavior jsOperatorKeyword
hi def link Key      jsFuncArgs

" vim: ts=8
