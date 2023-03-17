vim.o.background = 'dark'
local c = require('vscode.colors').get_colors()
require('vscode').setup({
    -- Enable transparent background
    transparent = true,

    -- Enable italic comment
    italic_comments = false,

    -- Disable nvim-tree background color
    disable_nvimtree_bg = true,

    -- Override colors (see ./lua/vscode/colors.lua)
    color_overrides = {
    },

    -- Override highlight groups (see ./lua/vscode/theme.lua)
    group_overrides = {
        -- this supports the same val table as vim.api.nvim_set_hl
        -- use colors from this colorscheme by requiring vscode.colors!
        Cursor      = { fg = c.vscDarkBlue, bg = c.vscLightGreen, bold = true },
        CursorLine  = { bg = c.vscLeftMid },
        ColorColumn = { bg = c.vscPopupBack },

        -- Plug hop
        HopNextKey  = { fg = c.vscRed },
        HopNextKey1 = { fg = c.vscRed },
        HopNextKey2 = { fg = c.vscRed },
    }
})
require('vscode').load('dark')
