" Vim filetype plugin file
"     Language: Windows PowerShell
"   Maintainer:	Wolfgang Puchinger <wpuchinger@rocom-service.de>


" run script with F5
nmap <buffer> <F5> :w \| :term pwsh -NoProfile -File %:p<CR>
