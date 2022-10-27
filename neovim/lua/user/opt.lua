vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.colorcolumn = '100'
vim.opt.scrolloff = 8
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Display all matching files when we tab complete
vim.opt.wildmenu = true

-- search case insensitiv
vim.opt.ignorecase = true
-- examples:
--  /copyright      " Case insensitive
--  /Copyright      " Case sensitive
--  /copyright\C    " Case sensitive
--  /Copyright\c    " Case insensitive

vim.wo.signcolumn = 'number'

-- Plug which-key
vim.opt.timeoutlen = 0

-- Plug nvim-cmp
vim.opt.completeopt = 'menu,menuone,noselect'
