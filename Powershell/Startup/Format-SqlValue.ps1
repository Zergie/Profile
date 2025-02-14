[cmdletbinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [object]
    $Value,

    [Parameter()]
    [string]
    $Field
)
Process {
    switch ($Value.GetType().FullName) {
        'System.DateTime' { "'$( $Value.ToString("yyyy-MM-ddTHH:mm:ss") )'" }
        'System.String'   { "'$( $Value -replace "'","''" )'" }
        'System.Boolean'  { "$( if ($Value) { 1 } else { 0 } )" }
        'System.Collections.ArrayList'
                          { "($( ($Value | Format-SqlValue -Field $Field) -join ','))" }
        'System.Object[]' { "($( ($Value | Format-SqlValue -Field $Field) -join ','))" }
        'System.DBNull'   { "NULL" }
        'System.Management.Automation.PSCustomObject'
                          { Format-SqlValue -Field $Field -Value $Value.$Field }
        default           { "$Value" }
    }
}
