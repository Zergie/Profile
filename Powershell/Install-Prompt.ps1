[CmdletBinding()]
param(
    [Parameter(DontShow)]
    [switch] $SkipGitPromptWatcherStart
)
$ErrorActionPreference = 'Stop'

# Codex's integrated terminal does not render the Nerd Font private-use glyphs
# used by the full prompt. Detect any Codex-provided environment marker.
$script:UseStandardUnicodePrompt = $null -ne (
    Get-ChildItem Env:CODEX* -ErrorAction SilentlyContinue |
        Select-Object -First 1
)

# oh-my-posh init pwsh --config atomic | Invoke-Expression

$global:GitPromptWatcherScript = Join-Path $PSScriptRoot 'Startup\Invoke-GitPromptWatcher.ps1'
$global:GitPromptWatcherLastError = $null

function Initialize-GitPromptWatcherStoppedEvent {
    $sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $userName = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $identitySuffix = [string] $env:GIT_PROMPT_WATCHER_TEST_ID
    $bytes = [Text.Encoding]::UTF8.GetBytes("$userName|$sessionId|$identitySuffix")
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).Substring(0, 24)
    $eventName = "Local\GitPromptWatcher-Stopped-$hash"
    $global:GitPromptWatcherPipeName = "GitPromptWatcher-$hash"
    if (-not (Get-Variable -Name GitPromptWatcherStoppedEventHandle -Scope Global -ValueOnly -ErrorAction SilentlyContinue)) {
        $created = $false
        $global:GitPromptWatcherStoppedEventHandle = [Threading.EventWaitHandle]::new(
            $false,
            [Threading.EventResetMode]::ManualReset,
            $eventName,
            [ref] $created
        )
    }
}

Initialize-GitPromptWatcherStoppedEvent

function Invoke-GitPromptWatcherSnapshotRequest {
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $global:GitPromptWatcherScript -PathType Leaf)) {
        return $null
    }

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $pipe = [IO.Pipes.NamedPipeClientStream]::new(
            '.', $global:GitPromptWatcherPipeName, [IO.Pipes.PipeDirection]::InOut,
            [IO.Pipes.PipeOptions]::Asynchronous,
            [Security.Principal.TokenImpersonationLevel]::Impersonation
        )
        $reader = $null
        $writer = $null
        try {
            $pipe.Connect(100)
            $reader = [IO.StreamReader]::new($pipe, [Text.UTF8Encoding]::new($false), $false, 1024, $true)
            $writer = [IO.StreamWriter]::new($pipe, [Text.UTF8Encoding]::new($false), 1024, $true)
            $writer.AutoFlush = $true
            $writer.WriteLine((@{ type = 'Snapshot'; path = $Path } | ConvertTo-Json -Compress))
            $readTask = $reader.ReadLineAsync()
            if (-not $readTask.Wait(250)) {
                throw 'The Git prompt watcher response timed out.'
            }
            $responseText = $readTask.Result
            if ($null -eq $responseText) {
                throw 'The Git prompt watcher closed the response pipe.'
            }
            return $responseText | ConvertFrom-Json
        } catch {
            if ($attempt -eq 3) {
                return $null
            }
            Start-Sleep -Milliseconds 10
        } finally {
            if ($reader) { $reader.Dispose() }
            if ($writer) { $writer.Dispose() }
            try { $pipe.Dispose() } catch { }
        }
    }
}

function Format-GitPromptSnapshot {
    param([object] $Snapshot)

    if (-not $Snapshot -or -not $Snapshot.available) { return '' }

    $branch = $Snapshot.branch
    if ($branch -match '^(release)/') {
        $text = " `e[38;5;214m$branch"
    } elseif ($branch -match '^(users|feature|feat)/') {
        $branchText = $branch -replace '(\d+)$', "`e]8;;https://dev.azure.com/rocom-service/TauOffice/_workitems/edit/`$1`e\`$1`e]8;;`e\"
        $text = " `e[38;5;29m$branchText"
    } else {
        $text = " `e[38;5;32m$branch"
    }

    if ($Snapshot.hasUpstream -and -not $Snapshot.hasAheadBehind) {
        $text += " `e[31m×"
    } elseif ($Snapshot.behind -gt 0 -and $Snapshot.ahead -gt 0) {
        if ($script:UseStandardUnicodePrompt) {
            $text += " `e[33m↓$($Snapshot.behind) ↑$($Snapshot.ahead)"
        } else {
            $text += " `e[33m$($Snapshot.behind) $($Snapshot.ahead)"
        }
    } elseif ($Snapshot.behind -gt 0) {
        if ($script:UseStandardUnicodePrompt) {
            $text += " `e[31m↓$($Snapshot.behind)"
        } else {
            $text += " `e[31m$($Snapshot.behind)"
        }
    } elseif ($Snapshot.ahead -gt 0) {
        if ($script:UseStandardUnicodePrompt) {
            $text += " `e[32m↑$($Snapshot.ahead)"
        } else {
            $text += " `e[32m$($Snapshot.ahead)"
        }
    } elseif (-not $Snapshot.hasAheadBehind) {
        $text += if ($script:UseStandardUnicodePrompt) { ' ✓' } else { ' ' }
    }

    $hasStaged = $Snapshot.staged.added -gt 0 -or $Snapshot.staged.modified -gt 0 -or $Snapshot.staged.deleted -gt 0
    $hasWorkingTree = $Snapshot.workingTree.added -gt 0 -or $Snapshot.workingTree.modified -gt 0 -or $Snapshot.workingTree.deleted -gt 0 -or $Snapshot.conflicts -gt 0
    if ($hasStaged) {
        $text += " `e[32m+$($Snapshot.staged.added) ~$($Snapshot.staged.modified) -$($Snapshot.staged.deleted)"
    }
    if ($hasStaged -and $hasWorkingTree) { $text += " `e[38;5;8m|" }
    if ($hasWorkingTree) {
        $text += " `e[31m+$($Snapshot.workingTree.added) ~$($Snapshot.workingTree.modified) -$($Snapshot.workingTree.deleted)"
    }
    return "$text `e[0m"
}

