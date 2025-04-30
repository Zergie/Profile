[cmdletbinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]
    $Query,

    [Parameter()]
    [int]
    $First = 10
)

$dllpath = "$PSScriptRoot/../Modules/Microsoft.Exchange.WebServices.2.2/lib/40/Microsoft.Exchange.WebServices.dll"
if (!(Test-Path $dllpath)) {
    nuget install Microsoft.Exchange.WebServices -OutputDirectory "$PSScriptRoot/../Modules/"
}
[void][Reflection.Assembly]::LoadFile($dllpath)

$credentials = Get-Content "$PSScriptRoot/../secrets.json" |
                    ConvertFrom-Json |
                    ForEach-Object Send-SprintStartMail

$service = [Microsoft.Exchange.WebServices.Data.ExchangeService]::new()
$service.url = "https://ews.de2.hostedoffice.ag/EWS/Exchange.asmx"
$service.credentials = [System.Net.NetworkCredential]::new($credentials.Username, $credentials.Password)
# $service.AutodiscoverUrl($credentials. Username, {[CmdletBinding()]param($url)process{$true}})

$propset = [Microsoft.Exchange.WebServices.Data.PropertySet]::new(
                [Microsoft.Exchange.WebServices.Data.ItemSchema]::TextBody,
                [Microsoft.Exchange.WebServices.Data.EmailMessageSchema]::From,
                [Microsoft.Exchange.WebServices.Data.EmailMessageSchema]::ToRecipients,
                [Microsoft.Exchange.WebServices.Data.EmailMessageSchema]::Subject,
                [Microsoft.Exchange.WebServices.Data.EmailMessageSchema]::DateTimeSent,
                [Microsoft.Exchange.WebServices.Data.EmailMessageSchema]::Attachments
            )
$service.findItems([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox, $Query, [Microsoft.Exchange.WebServices.Data.ItemView]::new($First)) |
    ForEach-Object {
        [Microsoft.Exchange.WebServices.Data.EmailMessage]::Bind($service, $_.Id, $propset)
    } |
    ForEach-Object {
            $r = @{}

            $item = $_
            foreach ($p in Get-Member -InputObject $item -Type Property) {
                $value = $item.($p.Name)

                if ($p.Name -in "Service", "Schema") {
                } elseif ($value -is [System.Boolean]) {
                } elseif (($value | Measure-Object).Count -eq 0) {
                } elseif ($p.Name -eq "TextBody") {
                    $r["Body"] = $value.Text
                } elseif ($null -ne $value) {
                    $r[$p.Name] = $value
                }
            }

            [pscustomobject]$r
        }
