local nvim_create_autocmd = vim.api.nvim_create_autocmd
local cmd                 = vim.cmd

-- Removes trailing spaces
nvim_create_autocmd({"BufWritePre"}, {
    pattern = "*",
    callback = function()
        cmd [[ %s/\([^ ]\)\s*$/\1/ ]]
        cmd [[ '' ]]
    end,
})

-- enter insert after :term
nvim_create_autocmd({"TermOpen"}, {
    pattern = "*",
    command = "startinsert"
})

-- change cursor back to pwsh default on leaving vim
nvim_create_autocmd({"VimLeave"}, {
    pattern = "*",
    command = "set guicursor=a:ver100"
})

-- vba file extensions
nvim_create_autocmd({"BufRead", "BufNewFile"}, {
    pattern = {"*.ACM","*.ACR","*.ACF"},
    command = "set filetype=vba"
})

-- vb file extensions
nvim_create_autocmd({"BufRead", "BufNewFile"}, {
    pattern = {"*.cls","*.bas"},
    command = "set filetype=vb"
})
nvim_create_autocmd({"BufRead", "BufNewFile"}, {
    pattern = "*.vbp",
    command = "set filetype=vbp"
})

-- to file extensions
nvim_create_autocmd({"BufRead", "BufNewFile"}, {
    pattern = "*.article",
    command = "set filetype=article"
})

-- zmk keymap file extensions
nvim_create_autocmd({"BufRead", "BufNewFile"}, {
    pattern = "*.keymap",
    command = "set filetype=keymap"
})
