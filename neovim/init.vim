call plug#begin('~/AppData/Local/nvim/plugged')
    "  Plug 'github/copilot.vim'
call plug#end()

" enable github copilot for all files
"  let g:copilot_filetypes = { '*': v:true } 

" change cursor back to pwsh default on leaving vim
au VimLeave * set guicursor=a:ver100

" set language to english
set spell spelllang=en_us
set langmenu=en_US
let $LANG = 'en_US'
