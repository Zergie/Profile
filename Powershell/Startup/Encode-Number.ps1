[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string[]]
    $Encoding,

    [Parameter()]
    [int]
    $Length,

    [Parameter(ValueFromPipeline,
               ValueFromPipelineByPropertyName)]
    [int[]]
    $Number
)
begin {
    if ($Encoding.Count -eq 1) {
        $dict = "$Encoding".ToCharArray()
    } else {
        $dict = @() + $Encoding
    }
    $numbers = @()
}
process {
    If ($Length -gt 0) {
         $numbers += 0..([Math]::Pow($dict.Length, $Length) - 1)
    } else {
        $numbers += $Number
    }
}
end {
    Write-Verbose "dict.count = $($dict.count)"
    $numbers |
        ForEach-Object {
            $i = $_
            $ret = ""
            while ($i -gt 0 -or $ret.Length -eq 0) {
                $j = $i % ($dict.count)
                Write-Verbose "j = $j"
                $ret = "$($dict[$j])${ret}"
                $i = [int](($i - $j) / $dict.count)
            }
            Write-Verbose "$_ -> $ret"
            $ret
        }
}
