-- Modes
--   normal_mode       = "n"
--   insert_mode       = "i"
--   visual_mode       = "v"
--   visual_block_mode = "x"
--   term_mode         = "t"
--   command_mode      = "c"

local opts    = { noremap = true, silent = true }

-- Shorten function name
local keymap = vim.keymap.set
local map    = function (mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc } ) end
--local mapbuf = function (mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc, buffer = 0} ) end

-- Workspaces
local cmd = vim.cmd
map("n", "<Leader>cP", function () cmd("cd C:|cd /GIT/Profile/")                       end, "Workspace Profile")
map("n", "<Leader>ca", function () cmd("cd C:|cd /GIT/TauOffice/Admintool/")           end, "Workspace Admintool")
map("n", "<Leader>cc", function () cmd("cd C:|cd /GIT/TauOffice/tau-office-controls/") end, "Workspace tau-office-controls")
map("n", "<Leader>cp", function () cmd("cd C:|cd /GIT/TauOffice/tau-office-plugins/")  end, "Workspace tau-office-plugins")
map("n", "<Leader>ct", function () cmd("cd C:|cd /GIT/TauOffice/tau-office/source/")   end, "Workspace tau-office")
map("n", "<Leader>cx", function () cmd("cd C:|cd /GIT/TauOffice/struktur")             end, "Workspace struktur")

-- Remap space
keymap("", "<Space>", "<nop>", opts)

-- Remap for dealing with word wrap
keymap('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
keymap('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- [[ Highlight on yank ]]
-- See `:help vim.highlight.on_yank()`
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.highlight.on_yank()
  end,
  group = highlight_group,
  pattern = '*',
})


-- Better window navigation
keymap("n", "<C-h>",      "<C-w>h",               opts)
keymap("n", "<C-j>",      "<C-w>j",               opts)
keymap("n", "<C-k>",      "<C-w>k",               opts)
keymap("n", "<C-l>",      "<C-w>l",               opts)
keymap("n", "<C-w><C-w>", "<cmd>w<bar>close<cr>", opts, "Save and Close window")
keymap("n", "<C-w>c",     "<cmd>close!<cr>",      opts, "Save and Close window")

-- Resize with arrows
keymap("n", "<C-Up>",    "<cmd>resize -2<cr>",          opts)
keymap("n", "<C-Down>",  "<cmd>resize +2<cr>",          opts)
keymap("n", "<C-Left>",  "<cmd>vertical resize -2<cr>", opts)
keymap("n", "<C-Right>", "<cmd>vertical resize +2<cr>", opts)

-- Navigate buffers
map("n", "<S-l>",      "<cmd>bn<cr>",                       "Next buffer")
map("n", "<S-h>",      "<cmd>bp<cr>",                       "Prev buffer")
map("n", "<C-b><C-b>", "<cmd>w<bar>bd<cr>",                 "Save and Close buffer")
map("n", "<C-b>c",     "<cmd>bp<bar>sp<bar>bn<bar>bd!<cr>", "Close buffer")

-- Move text up and down
map("n", "<A-j>", "<cmd>m-2<cr>", "Move text one line up")
map("n", "<A-k>", "<cmd>m+1<cr>", "Move text one line down")

-- some terminal keys
keymap("t", "<ESC>", "<C-\\><C-n>",         opts)

-- Change working Directory
map("n", "<Leader>cd", "<cmd>cd %:p:h<cr>", "Change working directory")

-- quick save
map("n", "ZS", "<cmd>w<cr>", "Save file")

-- open file explorer
-- map("n", "<Leader>x", "<cmd>Ex<cr>",  "File Explorer")
-- map("n", "<Leader>es", "<cmd>Sex<cr>", "File Explorer (split)")
-- map("n", "<Leader>el", "<cmd>Lex<cr>", "File Explorer (Lex)")

-- Syntax info
keymap("n", "<F13>", [[
:echo "hi<" . synIDattr(synID(line("."),col("."),1),"name") . '> trans<' . synIDattr(synID(line("."),col("."),0),"name") . "> lo<" . synIDattr(synIDtrans(synID(line("."),col("."),1)),"name") . ">"<cr>
]], opts)
