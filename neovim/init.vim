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
lua require 'user.autocmd'

set mouse=
" disable mouse, except mousewheel
" set mouse=a
" nnoremap <leftmouse> <nop>
" nnoremap <middlemouse> <nop>
" nnoremap <rightmouse> <nop>
