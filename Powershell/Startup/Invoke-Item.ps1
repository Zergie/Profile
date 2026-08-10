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
function Get-InvokeItemBatLanguageMappings {
    if ($null -ne $global:InvokeItemBatLanguageMappings) {
        return $global:InvokeItemBatLanguageMappings
    }

    if ($null -eq (Get-Command bat -ErrorAction SilentlyContinue)) {
        throw "Unable to classify FileSystem files because the required 'bat' command was not found."
    }

    $languageLines = @(& bat --list-languages)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to load bat language mappings because 'bat --list-languages' exited with code $LASTEXITCODE."
    }

    $mappings = [ordered]@{
        Markdown = [System.Collections.Generic.List[string]]::new()
        Text     = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($languageLine in $languageLines) {
        $parts = $languageLine -split ':', 2
        if ($parts.Count -ne 2) {
            continue
        }

        $patterns = $parts[1] -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_.Length -gt 0 }

        foreach ($pattern in $patterns) {
            if ($parts[0].Trim() -ieq 'Markdown') {
                $mappings.Markdown.Add($pattern)
            } else {
                $mappings.Text.Add($pattern)
            }
        }
    }

    $global:InvokeItemBatLanguageMappings = [pscustomobject]$mappings
    return $global:InvokeItemBatLanguageMappings
}

function Test-InvokeItemBatPattern {
    param(
        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $Pattern
    )

    $fileName = [System.IO.Path]::GetFileName($Path)
    if ($Pattern.IndexOfAny([char[]]'*?[') -ge 0) {
        $wildcard = [System.Management.Automation.WildcardPattern]::new(
            $Pattern,
            [System.Management.Automation.WildcardOptions]::IgnoreCase)
        return $wildcard.IsMatch($fileName) -or $wildcard.IsMatch(($Path -replace '\\', '/'))
    }

    return $fileName -ieq $Pattern -or $fileName.EndsWith(".$Pattern", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-InvokeItemViewer {
    param(
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    $mappings = Get-InvokeItemBatLanguageMappings
    foreach ($pattern in $mappings.Markdown) {
        if (Test-InvokeItemBatPattern -Path $Path -Pattern $pattern) {
            return 'glow'
        }
    }

    foreach ($pattern in $mappings.Text) {
        if (Test-InvokeItemBatPattern -Path $Path -Pattern $pattern) {
            return 'bat'
        }
    }

    return $null
}

function Get-InvokeItemStructuredFormat {
    param(
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    switch ([System.IO.Path]::GetExtension($Path)) {
        { $_ -ieq '.json' } { return 'Json' }
        { $_ -ieq '.xml' } { return 'Xml' }
        { $_ -ieq '.yaml' } { return 'Yaml' }
        { $_ -ieq '.yml' } { return 'Yaml' }
    }

    return $null
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

    foreach ($path in $paths) {
        $resolutionParameters = @{ $pathParameter = $path }
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
            $fallbackParameters[$pathParameter] = $path
            & $wrappedCmd @fallbackParameters
            continue
        }

        foreach ($item in $resolvedItems) {
            if ($item.PSProvider.Name -eq 'FileSystem' -and -not $item.PSIsContainer) {
                $structuredFormat = Get-InvokeItemStructuredFormat -Path $item.FullName
                if ($null -ne $structuredFormat) {
                    if ($PSCmdlet.ShouldProcess($item.FullName, "Parse $structuredFormat")) {
                        try {
                            $content = Microsoft.PowerShell.Management\Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop
                            if ($structuredFormat -eq 'Json') {
                                $content | Microsoft.PowerShell.Utility\ConvertFrom-Json
                            } elseif ($structuredFormat -eq 'Xml') {
                                [xml]$content
                            } else {
                                $yamlCommand = Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue
                                if ($null -eq $yamlCommand) {
                                    throw "Unable to parse YAML files because the required 'ConvertFrom-Yaml' command was not found."
                                }

                                $content | & $yamlCommand
                            }
                        } catch {
                            $message = "Unable to parse $structuredFormat file '$($item.FullName)': $($_.Exception.Message)"
                            throw [System.InvalidOperationException]::new($message, $_.Exception)
                        }
                    }
                    continue
                }

                $viewer = Get-InvokeItemViewer -Path $item.FullName
                if ($null -ne $viewer) {
                    if ($PSCmdlet.ShouldProcess($item.FullName, "View with $viewer")) {
                        if ($null -eq (Get-Command $viewer -ErrorAction SilentlyContinue)) {
                            throw "Unable to view Markdown files because the required '$viewer' command was not found."
                        }
                        & $viewer $item.FullName
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
