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

    " extended vim motions
    Plug 'phaazon/hop.nvim'

    " git integration
    Plug 'tpope/vim-fugitive'
call plug#end()

lua require 'user.opt'
lua require 'user.cmp'
lua require 'user.lspconfig'
lua require 'user.telescope'
lua require 'user.which-key'
lua require 'user.theme'
lua require 'user.keymaps'

" enter insert after :term
autocmd TermOpen * startinsert

" change cursor back to pwsh default on leaving vim
autocmd VimLeave * set guicursor=a:ver100

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
