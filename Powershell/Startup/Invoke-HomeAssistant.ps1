[cmdletbinding()]
param(
    # extended functions
    [Parameter(Mandatory, ParameterSetName="LightParameterSet")]
    [Alias('Switch')]
    [ValidateSet("turn_on", "turn_off", "toggle")]
    [string] $Light,

    # basic functions
    [Parameter(Mandatory, ParameterSetName="GetStatusParameterSet")]    [switch] $GetStatus,
    [Parameter(Mandatory, ParameterSetName="GetConfigParameterSet")]    [switch] $GetConfig,
    [Parameter(Mandatory, ParameterSetName="GetEventsParameterSet")]    [switch] $GetEvents,
    [Parameter(Mandatory, ParameterSetName="GetServicesParameterSet")]  [switch] $GetServices,
    [Parameter(Mandatory, ParameterSetName="GetHistoryParameterSet")]   [switch] $GetHistory,
    [Parameter(Mandatory, ParameterSetName="GetLogbookParameterSet")]   [switch] $GetLogbook,
    [Parameter(Mandatory, ParameterSetName="GetStateParameterSet")]     [switch] $GetState,
    [Parameter(Mandatory, ParameterSetName="GetErrorsParameterSet")]    [switch] $GetErrors,
    [Parameter(Mandatory, ParameterSetName="GetCameraParameterSet")]    [switch] $GetCamera,
    # [Parameter(Mandatory, ParameterSetName="GetCalendarsParameterSet")] [switch] $GetCalendars,
    [Parameter(Mandatory, ParameterSetName="SetStateParameterSet")]     [switch] $SetState,
    [Parameter(Mandatory, ParameterSetName="SetEventParameterSet")]     [switch] $SetEvent,
    [Parameter(Mandatory, ParameterSetName="SetServicesParameterSet")]  [switch] $SetServices,
    [Parameter(Mandatory, ParameterSetName="SetTemplateParameterSet")]  [switch] $SetTemplate,
    [Parameter(Mandatory, ParameterSetName="CheckConfigParameterSet")]  [switch] $CheckConfig,
    [Parameter(Mandatory, ParameterSetName="SetIntentParameterSet")]    [switch] $SetIntent,
    [Parameter(ParameterSetName="GetHistoryParameterSet")]
    [Parameter(ParameterSetName="GetLogbookParameterSet")]
    [datetime] $Timestamp,

    [Parameter(ParameterSetName="GetHistoryParameterSet")]
    [Parameter(ParameterSetName="GetLogbookParameterSet")]
    [datetime] $EndTimestamp,

    [Parameter(ParameterSetName="GetStateParameterSet")]
    [Parameter(Mandatory, ParameterSetName="GetHistoryParameterSet")]
    [Parameter(Mandatory, ParameterSetName="GetLogbookParameterSet")]
    # [Parameter(Mandatory, ParameterSetName="GetCameraParameterSet")]
    [Parameter(Mandatory, ParameterSetName="SetStateParameterSet")]
    [Parameter(Mandatory, ParameterSetName="LightParameterSet")]
    [Parameter(Mandatory, ParameterSetName="SetServicesParameterSet")]
    [string] $Entity,

    [Parameter(Mandatory, ParameterSetName="SetEventParameterSet")]
    [string] $EventName,

    [Parameter(Mandatory, ParameterSetName="SetServicesParameterSet")]
    [string] $Domain,

    [Parameter(Mandatory, ParameterSetName="SetServicesParameterSet")]
    [string] $Service,

    [Parameter(Mandatory, ParameterSetName="SetStateParameterSet")]
    [string] $State,

    [Parameter(ParameterSetName="SetStateParameterSet")]
    [hashtable] $Attributes
)

$token = Get-Content "$PSScriptRoot/../secrets.json" -Encoding utf8 |
                        ConvertFrom-Json |
                        ForEach-Object homeassistant |
                        ForEach-Object token

function Invoke-RestMethod2 {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Endpoint,

        [Parameter()]
        [Microsoft.PowerShell.Commands.WebRequestMethod] $Method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Get,

        [Parameter()]
        [hashtable] $Body = $null
    )

    $tries = 0
    while ($tries -lt 5) {
        try {
            $params = @{
                Uri                      = "http://homeassistant:8123$Endpoint"
                Method                   = $Method
                ContentType              = "application/json"
                Headers                  = @{
                    "Authorization" = "Bearer $token"
                }
                OperationTimeoutSeconds  = 1000
                ConnectionTimeoutSeconds = 1000
            }
            if ($null -ne $Body) {
                $params.body = ($Body | ConvertTo-Json -Depth 32 -Compress)
            }
            Write-Verbose "Invoke-RestMethod2 $(($params | ConvertTo-Json -Depth 64).Replace($token, "****"))"
            Invoke-RestMethod @params
            exit
        } catch {
            Write-Host -ForegroundColor Red "Invoke-RestMethod2 -Endpoint $Endpoint`: $_"
            $tries += 1
            Start-Sleep -Seconds 1
        }
    }
}

