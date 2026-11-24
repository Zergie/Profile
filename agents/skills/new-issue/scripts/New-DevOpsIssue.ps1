#requires -Version 7
<#
.SYNOPSIS
  Legt ein Issue in Azure DevOps (rocom-service / TauOffice) an und liest es zurück.
.DESCRIPTION
  Nur nach ausdrücklicher Freigabe des Nutzers aufrufen. -DryRun schreibt nichts.
  Beschreibungsdatei: UTF-8, Absätze durch Leerzeilen, Aufzählung mit "- ", Links als [Text](URL).
#>
param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$DescriptionFile,
    [ValidateRange(1, 4)][int]$Priority = 2,
    [Parameter(Mandatory)][double]$Effort,
    [datetime]$DueDate,
    [int[]]$RelatedTo = @(),
    [string]$Tags,
    [string]$Organization = 'https://dev.azure.com/rocom-service',
    [string]$Project = 'TauOffice',
    [string]$AreaPath = 'TauOffice',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function ConvertTo-Html([string]$text) {
    $enc = {
        param($s)
        $s = [System.Net.WebUtility]::HtmlEncode($s)
        [regex]::Replace($s, '\[([^\]]+)\]\((https?://[^)\s]+)\)', '<a href="$2">$1</a>')
    }
    $blocks = ($text -replace "`r`n", "`n").Trim() -split "`n\s*`n"
    $out = foreach ($b in $blocks) {
        $lines = $b -split "`n" | Where-Object { $_.Trim() }
        if (-not $lines) { continue }
        $items = @(); $para = @()
        foreach ($l in $lines) {
            if ($l -match '^\s*[-*]\s+(.*)$') {
                if ($para) { '<p>' + (& $enc ($para -join ' ')) + '</p>'; $para = @() }
                $items += '<li>' + (& $enc $Matches[1]) + '</li>'
            } else {
                if ($items) { '<ul>' + ($items -join '') + '</ul>'; $items = @() }
                $para += $l.Trim()
            }
        }
        if ($para) { '<p>' + (& $enc ($para -join ' ')) + '</p>' }
        if ($items) { '<ul>' + ($items -join '') + '</ul>' }
    }
    $out -join ''
}

$description = ConvertTo-Html (Get-Content -LiteralPath $DescriptionFile -Raw -Encoding utf8)

$ops = @(
    @{ op = 'add'; path = '/fields/System.Title'; value = $Title }
    @{ op = 'add'; path = '/fields/System.AreaPath'; value = $AreaPath }
    @{ op = 'add'; path = '/fields/System.Description'; value = $description }
    @{ op = 'add'; path = '/fields/Microsoft.VSTS.Common.Priority'; value = $Priority }
    @{ op = 'add'; path = '/fields/Microsoft.VSTS.Scheduling.Effort'; value = $Effort }
)
if ($PSBoundParameters.ContainsKey('DueDate')) {
    # Lokale Mitternacht als UTC speichern, wie es die Oberfläche tut.
    $local = [datetime]::SpecifyKind($DueDate.Date, [DateTimeKind]::Unspecified)
    $utc = [TimeZoneInfo]::ConvertTimeToUtc($local, [TimeZoneInfo]::Local)
    $ops += @{ op = 'add'; path = '/fields/Microsoft.VSTS.Scheduling.DueDate'; value = $utc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") }
}
if ($Tags) { $ops += @{ op = 'add'; path = '/fields/System.Tags'; value = $Tags } }
foreach ($id in $RelatedTo) {
    $ops += @{ op = 'add'; path = '/relations/-'; value = @{
            rel = 'System.LinkTypes.Related'; url = "$Organization/_apis/wit/workItems/$id" } }
}

$body = $ops | ConvertTo-Json -Depth 6 -AsArray
if ($DryRun) {
    Write-Host '--- DRY RUN: es wird nichts angelegt (danach folgt der Kind-Task "Implementierung und Test") ---'
    $body
    return
}

$token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv
if (-not $token) { throw 'Kein Azure-DevOps-Token. Bitte "az login" ausführen.' }
$headers = @{ Authorization = "Bearer $token" }

$created = Invoke-RestMethod -Method Post -Headers $headers `
    -ContentType 'application/json-patch+json; charset=utf-8' `
    -Uri "$Organization/$Project/_apis/wit/workitems/`$Issue?api-version=7.1" `
    -Body ([Text.Encoding]::UTF8.GetBytes($body))

# Kind-Task "Implementierung und Test" (wie bei den bestehenden Issues), verknüpft als Child des Issues
$taskOps = @(
    @{ op = 'add'; path = '/fields/System.Title'; value = 'Implementierung und Test' }
    @{ op = 'add'; path = '/fields/System.AreaPath'; value = $AreaPath }
    @{ op = 'add'; path = '/fields/Microsoft.VSTS.Common.Priority'; value = $Priority }
    @{ op = 'add'; path = '/relations/-'; value = @{
            rel = 'System.LinkTypes.Hierarchy-Reverse'; url = "$Organization/_apis/wit/workItems/$($created.id)" } }
)
$task = Invoke-RestMethod -Method Post -Headers $headers `
    -ContentType 'application/json-patch+json; charset=utf-8' `
    -Uri "$Organization/$Project/_apis/wit/workitems/`$Task?api-version=7.1" `
    -Body ([Text.Encoding]::UTF8.GetBytes(($taskOps | ConvertTo-Json -Depth 6 -AsArray)))

# Zurücklesen
$wi = Invoke-RestMethod -Headers $headers -Uri "$Organization/$Project/_apis/wit/workitems/$($created.id)?`$expand=relations&api-version=7.1"
$f = $wi.fields
[pscustomobject]@{
    Id        = $wi.id
    Typ       = $f.'System.WorkItemType'
    Titel     = $f.'System.Title'
    Prio      = $f.'Microsoft.VSTS.Common.Priority'
    Effort    = $f.'Microsoft.VSTS.Scheduling.Effort'
    Frist     = $f.'Microsoft.VSTS.Scheduling.DueDate'
    AreaPath  = $f.'System.AreaPath'
    Relations = @($wi.relations | Where-Object { $_.rel -eq 'System.LinkTypes.Related' }).Count
    KindTask  = "$($task.id) ($((Invoke-RestMethod -Headers $headers -Uri "$Organization/$Project/_apis/wit/workitems/$($task.id)?api-version=7.1").fields.'System.Title'))"
    Link      = "$Organization/$Project/_workitems/edit/$($wi.id)"
} | Format-List
