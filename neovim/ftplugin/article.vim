" Vim filetype plugin file
"     Language: Tau-Office Eval Expression
"   Maintainer:	Wolfgang Puchinger <wpuchinger@rocom-service.de>

nmap <buffer> <F5> 
    \ :w
    \ <bar> split
    \ <bar> set syntax=article
    \ <bar> setlocal number!
    \ <bar> setlocal relativenumber!
    \ <bar> TOhtml
    \ <bar> w! C:\temp\test.html
    \ <bar> q!
    \ <bar> q!
    \ <bar> !pwsh -NoProfile -NonInteractive -File C:\GIT\Profile\Powershell\Startup\ConvertTo-Pdf.ps1 C:\temp\test.html
    \ <bar> C:\temp\test.pdf
    \ <cr>