Write-Debug "ParameterSetName = $($PSCmdlet.ParameterSetName | ConvertTo-Json)"
Write-Debug "PSBoundParameters = $($PSBoundParameters | ConvertTo-Json)"
switch -Regex ($PSCmdlet.ParameterSetName){
    "GetStatusParameterSet"    { Invoke-RestMethod2 -Method Get  -Endpoint "/api/"                                                                                     }
    "GetConfigParameterSet"    { Invoke-RestMethod2 -Method Get  -Endpoint "/api/config"                                                                               }
    "GetEventsParameterSet"    { Invoke-RestMethod2 -Method Get  -Endpoint "/api/events"                                                                               }
    "GetServicesParameterSet"  { Invoke-RestMethod2 -Method Get  -Endpoint "/api/services" | ForEach-Object SyncRoot                                                   }
    "GetHistoryParameterSet"   {
        $endpoint = "/api/history/period"
        if ($null -ne $Timestamp) {
            $endpoint += "/$($Timestamp.ToString("s"))"
        }
        $endpoint += "?filter_entity_id=$Entity"
        if ($null -ne $EndTimestamp) {
            $endpoint += "&end_time=$($EndTimestamp.ToString("s"))"
        }

        Invoke-RestMethod2 -Method Get  -Endpoint $endpoint | ForEach-Object SyncRoot
    }
    "GetLogbookParameterSet"   {
        $endpoint = "/api/logbook"
        if ($null -ne $Timestamp) {
            $endpoint += "/$($Timestamp.ToString("s"))"
        }
        $endpoint += "?entity=$Entity"
        if ($null -ne $EndTimestamp) {
            $endpoint += "&end_time=$($EndTimestamp.ToString("s"))"
        }

        Invoke-RestMethod2 -Method Get  -Endpoint $endpoint | ForEach-Object SyncRoot
    }
    "GetStateParameterSet"     {
        if ($Entity.Length -gt 0) {
            $endpoint = "/api/states/$Entity"
            Invoke-RestMethod2 -Method Get -Endpoint $endpoint
        } else {
            $endpoint = "/api/states"
            Invoke-RestMethod2 -Method Get -Endpoint $endpoint | ForEach-Object SyncRoot
        }
    }
    "GetErrorsParameterSet"    { Invoke-RestMethod2 -Method Get  -Endpoint "/api/error_log"                                                                            }
    "GetCameraParameterSet"    { Invoke-RestMethod2 -Method Get  -Endpoint "/api/camera_proxy/$Entity"                                                                 }
    # "GetCalendarsParameterSet" { Invoke-RestMethod2 -Method Get  -Endpoint "/api/calendars" || "/api/calendars/$Entity?start=<timestamp>&end=<timestamp>"               }
    "SetStateParameterSet"     {
        Invoke-RestMethod2 -Method Post -Endpoint "/api/states/$Entity" `
            -Body @{ state=$State; attributes=$Attributes }
    }
    "SetEventParameterSet"     { Invoke-RestMethod2 -Method Post -Endpoint "/api/events/$EventName"                                                                    }
    "SetServicesParameterSet"  { Invoke-RestMethod2 -Method Post -Endpoint "/api/services/$Domain/$Service" -Body @{ entity_id=$Entity }                               }
    "SetTemplateParameterSet"  { Invoke-RestMethod2 -Method Post -Endpoint "/api/template"                                                                             }
    "CheckConfigParameterSet"  { Invoke-RestMethod2 -Method Post -Endpoint "/api/config/core/check_config"                                                             }
    "SetIntentParameterSet"    { Invoke-RestMethod2 -Method Post -Endpoint "/api/intent/handle"                                                                        }
    "(Light)ParameterSet"       {
        $endpoint = $(switch -Regex ($Entity) {
                    "^light\." { "/api/services/light/" }
                    default    { "/api/services/switch/" }
        })
        $endpoint += $Light.ToLower()
        Invoke-RestMethod2 -Method Post -Endpoint $endpoint -Body @{ entity_id=$Entity }
    }
}
