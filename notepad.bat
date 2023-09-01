Set file=%*
call Set file=%%file:*%1=%%
Echo %file%

SetLocal EnableDelayedExpansion
Set file=%file:~1%

nvim "%file%"
python "C:/Python311/Lib/site-packages/nvr/nvr.py" -cc "lua require('FTerm').close()" "%file%"
