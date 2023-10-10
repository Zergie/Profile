-- Vim filetype plugin file
--     Language: Python
--   Maintainer: Wolfgang Puchinger <wpuchinger@rocom-service.de>

local map = function (mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc} ) end

map("n", "<Leader>mr", function ()
    vim.cmd("wa")
    require('FTerm').run("; python '" .. vim.fn.expand("%:p") .. "'")
end,  "Run program")
