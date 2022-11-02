" Vim filetype plugin file
"     Language: CSharp
"   Maintainer:	Wolfgang Puchinger <wpuchinger@rocom-service.de>

setlocal makeprg=dotnet\ build\ /v:q\ /nologo\ /property:GenerateFullPaths=true\ /clp:ErrorsOnly
setlocal errorformat=\ %#%f(%l\\\,%c):\ %m

nnoremap <silent> <buffer> <Space>mk :make<bar>:copen<CR>

" automatically open quickfix window after build is completed
autocmd QuickFixCmdPost [^l]* nested cwindow
autocmd QuickFixCmdPost    l* nested lwindow
