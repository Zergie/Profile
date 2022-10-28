vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.colorcolumn = '100'
vim.opt.scrolloff = 8
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- remap leader to space
vim.g.mapleader = ' '

-- configure preview for netrw
vim.g.netrw_preview = 1
vim.g.netrw_winsize = 30

-- language settings
vim.opt.spelllang = 'en_us'
vim.opt.langmenu = 'en_US'
vim.api.nvim_exec('language en_US', true)

-- display all matching files when we tab complete
vim.opt.wildmenu = true

-- search case insensitiv
vim.opt.ignorecase = true
-- examples:
--  /copyright      " Case insensitive
--  /Copyright      " Case sensitive
--  /copyright\C    " Case sensitive
--  /Copyright\c    " Case insensitive

vim.opt.signcolumn = 'number'

-- Plug which-key
vim.opt.timeoutlen = 250

-- Plug nvim-cmp
vim.opt.completeopt = 'menu,menuone,noselect'

