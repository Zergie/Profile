[CmdletBinding()]
param(
)
$ErrorActionPreference = 'Stop'

# oh-my-posh init pwsh --config atomic | Invoke-Expression

$global:GitWorkspaceRoot = [IO.Path]::GetFullPath('C:\GIT')
$global:GitPromptCache = [hashtable]::Synchronized(@{})
$global:GitPromptWatcher = $null

function Remove-GitPromptWatcher {
    $subscribers = @(
        Get-EventSubscriber -ErrorAction SilentlyContinue |
            Where-Object SourceIdentifier -Like 'GitPrompt.*'
    )

    $sourceObjects = @(
        $subscribers |
            ForEach-Object SourceObject |
            Where-Object { $null -ne $_ } |
            Select-Object -Unique
    )

    foreach ($subscriber in $subscribers) {
        $actionJob = $subscriber.Action

        Unregister-Event `
            -SubscriptionId $subscriber.SubscriptionId `
            -ErrorAction SilentlyContinue

        if ($actionJob) {
            Remove-Job `
                -Id $actionJob.Id `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }

    foreach ($sourceObject in $sourceObjects) {
        if ($sourceObject -is [IO.FileSystemWatcher]) {
            $sourceObject.EnableRaisingEvents = $false
            $sourceObject.Dispose()
        }
    }

    $global:GitPromptWatcher = $null
}

function Initialize-GitPromptWatcher {
    if ($global:GitPromptWatcher) {
        return
    }

    if (-not (Test-Path -LiteralPath $global:GitWorkspaceRoot -PathType Container)) {
        return
    }

    $watcher = [IO.FileSystemWatcher]::new($global:GitWorkspaceRoot)
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter =
        [IO.NotifyFilters]::FileName `
        -bor [IO.NotifyFilters]::DirectoryName `
        -bor [IO.NotifyFilters]::LastWrite `
        -bor [IO.NotifyFilters]::Size

    # Helps when builds generate many filesystem events.
    $watcher.InternalBufferSize = 65536

    $state = [pscustomobject]@{
        Cache = $global:GitPromptCache
    }

    $invalidateAction = {
        $cache = $event.MessageData.Cache

        $changedPaths = @($event.SourceEventArgs.FullPath)

        if ($event.SourceEventArgs -is [IO.RenamedEventArgs]) {
            $changedPaths += $event.SourceEventArgs.OldFullPath
        }

        foreach ($changedPath in $changedPaths) {
            # Only Git index lock updates should invalidate the prompt cache.
            $fileName = [IO.Path]::GetFileName($changedPath)

            $isGitFile = $fileName -match '(\.lock|HEAD)$'
            $isInsideGitDirectory = $changedPath -match '(^|[\\/])\.git([\\/]|$)'

            if (-not ($isGitFile -and $isInsideGitDirectory)) {
                continue
            }

            foreach ($repositoryRoot in @($cache.Keys)) {
                $entry = $cache[$repositoryRoot]

                # Normally .git is inside the repository. For Git worktrees,
                # however, the Git directory can be elsewhere.
                $pathsBelongingToRepository = @($repositoryRoot)

                if ($entry.GitDirectory) {
                    $pathsBelongingToRepository += $entry.GitDirectory
                }

                foreach ($root in $pathsBelongingToRepository) {
                    $normalizedRoot = $root.TrimEnd('\', '/')
                    $rootPrefix = "$normalizedRoot\"

                    $isInside =
                        $changedPath.Equals(
                            $normalizedRoot,
                            [StringComparison]::OrdinalIgnoreCase
                        ) -or
                        $changedPath.StartsWith(
                            $rootPrefix,
                            [StringComparison]::OrdinalIgnoreCase
                        )

                    if ($isInside) {
                        $entry.Dirty = $true
                        break
                    }
                }
            }
        }
    }

    Remove-GitPromptWatcher
    foreach ($eventName in @('Changed', 'Created', 'Deleted', 'Renamed')) {
        Register-ObjectEvent `
            -InputObject $watcher `
            -EventName $eventName `
            -SourceIdentifier "GitPrompt.$eventName" `
            -MessageData $state `
            -Action $invalidateAction |
            Out-Null
    }

    # If the watcher buffer overflows, some changes may have been lost.
    # In that case, invalidate every cached repository.
    Register-ObjectEvent `
        -InputObject $watcher `
        -EventName Error `
        -SourceIdentifier 'GitPrompt.Error' `
        -MessageData $state `
        -Action {
            foreach ($entry in $event.MessageData.Cache.Values) {
                $entry.Dirty = $true
            }
        } |
        Out-Null

    $watcher.EnableRaisingEvents = $true
    $global:GitPromptWatcher = $watcher
}

function Update-GitPromptCache {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [object] $CacheEntry
    )

    # Clear Dirty before calculating. If a file changes while Git is running,
    # the watcher will set it to true again.
    $CacheEntry.Dirty = $false

    $branch = & git -C $RepositoryRoot symbolic-ref --quiet --short HEAD 2>$null

    if (-not $branch) {
        $branch = & git -C $RepositoryRoot rev-parse --short HEAD 2>$null
    }

    if (-not $branch) {
        $branch = "unknown"
    }

    $statusLines = & git -C $RepositoryRoot --no-optional-locks `
        status --porcelain=v2 --branch --untracked-files=normal 2>$null

    if ($LASTEXITCODE -ne 0) {
        $CacheEntry.Text = ""
        $CacheEntry.Dirty = $true
        return
    }

    $stagedAdded = 0
    $stagedModified = 0
    $stagedDeleted = 0
    $untrackedAdded = 0
    $untrackedModified = 0
    $untrackedDeleted = 0
    $conflicts = 0
    $ahead = 0
    $behind = 0
    $hasUpstream = $false
    $hasAheadBehind = $false

    foreach ($line in $statusLines) {
        if (-not $line) {
            continue
        }

        if ($line.StartsWith('# branch.upstream ')) {
            $hasUpstream = $true
            continue
        }

        if ($line.StartsWith('# branch.ab ')) {
            $hasAheadBehind = $true

            if ($line -match '^# branch\.ab \+(\d+) -(\d+)$') {
                $ahead = [int]$matches[1]
                $behind = [int]$matches[2]
            }

            continue
        }

        if ($line.StartsWith('? ')) {
            $untrackedAdded++
            continue
        }

        if ($line.StartsWith('u ')) {
            $conflicts++
            continue
        }

        if (-not ($line.StartsWith('1 ') -or $line.StartsWith('2 '))) {
            continue
        }

        $fields = $line -split '\s+'

        if ($fields.Count -lt 2) {
            continue
        }

        $xy = $fields[1]

        if ($xy.Length -lt 2) {
            continue
        }

        $indexStatus = $xy[0]
        $workingTreeStatus = $xy[1]

        switch ($indexStatus) {
            'A' { $stagedAdded++ }
            'D' { $stagedDeleted++ }
            '.' { }
            default { $stagedModified++ }
        }

        switch ($workingTreeStatus) {
            'D' { $untrackedDeleted++ }
            '.' { }
            default { $untrackedModified++ }
        }
    }

    if ($branch -match '^(release)/') {
        $text = " `e[38;5;214m$branch"
    } elseif ($branch -match '^(users|feature|feat)/') {
        $branch_text = $branch -replace '(\d+)$', "`e]8;;https://dev.azure.com/rocom-service/TauOffice/_workitems/edit/`$1`e\`$1`e]8;;`e\"
        $text = " `e[38;5;29m$branch_text"
    } else {
        $text = " `e[38;5;32m$branch"
    }

    $upstreamGone = $hasUpstream -and -not $hasAheadBehind

    if ($upstreamGone) {
        $text += " `e[31m×"
    } elseif ($behind -eq 0 -and $ahead -eq 0 -and $hasAheadBehind) {
    } elseif ($behind -gt 0 -and $ahead -gt 0) {
        $text += " `e[33m$behind $ahead"
    } elseif ($behind -gt 0) {
        $text += " `e[31m$behind"
    } elseif ($ahead -gt 0) {
        $text += " `e[32m$ahead"
    } else {
        $text += " "
    }

    $hasStaged =
        $stagedAdded -gt 0 -or
        $stagedModified -gt 0 -or
        $stagedDeleted -gt 0

    $hasUntracked =
        $untrackedAdded -gt 0 -or
        $untrackedModified -gt 0 -or
        $untrackedDeleted -gt 0 -or
        $conflicts -gt 0

    if ($hasStaged) {
        $text += " `e[32m+$stagedAdded ~$stagedModified -$stagedDeleted"
    }

    if ($hasStaged -and $hasUntracked) {
        $text += " `e[38;5;8m|"
    }

    if ($hasUntracked) {
        $text += " `e[31m+$untrackedAdded ~$untrackedModified -$untrackedDeleted"
    }


    $text += " `e[0m"

    $CacheEntry.Text = $text
    $CacheEntry.LastRefresh = [datetime]::UtcNow
}

