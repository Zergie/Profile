-- Modes
--   normal_mode       = "n"
--   insert_mode       = "i"
--   visual_mode       = "v"
--   visual_block_mode = "x"
--   term_mode         = "t"
--   command_mode      = "c"

-- Shorten function name
local map    = function (mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { noremap = false, silent = true, desc = desc } ) end
local cmd = vim.cmd
--local mapbuf = function (mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc, buffer = 0} ) end

-- Workspaces
-- map("n", "<Leader>cA", function () cmd("cd C:|cd /GIT/TauOffice/Admintool/|cd")               end, "Workspace Admintool")
-- map("n", "<Leader>cP", function () cmd("cd C:|cd /GIT/Profile/|cd")                           end, "Workspace Profile")
-- map("n", "<Leader>cS", function () cmd("cd C:|cd /GIT/TauServer/|cd")                         end, "Workspace Tau-Server")
-- map("n", "<Leader>cc", function () cmd("cd C:|cd /GIT/TauOffice/tau-office-controls/|cd")     end, "Workspace tau-office-controls")
-- map("n", "<Leader>ci", function () cmd("cd C:|cd /GIT/TauOffice/tau-office-installer/|cd")    end, "Workspace tau-office-installer")
-- map("n", "<Leader>cp", function () cmd("cd C:|cd /GIT/TauOffice/tau-office-plugins/|cd")      end, "Workspace tau-office-plugins")
-- map("n", "<Leader>cu", function () cmd("cd C:|cd /GIT/TauOffice/tau-office-utils/source/|cd") end, "Workspace tau-office")
-- map("n", "<Leader>ct", function () cmd("cd C:|cd /GIT/TauOffice/tau-office/source/|cd")       end, "Workspace tau-office")
-- map("n", "<Leader>cx", function () cmd("cd C:|cd /GIT/TauOffice/struktur|cd")                 end, "Workspace struktur")

-- Remap space
map("", "<Space>", "<nop>")

-- Keymaps for select mode
map('n', "<F9>", "*``gn<C-g>")
map('i', "<F9>", "<C-o>gn<C-g>")

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
map("n", "<C-h>",      "<C-w>h")
map("n", "<C-j>",      "<C-w>j")
map("n", "<C-k>",      "<C-w>k")
map("n", "<C-l>",      "<C-w>l")
map("n",    "<C-w><C-w>", "<cmd>w<bar>close<cr>", "Save and Close window")
map("n",    "<C-w>c",     "<cmd>close!<cr>",      "Save and Close window")

-- Resize with arrows
map("n", "<C-Up>",    "<cmd>resize -2<cr>")
map("n", "<C-Down>",  "<cmd>resize +2<cr>")
map("n", "<C-Left>",  "<cmd>vertical resize -2<cr>")
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>")

-- Navigate
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
map("t", "<ESC>", "<C-\\><C-n>")

-- Change working Directory
-- map("n", "<Leader>cd", "<cmd>cd %:p:h<cr>", "Change working directory")

-- quick save
map("n", "ZS", "<cmd>w<cr>", "Save file")

-- open file explorer
-- map("n", "<Leader>x", "<cmd>Ex<cr>",  "File Explorer")
-- map("n", "<Leader>es", "<cmd>Sex<cr>", "File Explorer (split)")
-- map("n", "<Leader>el", "<cmd>Lex<cr>", "File Explorer (Lex)")

-- Syntax info
-- map("n", "<F13>",
-- :echo "hi<" . synIDattr(synID(line("."),col("."),1),"name") . '> trans<' . synIDattr(synID(line("."),col("."),0),"name") . "> lo<" . synIDattr(synIDtrans(synID(line("."),col("."),1)),"name") . ">"<cr>
-- ]])
map({"v", "x", "n"}, "<Leader>ge", function()
  print([[Press key e.g. "]])
  local char = vim.fn.getcharstr()

  if vim.fn.mode() == 'v' or vim.fn.mode() == 'V' or vim.fn.mode() == '' then
    -- Visual modes
    vim.cmd("'<, '>s/\\(\\w\\|\\d\\)/" .. char .. "\\1/")
    vim.cmd("'<, '>s/$/" .. char .. "/")
    vim.cmd("noh")
  else
    -- Normal mode
    vim.cmd("s/\\(\\w\\|\\d\\)/" .. char .. "\\1/")
    vim.cmd("s/$/" .. char .. "/")
    vim.cmd("noh")
  end
end, "Encapsulte lines which char")
