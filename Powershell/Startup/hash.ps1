param(
    [Parameter(Position=0, ValueFromPipeline=$true, ValueFromRemainingArguments=$true)]
    [System.Object]
    ${Text},

    [ValidateSet('SHA1','SHA256','SHA384','SHA512','MACTripleDES','MD5','RIPEMD160')]
    [string]
    ${Algorithm} = 'SHA1'
)

$stream = [System.IO.MemoryStream]::new()
$writer = [System.IO.StreamWriter]::new($stream)
$writer.write("$Text")
$writer.Flush()
$stream.Position = 0
Get-FileHash -InputStream $stream -Algorithm ${Algorithm} | ForEach-Object Hash