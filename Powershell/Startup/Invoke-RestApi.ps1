[cmdletbinding()]
param (
    [Parameter(Mandatory=$true, ParameterSetName="Default")]
    [Parameter(Mandatory=$true, ParameterSetName="RawBody")]
    [Parameter(Mandatory=$true, ParameterSetName="PatchBody")]
    [string]
    $Endpoint,

    [Parameter(ParameterSetName="Default")]
    [Parameter(ParameterSetName="RawBody")]
    [Parameter(ParameterSetName="PatchBody")]
    [Hashtable]
    $Variables = @{},

    [Parameter(ParameterSetName="Default")]
    [Hashtable]
    $Body = $null,

    [Parameter(ParameterSetName="Default")]
    [string]
    $OutFile = $null,

    [Parameter(Mandatory=$true, ParameterSetName="PatchBody")]
    [System.Collections.Specialized.OrderedDictionary[]]
    $PatchBody = $null,

    [Parameter(Mandatory=$true, ParameterSetName="RawBody")]
    [byte[]]
    $RawBody = $null
)
process {
    $organization = 'rocom-service'
    $project = 'TauOffice'
    $projectId = '22af98ac-669d-4f9a-b415-3eb69c863d24'
    $team = 'TauOffice%20Team'
    $teamId = '48deb8b1-0e33-40d0-8879-71d5258a79f7'

    if ($null -eq $global:InvokeRestApiRepositoryContextCache) {
        $global:InvokeRestApiRepositoryContextCache = @{}
    }

    $repositoryRoot = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $repositoryRoot) {
        $repositoryRoot = [System.IO.Path]::GetFullPath(([string]$repositoryRoot).Trim())
        if (-not $global:InvokeRestApiRepositoryContextCache.ContainsKey($repositoryRoot)) {
            $remotes = @(git -C $repositoryRoot remote 2>$null)
            $repositoryContext = $null
            foreach ($remote in $remotes) {
                $remoteUrl = [string](git -C $repositoryRoot remote get-url $remote 2>$null)
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) {
                    continue
                }

                if ($remoteUrl -match '^git@ssh\.dev\.azure\.com:v3/(?<organization>[^/]+)/(?<project>[^/]+)/') {
                    $repositoryContext = [pscustomobject]@{
                        Organization = [System.Uri]::UnescapeDataString($Matches.organization)
                        Project      = [System.Uri]::UnescapeDataString($Matches.project)
                        ProjectId    = $null
                        Team         = $null
                        TeamId       = $null
                    }
                    break
                }

                if ($remoteUrl -match '^ssh://git@ssh\.dev\.azure\.com/v3/(?<organization>[^/]+)/(?<project>[^/]+)/') {
                    $repositoryContext = [pscustomobject]@{
                        Organization = [System.Uri]::UnescapeDataString($Matches.organization)
                        Project      = [System.Uri]::UnescapeDataString($Matches.project)
                        ProjectId    = $null
                        Team         = $null
                        TeamId       = $null
                    }
                    break
                }

                try {
                    $remoteUri = [System.Uri]$remoteUrl
                } catch {
                    continue
                }

                if ($remoteUri.Host -ne 'dev.azure.com' -and $remoteUri.Host -notlike '*.visualstudio.com') {
                    continue
                }

                $pathParts = @($remoteUri.AbsolutePath.Trim('/') -split '/')
                if ($remoteUri.Host -eq 'dev.azure.com' -and $pathParts.Count -ge 2) {
                    $remoteOrganization = $pathParts[0]
                    $remoteProject = $pathParts[1]
                } elseif ($remoteUri.Host -like '*.visualstudio.com' -and $pathParts.Count -ge 1) {
                    $remoteOrganization = $remoteUri.Host.Substring(0, $remoteUri.Host.Length - '.visualstudio.com'.Length)
                    $remoteProject = $pathParts[0]
                } else {
                    continue
                }

                if ($remoteOrganization -and $remoteProject) {
                    $repositoryContext = [pscustomobject]@{
                        Organization = [System.Uri]::UnescapeDataString($remoteOrganization)
                        Project      = [System.Uri]::UnescapeDataString($remoteProject)
                        ProjectId    = $null
                        Team         = $null
                        TeamId       = $null
                    }
                    break
                }
            }

            $global:InvokeRestApiRepositoryContextCache[$repositoryRoot] = $repositoryContext
        }

        $repositoryContext = $global:InvokeRestApiRepositoryContextCache[$repositoryRoot]
        if ($null -ne $repositoryContext) {
            $organization = $repositoryContext.Organization
            $project = $repositoryContext.Project
        }
    }

    $headers = @{}
    $localExtraHeaders = @()
    if ($repositoryRoot) {
        $localExtraHeaders = @(
            git -C $repositoryRoot config --local --get-all http.extraheader 2>$null
        )
    }
    if ($localExtraHeaders.Count -gt 0) {
        $headers = @{}
        foreach ($extraHeader in $localExtraHeaders) {
            $separator = $extraHeader.IndexOf(':')
            if ($separator -gt 0) {
                $headerName = $extraHeader.Substring(0, $separator).Trim()
                $headerValue = $extraHeader.Substring($separator + 1).TrimStart()
                $headers[$headerName] = $headerValue
            }
        }
    }

    if ($headers.Count -eq 0) {
        $token = Get-Content "$PSScriptRoot/../secrets.json" -Encoding utf8 |
                    ConvertFrom-Json |
                    ForEach-Object Invoke-RestApi |
                    ForEach-Object token
        $headers = @{
            Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($token)"))
        }
    }

    if ($null -ne $repositoryContext) {
        if ([string]::IsNullOrWhiteSpace($repositoryContext.ProjectId)) {
            $projectInfo = Invoke-RestMethod -Method Get `
                -Uri "https://dev.azure.com/$organization/_apis/projects/$([System.Uri]::EscapeDataString($project))?api-version=7.0" `
                -Headers $headers `
                -ContentType 'application/json'
            $repositoryContext.ProjectId = $projectInfo.id
        }
        if ([string]::IsNullOrWhiteSpace($repositoryContext.TeamId)) {
            $teams = Invoke-RestMethod -Method Get `
                -Uri "https://dev.azure.com/$organization/_apis/projects/$([System.Uri]::EscapeDataString($project))/teams?api-version=7.0" `
                -Headers $headers `
                -ContentType 'application/json'
            $firstTeam = @($teams.value) | Select-Object -First 1
            if ($null -eq $firstTeam) {
                throw "No Azure DevOps team found for project '$project'."
            }
            $repositoryContext.Team = [System.Uri]::EscapeDataString([string]$firstTeam.name)
            $repositoryContext.TeamId = $firstTeam.id
        }

        $projectId = $repositoryContext.ProjectId
        $team = $repositoryContext.Team
        $teamId = $repositoryContext.TeamId
    }

    $parts = $Endpoint -split ' '
    $method = $parts[0]
    $uri = $parts[1] -replace "{organization}", $organization `
                     -replace "{project}",      $project `
                     -replace "{projectId}",    $projectId `
                     -replace "{team}",         $team `
                     -replace "{teamId}",       $teamId `

    foreach ($key in $Variables.Keys) {
        $uri = $uri -replace "{$key}", [System.Web.HttpUtility]::UrlEncode($Variables[$key])
    }

    $params = @{
        method = $method
        uri = $uri
        headers = $headers
        ContentType = "application/json"
    }

    if ($null -ne $Body) {
        $params.body = ($Body | ConvertTo-Json -Depth 32)
    }

    if ($OutFile.Length -gt 0) {
        $params.OutFile = $OutFile
    }

    if ($null -ne $RawBody) {
        $params.body = $RawBody
        $params.ContentType = "application/octet-stream"
    }

    if ($null -ne $PatchBody) {
        $params.body = [System.Text.Encoding]::UTF8.GetBytes(($patchbody | ConvertTo-Json -AsArray -Depth 32))
        $params.ContentType = "application/json-patch+json"
    }

    Write-Debug ($params | ConvertTo-Json)
    Invoke-RestMethod @params
}
