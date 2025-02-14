[cmdletbinding()]
param(
    [Parameter(Mandatory,
               Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Name,

    [Parameter(Position=1)]
    [ScriptBlock]
    $ValueFunc,

    [Parameter(Mandatory,
               ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [object[]]
    $Data
)
Begin {
    $result = @{}
}
Process {
    if ($null -ne $ValueFunc) {
        $result[$Data.$Name] = $ValueFunc.InvokeReturnAsIs()
    } else {
        $result[$Data.$Name] = $Data
    }
}
End {
    $result
}