function Get-GitPromptCached {
    $repositoryInformation = @(
        & git rev-parse --show-toplevel --absolute-git-dir 2>$null
    )

    if ($LASTEXITCODE -ne 0 -or $repositoryInformation.Count -lt 2) {
        return ''
    }

    $repositoryRoot = [IO.Path]::GetFullPath($repositoryInformation[0])
    $gitDirectory = [IO.Path]::GetFullPath($repositoryInformation[1])

    if (-not $global:GitPromptCache.ContainsKey($repositoryRoot)) {
        $global:GitPromptCache[$repositoryRoot] = [pscustomobject]@{
            Text         = ''
            Dirty        = $true
            LastRefresh  = [datetime]::MinValue
            GitDirectory = $gitDirectory
        }
    }

    $entry = $global:GitPromptCache[$repositoryRoot]

    # FileSystemWatcher is not a transactional guarantee, so retain
    # a fallback refresh interval.
    $cacheExpired =
        ([datetime]::UtcNow - $entry.LastRefresh).TotalSeconds -ge 30

    if ($entry.Dirty -or $cacheExpired) {
        Update-GitPromptCache `
            -RepositoryRoot $repositoryRoot `
            -CacheEntry $entry
        $entry.Dirty = $false
    }

    return $entry.Text
}

