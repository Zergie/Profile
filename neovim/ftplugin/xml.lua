-- Vim filetype plugin file
--     Language:	xml
--   Maintainer:	Wolfgang Puchinger <wpuchinger@rocom-service.de>

-- use tabs instead of spaces
vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop    = 2
vim.opt_local.expandtab  = false

-- run tests with F5
local opts = { noremap = true, silent = true }
vim.api.nvim_buf_set_keymap(0, "n", "<F5>", ":!pwsh -NoProfile -NonInteractive -File C:/GIT/TauOffice/DBMS/tests/Run-Tests.ps1<cr>", opts)
