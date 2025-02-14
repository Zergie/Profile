[cmdletbinding()]
param(
    [string]
    $Filter,

    [object]
    $Value
)
Process {
    # if (($Value.GetType().ImplementedInterfaces |% FullName) -contains "System.Collections.IEnumerable") {
    #     # todo ?
    # } else {
    #     "[$Filter] = $(Format-SqlValue $Value)"
    # }

    if ($null -eq $Value) {
        "[$Filter] IS NULL"
    } else {
        switch -Regex ($Value.GetType().FullName) {
            '^(System\.Collections\.ArrayList|System\.Object\[\])$'
                    { "[$Filter] IN $(Format-SqlValue -Field $Filter -Value $Value)" }
            default { "[$Filter] = $(Format-SqlValue -Field $Filter -Value $Value)" }
        }
    }
}
