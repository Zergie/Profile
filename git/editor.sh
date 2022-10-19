#!/bin/sh
echo -ne "\\033]0;[neovim]\\007";
C:/tools/neovim/nvim-win64/bin/nvim.exe \
                +'startinsert' \
                +'set spell' \
                +'set termguicolors' \
                +'inoremap <C-S> <ESC>:wq<CR>' \
                +'inoremap <C-_> <C-o>z=' \
                +'map <ESC> :q!<CR>' \
                $1 \
                ; 