" Vim filetype plugin file
"     Language:	xml
"   Maintainer:	Wolfgang Puchinger <wpuchinger@rocom-service.de>

" use tabs instead of spaces 
setlocal shiftwidth=2
setlocal tabstop=2
setlocal noexpandtab

" run tests with F5
nmap <buffer> <F5> :!. "C:\GIT\TauOffice\DBMS\schema/../tests/Run-Tests.ps1"<CR>
