
    [CmdletBinding(DefaultParameterSetName='RandomNumberParameterSet', HelpUri='https://go.microsoft.com/fwlink/?LinkID=2097016', RemotingCapability='None')]
    param(
        [ValidateNotNull()]
        [System.Nullable[int]]
        ${SetSeed},

        [Parameter(ParameterSetName='DateParameterSet')]
        [Parameter(ParameterSetName='TimePeriodParameterSet')]
        [Parameter(ParameterSetName='DatePeriodParameterSet')]
        [Parameter(ParameterSetName='RandomNumberParameterSet', Position=0)]
        [System.Object]
        ${Maximum},

        [Parameter(ParameterSetName='DateParameterSet')]
        [Parameter(ParameterSetName='TimePeriodParameterSet')]
        [Parameter(ParameterSetName='DatePeriodParameterSet')]
        [Parameter(ParameterSetName='RandomNumberParameterSet')]
        [System.Object]
        ${Minimum},

        [Parameter(ParameterSetName='RandomListItemParameterSet', Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='ShuffleParameterSet', Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [AllowNull()]
        [System.Object[]]
        ${InputObject},

        [Parameter(ParameterSetName='NameParameterSet')]
        [Parameter(ParameterSetName='FirstNameParameterSet')]
        [Parameter(ParameterSetName='MaleNameParameterSet')]
        [Parameter(ParameterSetName='FemaleNameParameterSet')]
        [Parameter(ParameterSetName='RandomNumberParameterSet')]
        [Parameter(ParameterSetName='RandomListItemParameterSet')]
        [Parameter(ParameterSetName='DateParameterSet')]
        [Parameter(ParameterSetName='DatePeriodParameterSet')]
        [Parameter(ParameterSetName='StreetNameParameterSet')]
        [Parameter(ParameterSetName='CityNameParameterSet')]
        [Parameter(ParameterSetName='CityParameterSet')]
        [ValidateRange(1, 2147483647)]
        [int]
        ${Count},

        [Parameter(ParameterSetName='ShuffleParameterSet', Mandatory=$true)]
        [switch]
        ${Shuffle},

        # here comes my extension ..
        [Parameter(ParameterSetName='NameParameterSet', Mandatory=$true)]
        [switch]
        ${LastName},

        [Parameter(ParameterSetName='FirstNameParameterSet', Mandatory=$true)]
        [switch]
        ${FirstName},

        [Parameter(ParameterSetName='MaleNameParameterSet', Mandatory=$true)]
        [switch]
        ${MaleName},

        [Parameter(ParameterSetName='FemaleNameParameterSet', Mandatory=$true)]
        [switch]
        ${FemaleName},

        [Parameter(ParameterSetName='StreetNameParameterSet', Mandatory=$true)]
        [switch]
        ${StreetName},

        [Parameter(ParameterSetName='CityNameParameterSet', Mandatory=$true)]
        [switch]
        ${CityName},

        [Parameter(ParameterSetName='CityParameterSet', Mandatory=$true)]
        [switch]
        ${City},

        [Parameter(ParameterSetName='TimeParameterSet', Mandatory=$true)]
        [switch]
        ${Time},

        [Parameter(ParameterSetName='TimePeriodParameterSet', Mandatory=$true)]
        [switch]
        ${TimePeriod},

        [Parameter(ParameterSetName='DateParameterSet', Mandatory=$true)]
        [switch]
        ${Date},

        [Parameter(ParameterSetName='DatePeriodParameterSet', Mandatory=$true)]
        [switch]
        ${DatePeriod}

    )
    begin
    {
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
            {
                $PSBoundParameters['OutBuffer'] = 1
            }

            if(${LastName}) {
                $PSBoundParameters.Remove("LastName") | Out-Null
                Get-Content "$PSScriptRoot/Get-Random.json" -Encoding utf8 |
                    ConvertFrom-Json |
                    ForEach-Object LastName |
                    Get-Random @PSBoundParameters |
                    ForEach-Object {
                        if ((Get-Random -Minimum 0 -Maximum 100) -gt 70) {
                            "$_-$($names | Get-Random)"
                        } else {
                            $_
                        }
                    }
            } elseif(${FirstName} -or ${MaleName} -or ${FemaleName}) {
                $PSBoundParameters.Remove("FirstName") | Out-Null
                $PSBoundParameters.Remove("MaleName") | Out-Null
                $PSBoundParameters.Remove("FemaleName") | Out-Null
                if (${MaleName}) {
                    Get-Content "$PSScriptRoot/Get-Random.json" -Encoding utf8 |
                        ConvertFrom-Json |
                        ForEach-Object MaleName |
                        Get-Random @PSBoundParameters
                } elseif (${FemaleName}) {
                    Get-Content "$PSScriptRoot/Get-Random.json" -Encoding utf8 |
                        ConvertFrom-Json |
                        ForEach-Object FemaleName |
                        Get-Random @PSBoundParameters
                } else {
                    Get-Content "$PSScriptRoot/Get-Random.json" -Encoding utf8 |
                        ConvertFrom-Json -AsHashtable |
                        ForEach-Object { $_.GetEnumerator() }|
                        Where-Object Name -in "MaleName","FemaleName"|
                        ForEach-Object Value |
                        Get-Random @PSBoundParameters
                }
            } elseif(${StreetName}) {
                $PSBoundParameters.Remove("StreetName") | Out-Null
                Get-Content "$PSScriptRoot/Get-Random.json" -Encoding utf8 |
                    ConvertFrom-Json |
                    ForEach-Object StreetName |
                    Get-Random @PSBoundParameters
            } elseif(${CityName}) {
                $PSBoundParameters.Remove("CityName") | Out-Null
                Get-Content "$PSScriptRoot/Get-Random.json" -Encoding utf8 |
                    ConvertFrom-Json |
                    ForEach-Object CityName |
                    Get-Random @PSBoundParameters
            } elseif(${City}) {
                $PSBoundParameters.Remove("City") | Out-Null
                Get-Content "$PSScriptRoot/Get-Random.json" -Encoding utf8 |
                    ConvertFrom-Json |
                    ForEach-Object City |
                    Get-Random @PSBoundParameters
            } elseif(${Time}) {
                $PSBoundParameters.Remove("Time") | Out-Null
                (New-Object datetime 1899,12,31).AddHours((Get-Random @PSBoundParameters -Minimum 6 -Maximum 19)).AddMinutes((Get-Random @PSBoundParameters -Minimum 0 -Maximum 59))
            } elseif (${TimePeriod}) {
                if (-not $PSBoundParameters['Minimum']) { $PSBoundParameters.Add('Minimum', 15) }
                if (-not $PSBoundParameters['Maximum']) { $PSBoundParameters.Add('Maximum', 120) }
                $PSBoundParameters.Remove('TimePeriod') | Out-Null
                $diff = Get-Random @PSBoundParameters

                $PSBoundParameters.Remove('Minimum') | Out-Null
                $PSBoundParameters.Remove('Maximum') | Out-Null
                $start= Get-Random -Time @PSBoundParameters
                [pscustomobject]@{
                    start= $start
                    end=   $start.AddMinutes($diff)
                }

            } elseif (${DatePeriod}) {
                if (-not $PSBoundParameters['Minimum']) { $PSBoundParameters.Add('Minimum', 1) }
                if (-not $PSBoundParameters['Maximum']) { $PSBoundParameters.Add('Maximum', 120) }
                $PSBoundParameters.Remove('DatePeriod') | Out-Null

                Get-Random @PSBoundParameters |% {
                    $PSBoundParameters.Remove('Minimum') | Out-Null
                    $PSBoundParameters.Remove('Maximum') | Out-Null
                    $PSBoundParameters.Remove('Count') | Out-Null
                    $start= Get-Random -Date @PSBoundParameters
                    [pscustomobject]@{
                        start= $start
                        end=   $start.AddDays($_)
                    }
                }
            } elseif(${Date}) {
                $PSBoundParameters.Remove("Date") | Out-Null
                if (-not $PSBoundParameters['Minimum']) { $PSBoundParameters.Add('Minimum', -400) }
                if (-not $PSBoundParameters['Maximum']) { $PSBoundParameters.Add('Maximum', 400) }

                Get-Random @PSBoundParameters |% {
                    (Get-Date).AddDays($_).Date
                }

            } else {
                $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Utility\Get-Random', [System.Management.Automation.CommandTypes]::Cmdlet)
                $scriptCmd = {& $wrappedCmd @PSBoundParameters }
                $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
                $steppablePipeline.Begin($PSCmdlet)
            }


        } catch {
            throw
        }
    }

    process
    {
        try {
            if ($null -ne $steppablePipeline) {
                $steppablePipeline.Process($_)
            }
        } catch {
            throw
        }
    }

    end
    {
        try {
            if ($null -ne $steppablePipeline) {
                $steppablePipeline.End()
            }
        } catch {
            throw
        }
    }
    <#

    .ForwardHelpTargetName Microsoft.PowerShell.Utility\Get-Random
    .ForwardHelpCategory Cmdlet

    #>
