-- Modes
--   normal_mode       = "n"
--   insert_mode       = "i"
--   visual_mode       = "v"
--   visual_block_mode = "x"
--   term_mode         = "t"
--   command_mode      = "c"

local opts = { noremap = true, silent = true }

-- Shorten function name
local keymap = vim.api.nvim_set_keymap

-- Remap space
keymap("", "<Space>", "<nop>", opts)

-- Remap for <ESC>
keymap("n", "<C-j>", "<ESC>", opts)
keymap("i", "<C-j>", "<ESC>", opts)
keymap("v", "<C-j>", "<ESC>", opts)
keymap("x", "<C-j>", "<ESC>", opts)
keymap("t", "<C-j>", "<ESC>", opts)
keymap("c", "<C-j>", "<ESC>", opts)

-- Better window navigation
keymap("n", "<C-h>", "<C-w>h", opts)
keymap("n", "<C-j>", "<C-w>j", opts)
keymap("n", "<C-k>", "<C-w>k", opts)
keymap("n", "<C-l>", "<C-w>l", opts)

-- Resize with arrows
keymap("n", "<C-Up>", ":resize -2<cr>", opts)
keymap("n", "<C-Down>", ":resize +2<cr>", opts)
keymap("n", "<C-Left>", ":vertical resize -2<cr>", opts)
keymap("n", "<C-Right>", ":vertical resize +2<cr>", opts)

-- Navigate buffers
keymap("n", "<S-l>", ":bnext<cr>", opts)
keymap("n", "<S-h>", ":bprevious<cr>", opts)

-- Move text up and down
keymap("n", "<A-j>", ":m-2<cr>", opts)
keymap("n", "<A-k>", ":m+1<cr>", opts)

-- some terminal keys
keymap("t", '<ESC>', '<C-\\><C-n>', opts)
keymap("t", '<ESC>', '<C-\\><C-n>:bd!<CR>', opts)

-- Change working Directory
keymap("n", "<Leader>cd", ":cd %:p:h<cr>", opts)

-- Syntax info
keymap("n", "<F10>", [[
:echo "hi<" . synIDattr(synID(line("."),col("."),1),"name") . '> trans<' . synIDattr(synID(line("."),col("."),0),"name") . "> lo<" . synIDattr(synIDtrans(synID(line("."),col("."),1)),"name") . ">"<cr>
]], opts)

-- Telescope
keymap("n", "<Leader>s", ":Telescope current_buffer_fuzzy_find<cr>", opts)
keymap("n", "<Leader>o", ":Telescope find_files               <cr>", opts)
keymap("n", "<Leader>g", ":Telescope live_grep                <cr>", opts)
--keymap("n", "<Leader>t", ":Telescope builtin                  <cr>", opts)
keymap("n", "<Leader>m", ":Telescope marks                    <cr>", opts)
keymap("n", "<Leader>b", ":Telescope buffers                  <cr>", opts)
keymap("n", "<Leader>r", ":Telescope resume                   <cr>", opts)

-- Hop
local hop = require('hop')
hop.setup()
local directions = require('hop.hint').HintDirection
vim.keymap.set('', '<Leader>f', function() hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true }) end, opts)
vim.keymap.set('', '<Leader>F', function() hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true }) end, opts)
vim.keymap.set('', '<Leader>t', function() hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true, hint_offset = -1 }) end, opts)
vim.keymap.set('', '<Leader>T', function() hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 }) end, opts)
keymap("n", "<Leader>b", ":HopWordBC<cr>", opts)
keymap("n", "<Leader>w", ":HopWordAC<cr>", opts)
keymap("n", "<Leader>j", ":HopLineAC<cr>", opts)
keymap("n", "<Leader>k", ":HopLineBC<cr>", opts)
keymap("n", "s", ":HopChar2AC<cr>", opts)
keymap("n", "S", ":HopChar2BC<cr>", opts)
keymap("v", "<Leader>b", ":HopWordBC<cr>", opts)
keymap("v", "<Leader>w", ":HopWordAC<cr>", opts)
keymap("v", "<Leader>j", ":HopLineAC<cr>", opts)
keymap("v", "<Leader>k", ":HopLineBC<cr>", opts)
keymap("v", "s", ":HopChar2AC<cr>", opts)
keymap("v", "S", ":HopChar2BC<cr>", opts)

-- Easy Align
keymap("x", "ga", "<Plug>(EasyAlign)", opts)
keymap("n", "ga", "<Plug>(EasyAlign)", opts)