Initialize-GitPromptWatcher

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

    Write-Host -NoNewline ("`e[0m`n┌ #a##b##c##d#`n#x#└ " `
            -replace ' ',   "`e[38;2;$bg1" `
            -replace '(#a#)', "`e[38;2;$fg1`e[48;2;$bg1 `$1 `e[38;2;$bg1`e[48;2;$bg2" `
            -replace '(#b#)', "`e[38;2;$fg2`e[48;2;$bg2`$1`e[38;2;$bg2`e[48;2;$bg3" `
            -replace '(#c#)', "`e[38;2;$fg3`e[48;2;$bg3 `$1 `e[38;2;$bg3`e[48;2;$bg4" `
            -replace '(#d#)', "`e[38;2;$fg4`e[48;2;$bg4`$1`e[0m`e[38;2;$bg4" `
            -replace '(#x#)', "`e[0m"
        ).Replace('#a#' , $cwd
        ).Replace('#b#' , $(Get-GitPromptCached)
        ).Replace('#c#', $((Get-Date).ToString("ddd HH:mm"))
        ).Replace('#d#', $(
                try {
                    (Get-History)[-1].Duration |
                        ForEach-Object {
                            if ($_.TotalSeconds -gt 1) {
                                '  ' + $_.ToString('s\.f') + ' s '
                            } else {
                                '  ' + $_.TotalMilliseconds.ToString('0') + ' ms '
                            }
                        }
                } catch {
                }
            )
        )
    " "
}

# ContinuationPrompt
Set-PSReadLineOption -ContinuationPrompt "  "
