call plug#begin('~/AppData/Local/nvim/plugged')
    " vscode dark theme
    Plug 'Mofiqul/vscode.nvim'

    " allows align e.g. vipga=
    Plug 'junegunn/vim-easy-align'

    " simplifies Langauge Server configuration
    Plug 'neovim/nvim-lspconfig'

    " fuzzy finder
    Plug 'nvim-lua/plenary.nvim'
    Plug 'nvim-telescope/telescope.nvim'

    " completions
    Plug 'hrsh7th/cmp-nvim-lsp'
    Plug 'hrsh7th/cmp-buffer'
    Plug 'hrsh7th/cmp-path'
    Plug 'hrsh7th/cmp-cmdline'
    Plug 'hrsh7th/nvim-cmp'

    " snipets
    Plug 'hrsh7th/vim-vsnip'

    " inline key help
    Plug 'folke/which-key.nvim'

    " testing
    Plug 'ggandor/lightspeed.nvim'
    Plug 'tpope/vim-repeat'
call plug#end()

lua require 'user.cmp'
lua require 'user.keymaps'
lua require 'user.lspconfig'
lua require 'user.telescope'
lua require 'user.which-key'
lua require 'user.theme'
lua require 'user.opt'

let g:mapleader = "\<Space>"

" configure preview (for netrw)
let g:netrw_preview   = 1
let g:netrw_winsize   = 30

" use pwsh as shell
" set shell=cmd.exe
" set shellcmdflag=/c\ pwsh.exe\ -NoLogo\ -NoProfile\ -NonInteractive\ -ExecutionPolicy\ RemoteSigned\ -Command
" set shellpipe=|
" set shellredir=>


" enter insert after :term
autocmd TermOpen * startinsert


" some keys
tnoremap <silent>  <C-\><C-n>
tnoremap <silent>  <C-\><C-n>:bd!<CR>


" change cursor back to pwsh default on leaving vim
autocmd VimLeave * set guicursor=a:ver100


" set language to english
set spelllang=en_us
set langmenu=en_US
let $LANG = 'en_US'




set mouse=
" disable mouse, except mousewheel
" set mouse=a
" nnoremap <leftmouse> <nop>
" nnoremap <middlemouse> <nop>
" nnoremap <rightmouse> <nop>

" Removes trailing spaces
function! TrimWhiteSpace()
  %s/\([^ ]\)\s*$/\1/
  ''
endfunction

augroup user_trimws
    autocmd!
    autocmd BufWritePre * :call TrimWhiteSpace()
augroup END


" remove black background when `git commit`
highlight Normal guibg=None


" vba file extensions
au BufRead,BufNewFile *.ACM set filetype=vba
au BufRead,BufNewFile *.ACR set filetype=vba
au BufRead,BufNewFile *.ACF set filetype=vba

" vb file extensions
au BufRead,BufNewFile *.cls set filetype=vb
au BufRead,BufNewFile *.bas set filetype=vb
au BufRead,BufNewFile *.vbp set filetype=vbp

" to file extensions
au BufRead,BufNewFile *.article set filetype=article
