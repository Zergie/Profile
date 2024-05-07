[CmdletBinding(DefaultParameterSetName='ByConnectionParameters')]
param(
    [Parameter(ParameterSetName='ByConnectionParameters'
              , ValueFromPipelineByPropertyName=$true
              )]
    [psobject]
    ${ServerInstance},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Database},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [switch]
    ${EncryptConnection},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Username},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Password},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [ValidateNotNullOrEmpty()]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential},

    [Parameter(Position=0
              , ValueFromPipeline=$true
              , ValueFromPipelineByPropertyName=$true
              )]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Query},

    [Parameter(ValueFromPipeline=$true
              , ValueFromPipelineByPropertyName=$true
              )]
    [ValidateNotNullOrEmpty()]
    [string]
    ${Path},

    [ValidateRange(0, 65535)]
    [int]
    ${QueryTimeout},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [int]
    ${ConnectionTimeout},

    [ValidateRange(-1, 255)]
    [int]
    ${ErrorLevel},

    [ValidateRange(-1, 25)]
    [int]
    ${SeverityLevel},

    [ValidateRange(1, 2147483647)]
    [int]
    ${MaxCharLength},

    [ValidateRange(1, 2147483647)]
    [int]
    ${MaxBinaryLength},

    [switch]
    ${AbortOnError},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [switch]
    ${DedicatedAdministratorConnection},

    [switch]
    ${DisableVariables},

    [switch]
    ${DisableCommands},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [ValidateNotNullOrEmpty()]
    [string]
    ${HostName},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [string]
    ${NewPassword},

    [string[]]
    ${Variable},

    [ValidateNotNullOrEmpty()]
    [string]
    ${InputFile},

    [bool]
    ${OutputSqlErrors},

    [switch]
    ${IncludeSqlUserErrors},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [switch]
    ${SuppressProviderContextWarning},

    [Parameter(ParameterSetName='ByConnectionParameters')]
    [switch]
    ${IgnoreProviderContext},

    [Alias('As')]
    # [Microsoft.SqlServer.Management.PowerShell.OutputType] # error: Unable to find type [Microsoft.SqlServer.Management.PowerShell.OutputType]
    [ValidateSet('DataRows','DataSet','DataTables')]
    [string]
    ${OutputAs},

    [Parameter(ParameterSetName='ByConnectionString', Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${ConnectionString})

begin {
}

process {
    try {
        if ($PSBoundParameters.ContainsKey('Path')) {
            $PSBoundParameters['Query'] = Get-Content $PSBoundParameters['Path'] |
                                            Join-String -Separator `n
            $PSBoundParameters.Remove('Path') | Out-Null
        } elseif (-not $PSBoundParameters.ContainsKey('Query')) {
            $PSBoundParameters['Query'] = $_
        }
        $PSBoundParameters['Query'] = [string]$PSBoundParameters['Query']
        $PSBoundParameters['TrustServerCertificate'] = $true

        if ($PSBoundParameters['Verbose'].IsPresent) {
            ($PSBoundParameters | ConvertTo-Json -Compress) -replace '"Verbose":\{[^\}]+\},?','' |
                Write-Host -ForegroundColor Magenta
        }

        $outBuffer = $null
        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
        {
            $PSBoundParameters['OutBuffer'] = 1
        }

        & 'SqlServer\Invoke-Sqlcmd' @PSBoundParameters
    } catch {
        throw
    }
}

end { }
<#

.ForwardHelpTargetName SqlServer\Invoke-Sqlcmd
.ForwardHelpCategory Cmdlet

#>

# created by
# ```pswh
# $metadata = New-Object System.Management.Automation.CommandMetaData(Get-Command Invoke-Sqlcmd)
# [System.Management.Automation.ProxyCommand]::Create($metadata) | Out-File Invoke-Sqlcmd.ps1
# ```
