-- Vim filetype plugin file
--     Language: VimScript
--   Maintainer: Wolfgang Puchinger <wpuchinger@rocom-service.de>

-- source script with F5
local opts = { noremap = true, silent = true }
vim.api.nvim_buf_set_keymap(0, "n", "<F5>", ":wa<bar>:so %<cr>", opts)
