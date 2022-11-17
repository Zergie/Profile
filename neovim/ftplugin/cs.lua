-- Vim filetype plugin file
--     Language: CSharp
--   Maintainer:	Wolfgang Puchinger <wpuchinger@rocom-service.de>

vim.opt_local.makeprg     = "dotnet build /v:q /nologo /property:GenerateFullPaths=true /clp:ErrorsOnly"
vim.opt_local.errorformat = "%#%f(%l\\,%c):%m"

local opts = { noremap = true, silent = true }
vim.api.nvim_buf_set_keymap(0, "n", "<Leader>mk", ":make<bar>:copen<cr>", opts)
