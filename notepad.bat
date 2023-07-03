Set file=%*
call Set file=%%file:*%1=%%
Echo %file%

SetLocal EnableDelayedExpansion
Set file=%file:~1%

nvim "%file%"
