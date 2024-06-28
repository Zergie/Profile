[CmdletBinding()]
param(
    [Parameter()]
    [switch]
    ${ReadOnly}
)
DynamicParam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Port
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $true
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute((
        [System.IO.Ports.SerialPort]::GetPortNames() | Group-Object | ForEach-Object Name
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Port", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)


    return $RuntimeParameterDictionary
}
process {
    if ($ReadOnly) {
        $port = [System.IO.Ports.SerialPort]::new($PSBoundParameters.Port)
        try {
            $port.Open()
            while(1) { $port.ReadLine() }
        } finally {
            $port.Close()
        }
    } else {
        . 'C:\ProgramData\chocolatey\bin\PLINK.EXE' -serial $PSBoundParameters.Port
    }
}
