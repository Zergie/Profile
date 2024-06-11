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
map("n", "<Leader>cP", function () cmd("cd C:|cd /GIT/Profile/|cd")                        end, "Workspace Profile")
map("n", "<Leader>cA", function () cmd("cd C:|cd /GIT/TauOffice/Admintool/|cd")            end, "Workspace Admintool")
map("n", "<Leader>cS", function () cmd("cd C:|cd /GIT/TauServer/|cd")                      end, "Workspace Tau-Server")
map("n", "<Leader>cc", function () cmd("cd C:|cd /GIT/TauOffice/tau-office-controls/|cd")  end, "Workspace tau-office-controls")
map("n", "<Leader>ci", function () cmd("cd C:|cd /GIT/TauOffice/tau-office-installer/|cd") end, "Workspace tau-office-installer")
map("n", "<Leader>cp", function () cmd("cd C:|cd /GIT/TauOffice/tau-office-plugins/|cd")   end, "Workspace tau-office-plugins")
map("n", "<Leader>ct", function () cmd("cd C:|cd /GIT/TauOffice/tau-office/source/|cd")    end, "Workspace tau-office")
map("n", "<Leader>cx", function () cmd("cd C:|cd /GIT/TauOffice/struktur|cd")              end, "Workspace struktur")

-- Remap space
keymap("", "<Space>", "<nop>", opts)

-- Remap for dealing with word wrap
keymap('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
keymap('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- -- Automatically closing braces
-- keymap('i', '{}', '{}<C-G>U<Left>')
-- keymap('i', '()', '()<C-G>U<Left>')
-- keymap('i', '[]', '[]<C-G>U<Left>')
-- keymap('i', '""', '""<C-G>U<Left>')
-- keymap('i', "''", "''<C-G>U<Left>")

-- Keymaps for select mode
keymap('n', "<F9>", "*``gn<C-g>")
keymap('i', "<F9>", "<C-o>gn<C-g>")

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
map("n",    "<C-w><C-w>", "<cmd>w<bar>close<cr>", "Save and Close window")
map("n",    "<C-w>c",     "<cmd>close!<cr>",      "Save and Close window")

-- Resize with arrows
keymap("n", "<C-Up>",    "<cmd>resize -2<cr>",          opts)
keymap("n", "<C-Down>",  "<cmd>resize +2<cr>",          opts)
keymap("n", "<C-Left>",  "<cmd>vertical resize -2<cr>", opts)
keymap("n", "<C-Right>", "<cmd>vertical resize +2<cr>", opts)

-- Navigate
map("n", "<S-l>",      "<cmd>bn<cr>",                       "Next buffer")
map("n", "<S-h>",      "<cmd>bp<cr>",                       "Prev buffer")
map("n", "<C-b><C-b>", "<cmd>w<bar>bd<cr>",                 "Save and Close buffer")
map("n", "<C-b>c",     "<cmd>bp<bar>sp<bar>bn<bar>bd!<cr>", "Close buffer")
map("n", "gl",         "`.",                                "Goto last Change")
map("n", "<M-Up>",     "4")
map("n", "<M-Down>",   "4")
map("n", "]c",         function ()
vim.cmd('/<<<<<<< ')
local lb, x = unpack(vim.api.nvim_win_get_cursor(0))
vim.cmd('/=======')
local lm, x = unpack(vim.api.nvim_win_get_cursor(0))
vim.cmd('/>>>>>>> ')
local le, x = unpack(vim.api.nvim_win_get_cursor(0))
vim.cmd('noh')
vim.cmd('normal '.. lb+1 ..'ggV'.. lm-1 ..'gg"ay')
vim.cmd('normal '.. lm+1 ..'ggV'.. le-1 ..'gg"by')
vim.cmd('normal '.. lb   ..'ggV'.. le   ..'gg')
end)
map("n", "[c",         function ()
vim.cmd('?<<<<<<< ')
local lb, x = unpack(vim.api.nvim_win_get_cursor(0))
vim.cmd('/=======')
local lm, x = unpack(vim.api.nvim_win_get_cursor(0))
vim.cmd('/>>>>>>> ')
local le, x = unpack(vim.api.nvim_win_get_cursor(0))
vim.cmd('noh')
vim.cmd('normal '.. lb+1 ..'ggV'.. lm-1 ..'gg"ay')
vim.cmd('normal '.. lm+1 ..'ggV'.. le-1 ..'gg"by')
vim.cmd('normal '.. lb   ..'ggV'.. le   ..'gg')
end)


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
