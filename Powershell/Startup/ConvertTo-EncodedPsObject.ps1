[cmdletbinding()]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [pscustomobject]
    $Data,

    [Parameter(Position = 0)]
    [string[]]
    $Property
)
Begin {
    if ($Property.Length -eq 0) {
        function Get-Props  {
            param ([object] $InputObject)
            Get-Member -InputObject $InputObject -MemberType NoteProperty
        }
    } else {
        function Get-Props  {
            param ([object] $InputObject)
            $Property | ForEach-Object { [pscustomobject]@{ Name = $_ } } }
    }
}
Process {
    if ($Data -is [Hashtable]) {
        $Data = [pscustomobject]$Data
    }
    $data |
        ConvertTo-Csv |
        ConvertFrom-Csv |
        ForEach-Object {
            "[pscustomobject]@{"

            $item = $_
            $padding = Get-Props -InputObject $item |
                            ForEach-Object { $_.Name.Length } |
                            Measure-Object -Maximum |
                            ForEach-Object Maximum

            Get-Props -InputObject $item |
                ForEach-Object {
                    $name  = $_.Name.PadRight($padding)
                    $value = $item.($_.Name)

                    if ($value.Length -eq 0) {
                        $value = "`$null"
                    } elseif ($value -notmatch "^\d+$") {
                        $value = "`"$value`""
                    }

                    "    $name = $value"
                }

            "}"
        }
}
