call plug#begin('~/AppData/Local/nvim/plugged')
    Plug 'tomasiser/vim-code-dark'
call plug#end()

" enter the current millenium
set nocompatible

" set termguicolors
set termguicolors

" enable syntax and plugins (for netrw)
syntax enable
filetype plugin on

" Search down into subfolders
" Provides tab-completion for all file-related tasks
" set path+=**

" Display all matching files when we tab complete
set wildmenu

" Tweaks for browsing
let g:netrw_banner=0        " disable annoying banner
" let g:netrw_browse_split=4  " open in prior window
" let g:netrw_altv=1          " open splits to the right
" let g:netrw_liststyle=3     " tree view
" let g:netrw_list_hide=netrw_gitignore#Hide()
" let g:netrw_list_hide.=',\(^\|\s\s\)\zs\.\S\+'

" use pwsh as shell
set shell=cmd.exe
set shellcmdflag=/c\ pwsh.exe\ -NoLogo\ -NoProfile\ -NonInteractive\ -ExecutionPolicy\ RemoteSigned\ -Command
set shellpipe=|
set shellredir=>

" some keys
nmap <F6> :w \| !wt -w 0 sp -d %:p:h cmd /C "git add -p && pause"<CR><CR>

" change cursor back to pwsh default on leaving vim
au VimLeave * set guicursor=a:ver100

" set language to english
set spell spelllang=en_us
set langmenu=en_US
let $LANG = 'en_US'

" activate line numbers
set number relativenumber

" search case insensitiv
set ignorecase
set smartcase
" examples:
"  /copyright      " Case insensitive
"  /Copyright      " Case sensitive
"  /copyright\C    " Case sensitive
"  /Copyright\c    " Case insensitive

" use spaces instead of tabs
set tabstop=4
set shiftwidth=4
set expandtab

" color scheme
colorscheme codedark

" vba file extensions
au BufRead,BufNewFile *.ACM set filetype=vba
au BufRead,BufNewFile *.ACR set filetype=vba
au BufRead,BufNewFile *.ACF set filetype=vba
