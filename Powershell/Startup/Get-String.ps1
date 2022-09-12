
    param(
        [Parameter(ParameterSetName="DatabaseParameterSet", Mandatory)]
        [Parameter(ParameterSetName="TableParameterSet", Mandatory)]
        [Parameter(ParameterSetName="FieldParameterSet", Mandatory)]
        [string] 
        $Database,

        [Parameter(ParameterSetName="TableParameterSet", Position=0, Mandatory)]
        [Parameter(ParameterSetName="FieldParameterSet", Position=0, Mandatory)]
        [string] 
        $Table,

        [Parameter(ParameterSetName="FieldParameterSet", Position=1, Mandatory)]
        [string] 
        $Field
    )
    
    switch ($PSCmdlet.ParameterSetName) {
        "DatabaseParameterSet" { "[$Database]" }
        "TableParameterSet"    { "[$Table]" }
        "FieldParameterSet"    { "[$Table].[$Field]" }
        default { $PSCmdlet.ParameterSetName } 
    }

