[CmdletBinding()]

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

    [Parameter(Mandatory=$true, ParameterSetName="PatchBody")]
    [System.Collections.Specialized.OrderedDictionary[]]
    $PatchBody = $null,

    [Parameter(Mandatory=$true, ParameterSetName="RawBody")]
    [byte[]]
    $RawBody = $null
)

$organization = 'rocom-service'
$project = 'TauOffice'
$projectId = '22af98ac-669d-4f9a-b415-3eb69c863d24'
$team = 'TauOffice%20Team'
$teamId = '48deb8b1-0e33-40d0-8879-71d5258a79f7'

$token = Get-Content "$PSScriptRoot/../secrets.json" -Encoding utf8 |
            ConvertFrom-Json |
            ForEach-Object Invoke-RestApi |
            ForEach-Object token
$headers = @{
    Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($token)")) 
}

$parts = $Endpoint -split ' '
$method = $parts[0]
$uri = $parts[1] -replace "{organization}", $organization `
                    -replace "{project}", $project `
                    -replace "{projectId}", $projectId `
                    -replace "{team}", $team `
                    -replace "{teamId}", $teamId `

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

if ($null -ne $RawBody) {
    $params.body = $RawBody
    $params.ContentType = "application/octet-stream"
}

if ($null -ne $PatchBody) {
    $params.body = $patchbody | ConvertTo-Json -AsArray -Depth 32
    $params.ContentType = "application/json-patch+json"
}

Write-Debug ($params | ConvertTo-Json)
Invoke-RestMethod @params