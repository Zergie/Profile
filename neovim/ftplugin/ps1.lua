-- Vim filetype plugin file
--     Language: Windows PowerShell
--   Maintainer: Wolfgang Puchinger <wpuchinger@rocom-service.de>

local map = function (mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc} ) end

map("n", "<Leader>mk", function ()
    vim.cmd("wa")
    require('FTerm').run("; . '" .. vim.fn.expand("%:p") .. "'")
end,  "Run script")
