-- Vim filetype plugin file
--     Language: Visual Basic for Application
--   Maintainer:	Wolfgang Puchinger <wpuchinger@rocom-service.de>

local telescope = require('telescope.builtin')
local themes = require('telescope.themes')

local map = function (mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer=0, noremap = true, silent = true, desc = desc })
end
local remap = function (mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer=0, noremap = false, silent = true, desc = desc })
end

local search = function (pattern, prompt)
    telescope.grep_string(themes.get_dropdown {
	path_display = { "truncate" },
	prompt_title = prompt,
	search = pattern,
	use_regex = true,
	encoding = 'latin1',
	disable_coordinates = true,
    })
end

local searchInBuffer = function (pattern, prompt)
    vim.cmd("w")
    telescope.grep_string(themes.get_dropdown {
	path_display = { "hidden" },
	prompt_title = prompt,
	cwd = vim.fn.expand('%:p:h'),
	search_dirs = { vim.fn.expand('%:p'), },
	search = pattern,
	use_regex = true,
	encoding = 'latin1',
	disable_coordinates = true,
    })
end

map("n", "<Leader>ds", function ()
    searchInBuffer('^(|Private |Global |Public )(Enum|Sub|Function|Property Get|Property Set|Property Let) ([^(]+)', 'Document symbols')
end, "[D]ocument [S]ymbols")

map("n", "<Leader>dp", function ()
    searchInBuffer('^(|Global |Public )(Enum|Sub|Function|Property Get|Property Set|Property Let) ([^(]+)', 'Document public symbols')
end,  "[D]ocument [P]ublic symbols")

map("n", "<Leader>ws", function ()
    search('^(|Global |Public )(Enum|Sub|Function|Property Get|Property Set|Property Let) ([^(]+)', 'Workspace symbols')
end, "[W]orkspace [S]ymbols")

map("n", "<Leader>sd", function ()
    local wordUnderCursor = vim.fn.expand("<cword>")
    search('^(|Global |Public |Private )(Enum|Sub|Function|Property Get|Property Set|Property Let) ' .. wordUnderCursor, 'Search in definitions (' .. wordUnderCursor .. ')')
end, "[S]earch [D]efinition")

map('n', '<leader>sW', function()
    local wordUnderCursor = vim.fn.expand("<cword>")
    telescope.grep_string(themes.get_dropdown {
	cwd = '/git/TauOffice/DBMS/schema',
	search_dirs = { 'schema.xml', },
	prompt_title = 'Search in schema.xml (' .. wordUnderCursor .. ')',
	winblend  = 10,
	previewer = true,
	layout_config = {
	    height = 0.5,
	    width  = 0.8,
	},
    })
end, '[S]earch current [W]ord in database' )

map('n', '<leader>sG', function()
    telescope.live_grep{
	cwd = '/git/TauOffice/DBMS/schema',
	search_dirs = { 'schema.xml', },
	prompt_title = 'Search by grep in schema.xml',
    }
end, '[S]earch by [G]rep in database' )

map("n", "go", function ()
    vim.cmd("/CodeBehindForm")
    vim.cmd("exe 'normal! zt'")
    vim.cmd("noh")
end, "Go to start of code")

map('n', 'gr', function()
    local wordUnderCursor = vim.fn.expand("<cword>")
    search("[( ]+" .. wordUnderCursor .. "[( ]", 'Search Reference (' .. wordUnderCursor .. ')')
end, '[S]earch [R]eference' )

map('n', 'gd', function()
    local wordUnderCursor = vim.fn.expand("<cword>")
    search("(Dim|Private|Public|Global|Enum|Sub|Function|Property Get|Property Set|Property Let)[ ]+" .. wordUnderCursor, 'Search Definition (' .. wordUnderCursor .. ')')
end, '[S]earch [D]efinition' )

vim.opt_local.spell = false
vim.o.commentstring = "'%s"


function VBA_selectTag(around)
    local function MatchAny( str, pattern_list )
	for _, pattern in ipairs( pattern_list ) do
	    local w = string.match( str, pattern )
	    if w then return w end
	end
    end

    while MatchAny(vim.api.nvim_get_current_line(), { "^ *Begin ?", "Enum ", "Sub ", "Function ", "Property " }) == nil do
	vim.cmd('-')
    end
    local sel_start = vim.fn.line('.')

    if MatchAny(vim.api.nvim_get_current_line(), { "^ *Begin ?"  }) then
	local count = 1

	while count > 0 do
	    vim.cmd('+')
	    if MatchAny(vim.api.nvim_get_current_line(), { "Begin ?" }) then
		count = count + 1
	    elseif MatchAny(vim.api.nvim_get_current_line(), { " End" }) then
		count = count - 1
	    end
	end
    else
	while MatchAny(vim.api.nvim_get_current_line(), { "^End Sub", "^End Function", "^End Property", "^End Enum" }) == nil do
	    vim.cmd('+')
	end
    end

    local sel_end = vim.fn.line('.')
    if around then
	vim.cmd('+')
	while string.len(vim.api.nvim_get_current_line()) == 0 do
	    sel_end = sel_end + 1
	    vim.cmd('+')
	end
    else
	sel_start = sel_start + 1
	sel_end = sel_end - 1
    end

    vim.cmd('normal! ' .. sel_start .. 'gg0V' .. sel_end .. 'gg')
end

for _, mode in ipairs({ 'x', 'o' }) do
    remap(mode, 'it', ':<c-u>lua VBA_selectTag(false)<cr>', "vba tag")
    remap(mode, 'at', ':<c-u>lua VBA_selectTag(true)<cr>', "vba tag")
end
