#Requires -Version 7.0

<#
.SYNOPSIS
Creates an ephemeral Tailscale auth key and returns the key as a string.

.DESCRIPTION
Uses a Tailscale OAuth client with the auth_keys write scope. Reads credentials
from TAILSCALE_OAUTH_CLIENT_ID and TAILSCALE_OAUTH_CLIENT_SECRET or prompts
interactively, masking the secret. Defaults to a single-use key valid for one day.

.PARAMETER Tag
One or more device tags the OAuth client is authorized to provision.

.PARAMETER Tailnet
The tailnet name from the Tailscale admin console. Use '-' for the client's tailnet.

.PARAMETER ExpiryDays
Number of days the auth key remains valid, from 1 to 90.

.PARAMETER Reusable
Allows the same key to register multiple devices.

.PARAMETER Preapproved
Automatically approves devices registered with this key.

.EXAMPLE
$key = .\New-TailscaleEphemeralKey.ps1 -Tag tag:ephemeral
#>
[CmdletBinding()]
param(
    [ValidatePattern('^tag:[a-zA-Z][a-zA-Z0-9-]*\z')]
    [string[]] $Tag = "tag:ephemeral",

    [string] $ClientId = $env:TAILSCALE_OAUTH_CLIENT_ID,

    [ValidatePattern('^(?:-|[a-zA-Z0-9][a-zA-Z0-9._@-]*)\z')]
    [string] $Tailnet = '-',

    [ValidateRange(1, 90)]
    [int] $ExpiryDays = 1,

    [switch] $Reusable,

    [switch] $Preapproved
)

if ([string]::IsNullOrWhiteSpace($ClientId)) {
    $ClientId = Read-Host 'Tailscale OAuth client ID'
    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        throw 'A Tailscale OAuth client ID is required.'
    }
}

$clientSecret = $env:TAILSCALE_OAUTH_CLIENT_SECRET
if ([string]::IsNullOrWhiteSpace($clientSecret)) {
    $secretInput = Read-Host 'Tailscale OAuth client secret' -AsSecureString
    $clientSecret = [pscredential]::new($ClientId, $secretInput).GetNetworkCredential().Password
}

if ([string]::IsNullOrWhiteSpace($clientSecret)) {
    throw 'A Tailscale OAuth client secret is required.'
}

$tokenResponse = Invoke-RestMethod -Uri 'https://api.tailscale.com/api/v2/oauth/token' `
    -Method Post -ContentType 'application/x-www-form-urlencoded' -MaximumRedirection 0 `
    -ErrorAction Stop -Body @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $clientSecret
    }

if ([string]::IsNullOrWhiteSpace($tokenResponse.access_token)) {
    throw 'Tailscale returned no OAuth access token.'
}

$body = @{
    capabilities = @{
        devices = @{
            create = @{
                ephemeral     = $true
                reusable      = $Reusable.IsPresent
                preauthorized = $Preapproved.IsPresent
                tags          = $Tag
            }
        }
    }
    expirySeconds = $ExpiryDays * 86400
} | ConvertTo-Json -Depth 5

$tailnetPath = [uri]::EscapeDataString($Tailnet)
$request = @{
    Uri                = "https://api.tailscale.com/api/v2/tailnet/$tailnetPath/keys"
    Method             = 'Post'
    Authentication     = 'Bearer'
    Token              = ConvertTo-SecureString -String $tokenResponse.access_token -AsPlainText -Force
    ContentType        = 'application/json'
    Body               = $body
    MaximumRedirection = 0
    ErrorAction        = 'Stop'
}
$response = Invoke-RestMethod @request

if ([string]::IsNullOrWhiteSpace($response.key)) {
    throw 'Tailscale returned no auth key.'
}

$response.key
