-- Vim filetype plugin file
--     Language: Windows PowerShell
--   Maintainer:	Wolfgang Puchinger <wpuchinger@rocom-service.de>

-- run script with F5
local opts = { noremap = true, silent = true }
vim.api.nvim_buf_set_keymap(0, "n", "<F5>", ":w<bar>:term pwsh -NoProfile -File %:p", opts)
