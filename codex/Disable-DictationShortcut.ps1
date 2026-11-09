#requires -Version 7.0
<#
.SYNOPSIS
Entfernt Ctrl+D als globalen Diktier-Shortcut der Codex-/ChatGPT-Desktop-App.
.DESCRIPTION
Die App vorher vollstaendig beenden (auch im Infobereich).
Aendert nur den vorhandenen globalDictationToggleHotkey-Eintrag und erstellt
eine bytegetreue Sicherung. Ein leerer Shortcut wird als leere Zeichenfolge
gespeichert. Dies ist eine interne, nicht dokumentierte App-Einstellung;
nach dem Neustart bitte pruefen, ob Ctrl+D wieder frei ist.
.EXAMPLE
pwsh -File .\Disable-DictationShortcut.ps1 -WhatIf
.EXAMPLE
pwsh -File .\Disable-DictationShortcut.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $StatePath = $(
        $codexDirectory = if ($env:CODEX_HOME) { $env:CODEX_HOME } else {
            Join-Path $env:USERPROFILE '.codex'
        }
        Join-Path $codexDirectory '.codex-global-state.json'
    )
)

$ErrorActionPreference = 'Stop'
$StatePath = (Resolve-Path -LiteralPath $StatePath).ProviderPath
$bytes = [IO.File]::ReadAllBytes($StatePath)
$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
    $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$encoding = [Text.UTF8Encoding]::new($hasBom, $true)
$text = $encoding.GetString($bytes)
if ($hasBom) { $text = $text.Substring(1) }
$state = ConvertFrom-Json -InputObject $text -AsHashtable
$key = 'globalDictationToggleHotkey'
if (-not $state.ContainsKey($key)) {
    throw "Der Eintrag '$key' fehlt. Keine Aenderung vorgenommen."
}
if ($state[$key] -eq '') {
    Write-Output 'Der Diktier-Shortcut ist bereits leer.'
    return
}
if ($state[$key] -cne 'Ctrl+D') {
    throw "Der Shortcut ist nicht Ctrl+D. Keine Aenderung vorgenommen."
}

# Nur den Wert ersetzen; andere Einstellungen und Formatierung bleiben erhalten.
$pattern = '"globalDictationToggleHotkey"\s*:\s*"Ctrl\+D"'
$matchesFound = [regex]::Matches($text, $pattern)
if ($matchesFound.Count -ne 1) {
    throw 'Der Shortcut-Eintrag ist nicht eindeutig. Keine Aenderung vorgenommen.'
}
$match = $matchesFound[0]
$replacement = [regex]::Replace($match.Value, '"Ctrl\+D"$', '""')
$updated = $text.Substring(0, $match.Index) + $replacement +
    $text.Substring($match.Index + $match.Length)
$check = ConvertFrom-Json -InputObject $updated -AsHashtable
if ($check[$key] -cne '') { throw 'Die Validierung der Aenderung ist fehlgeschlagen.' }

if ($PSCmdlet.ShouldProcess($StatePath, 'Sicherung erstellen und Diktier-Shortcut leeren')) {
    $running = @(Get-Process -Name Codex, ChatGPT -ErrorAction SilentlyContinue)
    if ($running.Count) {
        throw 'Bitte Codex/ChatGPT vollstaendig beenden und das Skript erneut starten.'
    }
    # Verhindert das Ueberschreiben einer zwischenzeitlich geaenderten Datei.
    $currentBytes = [IO.File]::ReadAllBytes($StatePath)
    if ([Convert]::ToBase64String($bytes) -cne [Convert]::ToBase64String($currentBytes)) {
        throw 'Die Datei wurde zwischenzeitlich geaendert. Bitte erneut starten.'
    }
    $backup = "$StatePath.backup-$(Get-Date -Format yyyyMMdd-HHmmss)-$([guid]::NewGuid().ToString('N'))"
    [IO.File]::WriteAllBytes($backup, $bytes)
    $outputBytes = $encoding.GetPreamble() + $encoding.GetBytes($updated)
    [IO.File]::WriteAllBytes($StatePath, $outputBytes)
    Write-Output "Shortcut geleert. Sicherung: $backup"
    Write-Output 'App neu starten und Ctrl+D in einer anderen Anwendung pruefen.'
}
