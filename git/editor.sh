#!/bin/sh
echo -ne "\\033]0;[neovim]\\007";
C:/tools/neovim/nvim-win64/bin/nvim.exe \
                +'set spell' \
                +'set termguicolors' \
                $1 \
                ;
