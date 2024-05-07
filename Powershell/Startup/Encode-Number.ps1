[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]
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
    if ($Encoding.StartsWith('0')) {
        $dict = "$Encoding"
    } else {
        $dict = " $Encoding"
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
    $numbers |
        ForEach-Object {
            $i = $_
            $ret = ""
            while ($i -gt 0 -or $ret.Length -eq 0) {
                $j = $i % ($dict.length)
                    $ret = "$($dict[$j])${ret}"
                    $i = [int](($i - $j - 1) / $dict.length)
            }
            # Write-host "$_ -> $ret"
            $ret
        } |
        Group-Object |
        ForEach-Object Name
}
