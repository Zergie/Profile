-- Vim filetype plugin file
--     Language: SQL
--   Maintainer: Wolfgang Puchinger <wpuchinger@rocom-service.de>

local map = function (mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc} ) end

map("n", "<Leader>mr", function ()
    vim.cmd("wa")
    require('FTerm').run([[;Invoke-SqlCmd -Query (Get-Content ']] .. vim.fn.expand("%:p") .. [[' | Join-String -Separator " `n")]])
end,  "Run SQL")
