
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

        switch ($Value.GetType().FullName) {
            'System.Object[]' { "[$Filter] IN $(Format-SqlValue $Value)" }
            default           { "[$Filter] = $(Format-SqlValue $Value)" }
        }
    }

