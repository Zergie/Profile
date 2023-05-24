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
local map    = function (mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc} ) end
--local mapbuf = function (mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc, buffer = 0} ) end

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
keymap("n", "<C-h>", "<C-w>h", opts)
keymap("n", "<C-j>", "<C-w>j", opts)
keymap("n", "<C-k>", "<C-w>k", opts)
keymap("n", "<C-l>", "<C-w>l", opts)

-- Resize with arrows
keymap("n", "<C-Up>",    "<cmd>resize -2<cr>",          opts)
keymap("n", "<C-Down>",  "<cmd>resize +2<cr>",          opts)
keymap("n", "<C-Left>",  "<cmd>vertical resize -2<cr>", opts)
keymap("n", "<C-Right>", "<cmd>vertical resize +2<cr>", opts)

-- Navigate buffers
map("n", "<S-l>",  "<cmd>bnext<cr>",     "Next buffer")
map("n", "<S-h>",  "<cmd>bprevious<cr>", "Prev buffer")
map("n", "<C-b>c", "<cmd>bp<bar>sp<bar>bn<bar>bd<cr>", "Close buffer")
map("n", "<C-b>C", "<cmd>bp<bar>sp<bar>bn<bar>bd!<cr>", "Close buffer!")

-- Move text up and down
map("n", "<A-j>", "<cmd>m-2<cr>", "Move text one line up")
map("n", "<A-k>", "<cmd>m+1<cr>", "Move text one line down")

-- some terminal keys
keymap("t", "<ESC>", "<C-\\><C-n>",         opts)
-- keymap("t", "<ESC>", "<cmd>bp<bar>sp<bar>bn<bar>bd!<CR>", opts)
map("n", "<Leader>t", "<cmd>FloatermNew --autoclose=2 pwsh<cr>", "Open a floating pwsh -NoProfile")
map("n", "<Leader>T", "<cmd>FloatermNew --autoclose=2 \"pwsh.exe\"<cr>", "Open a floating pwsh")

-- Change working Directory
map("n", "<Leader>cd", "<cmd>cd %:p:h<cr>", "Change working directory")

-- quick save
map("n", "ZS", "<cmd>w<cr>", "Save file")

-- open file explorer
map("n", "<Leader>x", "<cmd>Ex<cr>",  "File Explorer")
-- map("n", "<Leader>es", "<cmd>Sex<cr>", "File Explorer (split)")
-- map("n", "<Leader>el", "<cmd>Lex<cr>", "File Explorer (Lex)")

-- Syntax info
keymap("n", "<F10>", [[
:echo "hi<" . synIDattr(synID(line("."),col("."),1),"name") . '> trans<' . synIDattr(synID(line("."),col("."),0),"name") . "> lo<" . synIDattr(synIDtrans(synID(line("."),col("."),1)),"name") . ">"<cr>
]], opts)

-- Telescope
local telescope = require('telescope.builtin')
local minimal_theme = require('telescope.themes').get_dropdown {
    winblend  = 10,
    previewer = false,
    layout_config = {
      width = 0.5,
    },
}
local cursor_theme = require('telescope.themes').get_cursor {
    winblend  = 10,
    previewer = true,
    layout_config = {
      height = 0.5,
      width  = 0.8,
    },
}
local cursor_minimal_theme = require('telescope.themes').get_cursor {
    winblend  = 20,
    previewer = false,
    layout_config = {
      height = 0.25,
      -- width  = 0.8,
    },
}

map('n', '<leader>/',       function() telescope.current_buffer_fuzzy_find(minimal_theme) end, '[/] Fuzzily search in current buffer]' )
map('n', '<leader><space>', function() telescope.buffers(minimal_theme) end,                   '[ ] Find existing buffers')
map('n', '<leader>sf',      function() telescope.find_files(minimal_theme) end,                '[S]earch [F]iles' )
map('n', '<leader>so',      function() telescope.oldfiles(minimal_theme) end,                  '[S]earch in old files')
map('n', 'z=',              function() telescope.spell_suggest(cursor_minimal_theme) end,      'Spell Suggest')

--map("n",               "<Leader>s",       telescope.current_buffer_fuzzy_find, "current_buffer_fuzzy_find [Telescope]")
--map("n",               "<Leader>o",       telescope.find_files,                "find_files [Telescope]")
--map("n",               "<Leader>g",       telescope.live_grep,                 "live_grep [Telescope]")
map("n", "<Leader>sb", telescope.builtin,                 "builtin [Telescope]")
map("n", "<Leader>sm", telescope.marks,       "[S]earch [M]arks")
map("n", "<Leader>sr",  telescope.resume,      "[S]earch [R]esume")
map('n', '<leader>sh', telescope.help_tags,   '[S]earch [H]elp' )
--map('n', '<leader>sw', telescope.grep_string, '[S]earch current [W]ord' )
map('n', '<leader>sw', function() telescope.grep_string(cursor_theme) end, '[S]earch current [W]ord' )
map('n', '<leader>sg', telescope.live_grep,   '[S]earch by [G]rep' )
map('n', '<leader>sd', telescope.diagnostics, '[S]earch [D]iagnostics' )

