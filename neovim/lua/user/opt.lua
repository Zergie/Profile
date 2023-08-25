-- [[ Setting options ]]
-- See `:help vim.o`

vim.wo.number = true              -- Make line numbers default
vim.o.mouse = ''                  -- Disable mouse mode
vim.o.breakindent = true          -- Enable break indent
vim.o.undofile = true             -- Save undo history
vim.o.ignorecase = true           -- Case insensitive searching UNLESS /C or capital in search
vim.o.smartcase = true
vim.o.updatetime = 250            -- Decrease update time
vim.wo.signcolumn = 'yes'
vim.opt.autoread = true           -- When a file has been detected to have been changed outside of Vim and
                                  -- it has not been changed inside of Vim, automatically read it again.

vim.opt.number         = true     -- Line numbers
vim.opt.relativenumber = true     -- Relative line numbers for better navigation
vim.opt.colorcolumn    = '100'    -- Mark column to remember me keeping lines short
vim.opt.scrolloff      = 8        --
vim.opt.tabstop        = 4        -- Insert 2 spaces for a tab
vim.opt.shiftwidth     = 4        -- Change the number of space characters inserted for indentation
vim.opt.expandtab      = true     -- Converts tabs to spaces
vim.opt.smartindent    = true     --
vim.g.mapleader        = ' '      -- remap leader to space
vim.g.maplocalleader   = ' '      --
vim.opt.wildmenu       = true     -- Display all matching files when we tab complete
vim.opt.signcolumn     = 'yes'    -- Display errors/warnings from lsp in front of the line number
vim.opt.pumheight      = 15       -- Makes popup menu smaller
vim.opt.splitright     = true     -- Vertical splits will automatically be to the right
vim.opt.cursorline     = true     -- Enable highlighting of the current line

-- look for .exrc files
vim.o.exrc = true

-- configure preview for netrw
vim.g.netrw_preview = 1
vim.g.netrw_winsize = 30

-- language settings
vim.opt.spell = false
vim.opt.spelllang = { 'en_us' }
vim.opt.langmenu  = 'en_US'
vim.api.nvim_exec('language en_US', true)


-- search case insensitiv
vim.opt.ignorecase = true
-- examples:
--  /copyright      " Case insensitive
--  /Copyright      " Case sensitive
--  /copyright\C    " Case sensitive
--  /Copyright\c    " Case insensitive

-- Stop newline continution of comments
vim.opt.formatoptions:remove "c"
vim.opt.formatoptions:remove "r"
vim.opt.formatoptions:remove "o"

-- Plug easy-align
local easy_align_delimiters = {}
easy_align_delimiters[';'] = {
    pattern       = ";",
    ignore_groups = {'!Comment'}
}
vim.api.nvim_set_var('easy_align_delimiters', easy_align_delimiters)

-- Plug which-key
vim.opt.timeoutlen = 250

-- Plug nvim-cmp
vim.opt.completeopt = 'menu,menuone,noselect'

