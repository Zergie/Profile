" Vim syntax file
" Language:     Visual Basic - Project File

" quit when a syntax file was already loaded
" if exists("b:current_syntax")
"     finish
" endif

" VB is case insensitive
syn case ignore

syn match vbKeyword "\v^\w+"

syn match vbType "\v^Type" contained
syn region vbTypeRegion start="\v^Type" end="$" contains=vbType

syn match vbReference "\v^Reference" contained
syn match vbGuid "\v\*\\G\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}" contained
syn match vbVersion "\v\d+\.\d+\w?" contained
syn region vbVersionRegion start="#" end="#" contained contains=vbVersion
syn match vbReferencePath "\v[^#].+" contained
" TODO : fix vbReferencePathRegion
syn region vbReferencePathRegion start="\v#[tp.]" end="$" contained contains=vbReferencePath
syn region vbReferenceRegion start="\v^Reference" end="$" contains=vbReference,vbGuid,vbVersionRegion,vbReferencePathRegion

" TODO : fix vbClass
syn match vbClass contained "\v^Class"
syn match vbModule contained "\v^Module"

syn match vbFileIdentifier contained "\v[^;=]+"
syn region vbFileIdentifierRegion start="=" end=";" contains=vbFileIdentifier
syn match vbFilePath contained "\v[^ ][^;]+"
syn region vbFilePathRegion start=" " end="$" contains=vbFilePath

syn region vbFileRegion start="\v^(Class|Module)" end="$" contains=vbClass,vbModule,vbFileIdentifierRegion,vbFilePathRegion

" Define the default highlighting.
" Only when an item doesn't have highlighting yet

hi def link vbKeyword         Type
hi def link vbType            Define
hi def link vbReference       Identifier
hi def link vbReferencePath   String
hi def link vbGuid            Number
hi def link vbVersion         Number
hi def link vbClass           Define
hi def link vbFileIdentifier  Identifier
hi def link vbFilePath        String
hi def link vbModule          Function

let b:current_syntax = "vbp"

" vim: ts=8