-- LSP
map("n", "<Leader>e",  vim.diagnostic.open_float,                                               "Open diagnostics [LSP]")
map("n", "[d",         vim.diagnostic.goto_prev,                                                "Prev diagnostics [LSP]")
map("n", "]d",         vim.diagnostic.goto_next,                                                "Next diagnostics [LSP]")
map("n", "<Leader>q",  vim.diagnostic.setloclist,                                               "setloclist [LSP]")
map("n", "gD",         vim.lsp.buf.declaration,                                                 "Goto declaration [LSP]")
map("n", "gd",         vim.lsp.buf.definition,                                                  "Goto definition [LSP]")
map("n", "K",          vim.lsp.buf.hover,                                                       "Hover [LSP]")
map("n", "gi",         vim.lsp.buf.implementation,                                              "Goto implementation [LSP]")
map("n", "gk",         vim.lsp.buf.signature_help,                                              "Signature help [LSP]")
map("n", "<Leader>aa", vim.lsp.buf.add_workspace_folder,                                        "add_workspace_folder [LSP]")
map("n", "<Leader>ar", vim.lsp.buf.remove_workspace_folder,                                     "remove_workspace_folder [LSP]")
map("n", "<Leader>al", function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, "list_workspace_folders [LSP]")
map("n", "<Leader>D",  vim.lsp.buf.type_definition,                                             "type_definition [LSP]")
map("n", "<Leader>rn", vim.lsp.buf.rename,                                                      "Rename [LSP]")
map("n", "<Leader>ca", vim.lsp.buf.code_action,                                                 "Code action [LSP]")
map("n", "gr",         vim.lsp.buf.references,                                                  "References [LSP]")

-- Hop
local hop = require("hop")
hop.setup()
-- local directions = require("hop.hint").HintDirection
-- vim.keymap.set("", "<Leader>f", function() hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true }) end, opts)
-- vim.keymap.set("", "<Leader>F", function() hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true }) end, opts)
-- vim.keymap.set("", "<Leader>t", function() hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true, hint_offset = -1 }) end, opts)
-- vim.keymap.set("", "<Leader>T", function() hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 }) end, opts)
map("n", "<Leader>w", "<cmd>HopWordAC<cr>",  "Hop word forward [Hop]")
map("n", "<Leader>W", "<cmd>HopWordBC<cr>",  "Hop word backward [Hop]")
map("n", "<Leader>j", "<cmd>HopLineAC<cr>",  "Hop word forward [Hop]")
map("n", "<Leader>k", "<cmd>HopLineBC<cr>",  "Hop word backward [Hop]")
map("n", "s",         "<cmd>HopChar2AC<cr>", "Hop 2chars forward [Hop]")
map("n", "S",         "<cmd>HopChar2BC<cr>", "Hop 2chars backward [Hop]")
map("v", "<Leader>w", "<cmd>HopWordAC<cr>",  "Hop word forward [Hop]")
map("v", "<Leader>W", "<cmd>HopWordBC<cr>",  "Hop word backward [Hop]")
map("v", "<Leader>j", "<cmd>HopLineAC<cr>",  "Hop word forward [Hop]")
map("v", "<Leader>k", "<cmd>HopLineBC<cr>",  "Hop word backward [Hop]")
map("v", "s",         "<cmd>HopChar2AC<cr>", "Hop 2chars forward [Hop]")
map("v", "S",         "<cmd>HopChar2BC<cr>", "Hop 2chars backward [Hop]")

-- Easy Align
map("x", "ga", "<Plug>(EasyAlign)", "Align [EasyAlign]")
map("n", "ga", "<Plug>(EasyAlign)", "Align [EasyAlign]")

-- Fugitive
map("n", "<Leader>l", "<cmd>0Gclog -- %<cr>", "git log [Fugitive]")
map("n", "[q",        "<cmd>cprev<cr>",       "Prev qf item")
map("n", "]q",        "<cmd>cnext<cr>",       "Next qf item")
map("n", "[Q",        "<cmd>cfirst<cr>",      "First qf item")
map("n", "]Q",        "<cmd>clast<cr>",       "Last qf item")
