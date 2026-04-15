[cmdletbinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [object]
    $InputObject,

    [Parameter()]
    [hashtable]
    $AddProperties
)

# create a hashtable of the properties of the input object
$hashtable = @{}
$InputObject.psobject.properties |
    ForEach-Object {
        $hashtable[$_.Name] = $_.Value
    }

# add any additional properties specified in the $AddProperties hashtable
if ($AddProperties) {
    foreach ($key in $AddProperties.Keys) {
        $hashtable[$key] = $AddProperties[$key]
    }
}

# create a new PSObject from the hashtable
[PSCustomObject]$hashtable