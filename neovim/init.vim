call plug#begin('~/AppData/Local/nvim/plugged')
    Plug 'tomasiser/vim-code-dark' " theme like vscode dark
    Plug 'junegunn/vim-easy-align' " allows align e.g. vipga=
    Plug 'neovim/nvim-lspconfig'   " Simplifies Langauge Server configuration

    " fuzzy finder
    Plug 'nvim-lua/plenary.nvim'
    Plug 'nvim-telescope/telescope.nvim'

    " completions
    Plug 'hrsh7th/cmp-nvim-lsp'
    Plug 'hrsh7th/cmp-buffer'
    Plug 'hrsh7th/cmp-path'
    Plug 'hrsh7th/cmp-cmdline'
    Plug 'hrsh7th/nvim-cmp'
call plug#end()

lua require('wpuchinger')

" <vim-easy-align>
" Start interactive EasyAlign in visual mode (e.g. vipga=)
xmap ga <Plug>(EasyAlign)

" Start interactive EasyAlign for a motion/text object (e.g. gaip=)
nmap ga <Plug>(EasyAlign)
" </vim-easy-align>

" <telescope>
nnoremap <leader>ff <cmd>Telescope find_files theme=ivy<cr>
nnoremap <leader>fc <cmd>Telescope current_buffer_fuzzy_find theme=ivy<cr>
nnoremap <leader>fg <cmd>Telescope live_grep  theme=ivy<cr>
nnoremap <leader>fb <cmd>Telescope buffers    theme=ivy<cr>
nnoremap <leader>fs <cmd>Telescope git_status theme=ivy<cr>
nnoremap <leader>fm <cmd>Telescope marks      theme=ivy<cr>
nnoremap <leader>fr <cmd>Telescope registers  theme=ivy<cr>
nnoremap <leader>ft <cmd>Telescope builtin    theme=ivy<cr>
" </telescope>

nnoremap <leader>cd <cmd>cd %:p:h<cr>


" <nvim-cmp>
set completeopt=menu,menuone,noselect
" </nvim-cmp>

" set termguicolors
set termguicolors

" enable syntax and plugins (for netrw)
syntax enable
filetype plugin on

" configure preview (for netrw)
let g:netrw_preview   = 1
let g:netrw_winsize   = 30

" Search down into subfolders
" Provides tab-completion for all file-related tasks
" set path+=**

" Display all matching files when we tab complete
set wildmenu

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
nmap <F6> :w \| :tabe \| :term git add -p .<CR>

" change cursor back to pwsh default on leaving vim
au VimLeave * set guicursor=a:ver100

" set language to english
set spelllang=en_us
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

" vb file extensions
au BufRead,BufNewFile *.cls set filetype=vb
au BufRead,BufNewFile *.bas set filetype=vb