function Get-GitPromptCached {
    try {
        $response = Invoke-GitPromptWatcherSnapshotRequest -Path (Get-Location).Path
        if ($response.state -eq 'Paused' -and $response.sourceLoadError) {
            $global:GitPromptWatcherLastError = "Invoke-GitPromptWatcher: $($response.sourceLoadError)"
        } else {
            $global:GitPromptWatcherLastError = $null
        }
        return Format-GitPromptSnapshot -Snapshot $response.snapshot
    } catch {
        $global:GitPromptWatcherLastError = $null
        return ''
    }
}

# Start the watcher during profile loading. Its mutex makes duplicate profile
# loads harmless, and prompt requests use short-lived pipe connections.
if (-not $SkipGitPromptWatcherStart) {
    Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden `
        -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $global:GitPromptWatcherScript) |
        Out-Null
}

function Get-RGB {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [string] $hex,
        [string] $Delimiter = ";",
        [string] $Terminator = "m"
    )
    $c = ([int]"0x$($hex -replace '#','')")
    "$($c -shr 16 -band 255)$Delimiter$($c -shr 8 -band 255)$Delimiter$($c -band 255)$Terminator"
}

function prompt {

    $gitPromptSegment = Get-GitPromptCached
    if ($global:GitPromptWatcherLastError) {
        Write-Host $global:GitPromptWatcherLastError
    }

    $cwd = (Get-Location).Path
    if ($cwd.StartsWith("Microsoft.PowerShell.Core\FileSystem::")) {
        $cwd = $cwd.Substring("Microsoft.PowerShell.Core\FileSystem::".Length)
    }


    # colors
    $palette = "395B64,2C3333,404258,474E68,50577A,6B728E" -split ","
    if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        $fg1 = 'ffffff'    | Get-RGB
        $bg1 = 'dd0000'    | Get-RGB
    } else {
        $fg1 = 'ffffff'    | Get-RGB
        $bg1 = $palette[0] | Get-RGB
    }
    $fg2 = 'ffffff'    | Get-RGB
    $bg2 = $palette[1] | Get-RGB
    $fg3 = 'ffffff'    | Get-RGB
    $bg3 = $palette[2] | Get-RGB
    $fg4 = 'ffffff'    | Get-RGB
    $bg4 = $palette[3] | Get-RGB

    $promptSeparators = if ($script:UseStandardUnicodePrompt) { '▐', '▌' } else { '', '' }
    $timerIcon = if ($script:UseStandardUnicodePrompt) { ' ◷ ' } else { '  ' }

    Write-Host -NoNewline (("`e[0m`n┌ $($promptSeparators[0])#a#$($promptSeparators[1])#b#$($promptSeparators[1])#c#$($promptSeparators[1])#d#$($promptSeparators[1])`n#x#└ " `
            -replace ' ',   "`e[38;2;$bg1" `
            -replace '(#a#)', "`e[38;2;$fg1`e[48;2;$bg1 `$1 `e[38;2;$bg1`e[48;2;$bg2" `
            -replace '(#b#)', "`e[38;2;$fg2`e[48;2;$bg2`$1`e[38;2;$bg2`e[48;2;$bg3" `
            -replace '(#c#)', "`e[38;2;$fg3`e[48;2;$bg3 `$1 `e[38;2;$bg3`e[48;2;$bg4" `
            -replace '(#d#)', "`e[38;2;$fg4`e[48;2;$bg4`$1`e[0m`e[38;2;$bg4" `
            -replace '(#x#)', "`e[0m"
        ).Replace('#a#' , $cwd
        ).Replace('#b#' , $gitPromptSegment
        ).Replace('#c#', $((Get-Date).ToString("ddd HH:mm"))
        ).Replace('#d#', $(
                try {
                    (Get-History)[-1].Duration |
                        ForEach-Object {
                            if ($_.TotalSeconds -gt 1) {
                                $timerIcon + $_.ToString('s\.f') + ' s '
                            } else {
                                $timerIcon + $_.TotalMilliseconds.ToString('0') + ' ms '
                            }
                        }
                } catch {
                }
            )
        )
    )
    " "
}

# ContinuationPrompt
Set-PSReadLineOption -ContinuationPrompt "  "
