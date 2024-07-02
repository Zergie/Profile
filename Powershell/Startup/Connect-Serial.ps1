[CmdletBinding()]
param(
    [Parameter(ParameterSetName="ReadOnlyParameterSet")]
    [switch]
    ${Unique},

    [Parameter(ParameterSetName="ReadOnlyParameterSet")]
    [switch]
    ${ReadOnly}
)
DynamicParam {
    Set-Alias "New-DynamicParameter" "$PSScriptRoot\New-DynamicParameter.ps1"
    @(
        [pscustomobject]@{
            Position = 0
            Type = [string]
            Name = "Port"
            ValidateSet = [System.IO.Ports.SerialPort]::GetPortNames() |
                            Group-Object |
                            ForEach-Object Name
        }
    ) | New-DynamicParameter
}
process {
    if ($ReadOnly) {
        $port = [System.IO.Ports.SerialPort]::new($PSBoundParameters.Port)
        try {
            $port.Open()

            while(1) {
                $port.ReadLine() |
                ForEach-Object {
                    if ($PSBoundParameters.Unique) {
                        if ($_ -ne $Last) {
                            $Last = $_
                            $_
                        }
                    } else {
                        $_
                    }
                }
            }
        } finally {
            $port.Close()
        }
    } else {
        . 'C:\ProgramData\chocolatey\bin\PLINK.EXE' -serial $PSBoundParameters.Port
    }
}
