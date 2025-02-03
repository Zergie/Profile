param (
        [Parameter(Mandatory,
                   Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object[]]
        $Object,

        [Parameter(Mandatory,
                   Position=2,
                   ValueFromPipeline,
                   ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Object[]]
        $Other
)
$object_max = ($Object | Measure-Object).Count
$other_max  = ($Other | Measure-Object).Count
$max = [System.Math]::Max($object_max, $other_max) -1


$i_other = 0
foreach ($i in 0..$max) {
    $item = $(if ($i -gt $object_max) { "" } else { $Object[$i].ToString() })
    $other_item = $(if ($i_other -gt $other_max) { "" } else { $other[$i_other].ToString() })

    if ($item -eq $other_item) {
        [pscustomobject] @{
            Item  = $item
            Other = $other_item
        }
        $i_other += 1
    } else {
        woop
        [pscustomobject] @{
            Item  = $item
            Other = ""
        }
    }
}
