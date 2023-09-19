wt -w 0 focus-tab -t 1

Set file=%*
call Set file=%%file:*%1=%%

SetLocal EnableDelayedExpansion
Set file=%file:~1%

python "C:\Python311\Lib\site-packages\nvr/nvr.py" "%file%" --servername 127.0.0.1:6789 -cc "lua require('FTerm').close()"
