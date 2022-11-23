-- Vim filetype plugin file
--     Language: Tau-Office Eval Expression
--   Maintainer:	Wolfgang Puchinger <wpuchinger@rocom-service.de>

local opts = { noremap = true, silent = true }
vim.api.nvim_buf_set_keymap(0, "n", "<F5>", [[
    :w
    :split
    :set syntax=article
    :setlocal number!
    :setlocal relativenumber!
    :hi normal guibg=#202020
    :TOhtml
    :hi normal guibg=#
    :w! C:/temp/test.html
    :q!
    :q!
    :!pwsh -NoProfile -NonInteractive -File C:\GIT\Profile\Powershell\Startup\ConvertTo-Pdf.ps1 C:\temp\test.html -Orientation Landscape
    :!C:/temp/test.pdf
    <cr>
]], opts)

