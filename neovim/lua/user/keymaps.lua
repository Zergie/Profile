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
keymap("n", "<C-Up>", ":resize -2<CR>", opts)
keymap("n", "<C-Down>", ":resize +2<CR>", opts)
keymap("n", "<C-Left>", ":vertical resize -2<CR>", opts)
keymap("n", "<C-Right>", ":vertical resize +2<CR>", opts)

-- Navigate buffers
keymap("n", "<S-l>", ":bnext<CR>", opts)
keymap("n", "<S-h>", ":bprevious<CR>", opts)

-- Move text up and down
keymap("n", "<A-j>", ":m-2<cr>", opts)
keymap("n", "<A-k>", ":m+1<cr>", opts)

-- Change working Directory
keymap("n", "<Space>cd", ":cd %:p:h<cr>", opts)

-- Telescope
keymap("n", "<Space>fc", ":Telescope current_buffer_fuzzy_find theme=ivy<cr>", opts)
keymap("n", "<Space>ff", ":Telescope find_files                theme=ivy<cr>", opts)
keymap("n", "<Space>fg", ":Telescope live_grep                 theme=ivy<cr>", opts)
keymap("n", "<Space>ft", ":Telescope builtin                   theme=ivy<cr>", opts)
keymap("n", "<Space>m", " :Telescope marks                     theme=ivy<cr>", opts)
keymap("n", "<Space>b", " :Telescope buffers                   theme=ivy<cr>", opts)
keymap("n", "<Space>r", " :Telescope resume                    theme=ivy<cr>", opts)

-- Syntax info
keymap("n", "<F10>", [[
:echo "hi<" . synIDattr(synID(line("."),col("."),1),"name") . '> trans<' . synIDattr(synID(line("."),col("."),0),"name") . "> lo<" . synIDattr(synIDtrans(synID(line("."),col("."),1)),"name") . ">"<CR>
]], opts)
