
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $Value
    )
    Process {
        switch ($Value.GetType().FullName) {
            'System.DateTime' { "'$( $Value.ToString("yyyy-MM-ddTHH:mm:ss") )'" }
            'System.String'   { "'$( $Value -replace "'","''" )'" }
            'System.Boolean'  { "$( if ($Value) { 1 } else { 0 } )" }
            'System.Object[]' { "($( ($Value | Format-SqlValue) -join ',') )" }
            'System.DBNull'   { "NULL" }
            default           { "$Value" }
        }
    }

