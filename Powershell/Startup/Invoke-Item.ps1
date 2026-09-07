[CmdletBinding(DefaultParameterSetName='Path', SupportsShouldProcess=$true, ConfirmImpact='Medium', HelpUri='https://go.microsoft.com/fwlink/?LinkID=2096590')]
param(
    [Parameter(ParameterSetName='Path', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [string[]]
    ${Path},

    [Parameter(ParameterSetName='LiteralPath', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('PSPath','LP')]
    [string[]]
    ${LiteralPath},

    [string]
    ${Filter},

    [string[]]
    ${Include},

    [string[]]
    ${Exclude},

    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [pscredential]
    [System.Management.Automation.CredentialAttribute()]
    ${Credential})

dynamicparam
{
    $targetCmd = $ExecutionContext.InvokeCommand.GetCommand(
        'Microsoft.PowerShell.Management\Invoke-Item',
        [System.Management.Automation.CommandTypes]::Cmdlet,
        $PSBoundParameters)
    $dynamicParams = @($targetCmd.Parameters.GetEnumerator() | Microsoft.PowerShell.Core\Where-Object { $_.Value.IsDynamic })

    if ($dynamicParams.Length -gt 0) {
        $paramDictionary = [Management.Automation.RuntimeDefinedParameterDictionary]::new()
        foreach ($param in $dynamicParams) {
            $param = $param.Value

            if (-not $MyInvocation.MyCommand.Parameters.ContainsKey($param.Name)) {
                $dynParam = [Management.Automation.RuntimeDefinedParameter]::new($param.Name, $param.ParameterType, $param.Attributes)
                $paramDictionary.Add($param.Name, $dynParam)
            }
        }

        return $paramDictionary
    }
}

begin
{
    # This is the single editable policy for FileSystem file routing.
    $fileTypeHandlers = [ordered]@{
        '.json' = 'Json'
        '.xml'  = 'Xml'
        '.yaml' = 'Yaml'
        '.yml'  = 'Yaml'
        '.csv'  = 'Csv'
        '.md' = 'glow'
        '.markdown' = 'glow'
        '.mdown' = 'glow'
        '.mkdn' = 'glow'
        '.mkd' = 'glow'
        '.txt' = 'bat'
        '.log' = 'bat'
        '.ps1' = 'bat'
        '.psm1' = 'bat'
        '.psd1' = 'bat'
        '.cs' = 'bat'
        '.js' = 'bat'
        '.ts' = 'bat'
        '.py' = 'bat'
        '.sh' = 'bat'
        '.sql' = 'bat'
        '.html' = 'bat'
        '.css' = 'bat'
        '.toml' = 'bat'
        '.ini' = 'bat'
        '.conf' = 'bat'
    }

    $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand(
        'Microsoft.PowerShell.Management\Invoke-Item',
        [System.Management.Automation.CommandTypes]::Cmdlet)
}

process
{
    $pathParameter = if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') { 'LiteralPath' } else { 'Path' }
    if ($MyInvocation.ExpectingInput -and $_ -isnot [string]) {
        if ($null -ne $_.PSObject.Properties['LiteralPath'] -and $null -eq $_.PSObject.Properties['Path']) {
            $pathParameter = 'LiteralPath'
            $paths = @($_.LiteralPath)
        } elseif ($null -ne $_.PSObject.Properties['Path']) {
            $paths = @($_.Path)
        } else {
            $paths = @($_)
        }
    } elseif ($MyInvocation.ExpectingInput) {
        $paths = @($_)
    } else {
        $paths = @($PSBoundParameters[$pathParameter])
    }

    foreach ($candidatePath in $paths) {
        $candidateUri = $null
        $isExternalUri = $candidatePath -is [string] -and
            [System.Uri]::TryCreate($candidatePath, [System.UriKind]::Absolute, [ref]$candidateUri) -and
            -not $candidateUri.IsFile -and
            $null -eq (Microsoft.PowerShell.Management\Get-PSDrive -Name $candidateUri.Scheme -ErrorAction SilentlyContinue)

        if ($isExternalUri) {
            if ($PSCmdlet.ShouldProcess($candidatePath, 'Open URL')) {
                Microsoft.PowerShell.Management\Start-Process -FilePath $candidatePath
            }
            continue
        }

        $resolutionParameters = @{ $pathParameter = $candidatePath }
        foreach ($name in 'Filter', 'Include', 'Exclude') {
            if ($PSBoundParameters.ContainsKey($name)) {
                $resolutionParameters[$name] = $PSBoundParameters[$name]
            }
        }

        $resolutionErrors = @()
        $resolvedItems = @(Microsoft.PowerShell.Management\Get-Item @resolutionParameters -ErrorAction SilentlyContinue -ErrorVariable +resolutionErrors)
        if ($resolutionErrors.Count -gt 0 -or $resolvedItems.Count -eq 0) {
            $fallbackParameters = @{}
            foreach ($entry in $PSBoundParameters.GetEnumerator()) {
                $fallbackParameters[$entry.Key] = $entry.Value
            }
            $fallbackParameters[$pathParameter] = $candidatePath
            & $wrappedCmd @fallbackParameters
            continue
        }

        foreach ($item in $resolvedItems) {
            if ($item.PSProvider.Name -eq 'FileSystem' -and -not $item.PSIsContainer) {
                $extension = [System.IO.Path]::GetExtension($item.FullName).ToLowerInvariant()
                $fileTypeHandler = $fileTypeHandlers[$extension]
                if ($fileTypeHandler -eq 'Native') {
                    $fallbackParameters = @{ LiteralPath = $item.PSPath }
                    foreach ($entry in $PSBoundParameters.GetEnumerator()) {
                        if ($entry.Key -notin 'Path', 'LiteralPath', 'Filter', 'Include', 'Exclude') {
                            $fallbackParameters[$entry.Key] = $entry.Value
                        }
                    }
                    & $wrappedCmd @fallbackParameters
                    continue
                }

                if ($fileTypeHandler -in 'Json', 'Xml', 'Yaml', 'Csv') {
                    if ($PSCmdlet.ShouldProcess($item.FullName, "Parse $fileTypeHandler")) {
                        try {
                            $content = Microsoft.PowerShell.Management\Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop
                            if ($fileTypeHandler -eq 'Json') {
                                $content | Microsoft.PowerShell.Utility\ConvertFrom-Json
                            } elseif ($fileTypeHandler -eq 'Xml') {
                                [xml]$content
                            } elseif ($fileTypeHandler -eq 'Yaml') {
                                $yamlCommand = Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue
                                if ($null -eq $yamlCommand) {
                                    throw "Unable to parse YAML files because the required 'ConvertFrom-Yaml' command was not found."
                                }

                                $content | & $yamlCommand
                            } else {
                                $content | Microsoft.PowerShell.Utility\ConvertFrom-Csv
                            }
                        } catch {
                            $message = "Unable to parse $fileTypeHandler file '$($item.FullName)': $($_.Exception.Message)"
                            throw [System.InvalidOperationException]::new($message, $_.Exception)
                        }
                    }
                    continue
                }

                if ($fileTypeHandler -in 'glow', 'bat') {
                    if ($PSCmdlet.ShouldProcess($item.FullName, "View with $fileTypeHandler")) {
                        if ($null -eq (Get-Command $fileTypeHandler -ErrorAction SilentlyContinue)) {
                            throw "Unable to view files because the required '$fileTypeHandler' command was not found."
                        }
                        & $fileTypeHandler $item.FullName
                    }
                    continue
                }
            }

            $fallbackParameters = @{ LiteralPath = $item.PSPath }
            foreach ($entry in $PSBoundParameters.GetEnumerator()) {
                if ($entry.Key -notin 'Path', 'LiteralPath', 'Filter', 'Include', 'Exclude') {
                    $fallbackParameters[$entry.Key] = $entry.Value
                }
            }
            & $wrappedCmd @fallbackParameters
        }
    }
}

end
{
}

<#
.ForwardHelpTargetName Microsoft.PowerShell.Management\Invoke-Item
.ForwardHelpCategory Cmdlet
#>
