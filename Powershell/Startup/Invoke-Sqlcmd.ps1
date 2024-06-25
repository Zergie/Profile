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
    [ValidateSet('DataRows','DataSet','DataTables', 'Json', 'Csv', 'ReplItem')]
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
        if ($PSBoundParameters.ContainsKey('InputFile')) {
            $PSBoundParameters['Query'] = Get-Content $PSBoundParameters['InputFile'] |
                                            Join-String -Separator `n
            $PSBoundParameters.Remove('InputFile') | Out-Null
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

        if ($PSBoundParameters['OutputAs'] -eq 'Csv') {
            $PSBoundParameters.Remove('OutputAs') | Out-Null
            & 'SqlServer\Invoke-Sqlcmd' @PSBoundParameters |
                ConvertTo-Csv
        } elseif ($PSBoundParameters['OutputAs'] -eq 'Json') {
            $PSBoundParameters.Remove('OutputAs') | Out-Null
            & 'SqlServer\Invoke-Sqlcmd' @PSBoundParameters |
                ConvertTo-Csv |
                ConvertFrom-Csv |
                ConvertTo-Json
        } elseif ($PSBoundParameters['OutputAs'] -eq 'ReplItem') {
            "<?xml version='1.0' encoding='windows-1250'?>"
            "<DatML-RAW-D xmlns='http://www.destatis.de/schema/datml-raw/2.0/de' version='2.0'>"
            " <replizierung version='2024.05.21' revision='000'>"

            $PSBoundParameters['OutputAs'] = "DataTables"
            & 'SqlServer\Invoke-Sqlcmd' @PSBoundParameters -PipelineVariable dt |
                ForEach-Object rows -PipelineVariable row |
                ForEach-Object {
                      $stage  = 0
                      $reader = [System.IO.StringReader]::new($PSBoundParameters["Query"])
                      $parser = New-Object -TypeName "Microsoft.SqlServer.TransactSql.ScriptDom.TSql100Parser" -ArgumentList $true
                      $table  = $parser.GetTokenStream($reader, [ref] $null) |
                        ForEach-Object{
                          if ($stage -eq 1 -and $_.TokenType -eq [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlTokenType]::Identifier) {
                             $_
                          }
                          if ($_.TokenType -eq [Microsoft.SqlServer.TransactSql.ScriptDom.TSqlTokenType]::From) {
                            $stage += 1
                          }
                        } |
                        Select-Object -First 1 |
                        ForEach-Object Text
                      $idname = "ID"
                      $id = $row.($idname)

                      " <replitem key='tau-office.mdb_$($table.ToLower()):$($id.ToString().ToLower())'>"
                      "  <aktion>ADDNEW</aktion>"
                      "  <db>tau-office.mdb</db>"
                      "  <idfeldname>${idname}</idfeldname>"
                      "  <tabelle>${table}</tabelle>"
                      "  <tabelle_id>${id}</tabelle_id>"
                      "  <tabelle_idnew/>"
                      "  <fields>"
                      $dt.Columns |
                        ForEach-Object ColumnName -PipelineVariable p |
                        ForEach-Object {
                          "   <field key='$($p.ToLower())'>"
                          "    <field_fieldname>$([System.Security.SecurityElement]::Escape($p))</field_fieldname>"
                          if ($row.($p) -eq [System.DBNull]::Value) {
                          "    <field_newvalue/>"
                          } else {
                          "    <field_newvalue>$([System.Security.SecurityElement]::Escape($row.($p).ToString()))</field_newvalue>"
                          }
                          "   </field>"
                        }
                      "  </fields>"
                      " </replitem>"
                    }

            " </replizierung>"
            "</DatML-RAW-D>"
        } else {
            & 'SqlServer\Invoke-Sqlcmd' @PSBoundParameters
        }
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
