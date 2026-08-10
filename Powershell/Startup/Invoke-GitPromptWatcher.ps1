#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(ParameterSetName = 'Status')]
    [switch] $Status,

    [Parameter(ParameterSetName = 'Stop')]
    [switch] $Stop,

    [Parameter(ParameterSetName = 'Reload')]
    [switch] $Reload,

    [Parameter(ParameterSetName = 'Restart')]
    [switch] $Restart,

    [Parameter(ParameterSetName = 'Request', Mandatory)]
    [ValidateSet('Snapshot')]
    [string] $Request,

    [Parameter(ParameterSetName = 'Request')]
    [string] $Path = (Get-Location).Path,

    [Parameter(ParameterSetName = 'Worker', DontShow)]
    [switch] $Worker,

    [Parameter(DontShow)]
    [string] $WorkerIdentityKey,

    [Parameter(DontShow)]
    [string] $InitialPausedErrorBase64
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GitPromptWatcherIdentity {
    if ($WorkerIdentityKey) {
        $hash = $WorkerIdentityKey
        return [pscustomobject]@{
            Key = $hash
            MutexName = "Local\GitPromptWatcher-$hash"
            StartMutexName = "Local\GitPromptWatcher-Start-$hash"
            PipeName = "GitPromptWatcher-$hash"
            StoppedEventName = "Local\GitPromptWatcher-Stopped-$hash"
        }
    }

    $sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $userName = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    # The optional suffix gives process-level tests an isolated session without
    # changing the production identity contract.
    $identitySuffix = [string] $env:GIT_PROMPT_WATCHER_TEST_ID
    $bytes = [Text.Encoding]::UTF8.GetBytes("$userName|$sessionId|$identitySuffix")
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).Substring(0, 24)

    [pscustomobject]@{
        Key = $hash
        MutexName = "Local\GitPromptWatcher-$hash"
        StartMutexName = "Local\GitPromptWatcher-Start-$hash"
        PipeName = "GitPromptWatcher-$hash"
        StoppedEventName = "Local\GitPromptWatcher-Stopped-$hash"
    }
}

function Get-GitPromptWatcherSourcePath {
    $configuredSourcePath = [string] $env:GIT_PROMPT_WATCHER_SOURCE_PATH
    if ($configuredSourcePath) {
        return [IO.Path]::GetFullPath($configuredSourcePath)
    }
    return [IO.Path]::GetFullPath($PSCommandPath)
}

function Get-GitPromptStartupRepositoryPaths {
    $root = 'C:\GIT'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $root -Directory -Force |
            Where-Object {
                ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                (Test-Path -LiteralPath (Join-Path $_.FullName '.git'))
            } |
            Sort-Object -Property LastWriteTime -Descending |
            ForEach-Object FullName
    )
}

function Test-GitPromptWatcherSourceLoad {
    param([Parameter(Mandatory)] [string] $SourcePath)

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Watcher source file '$SourcePath' is missing."
    }
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($SourcePath, [ref] $tokens, [ref] $errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $details = $errors | ForEach-Object { $_.Message } | Select-Object -Unique
        throw "Watcher source '$SourcePath' failed preflight load: $($details -join ' ')"
    }
}

function Get-GitPromptWatcherStoppedEventHandle {
    param(
        [Parameter(Mandatory)] [string] $EventName,
        [switch] $OpenOnly
    )

    if ($OpenOnly) {
        try {
            return [Threading.EventWaitHandle]::OpenExisting($EventName)
        } catch [Threading.WaitHandleCannotBeOpenedException] {
            return $null
        }
    }

    $created = $false
    return [Threading.EventWaitHandle]::new(
        $false,
        [Threading.EventResetMode]::ManualReset,
        $EventName,
        [ref] $created
    )
}

function Test-GitPromptWatcherStoppedState {
    param([Parameter(Mandatory)] [string] $EventName)

    $handle = Get-GitPromptWatcherStoppedEventHandle -EventName $EventName -OpenOnly
    if (-not $handle) { return $false }
    try {
        return $handle.WaitOne(0)
    } finally {
        $handle.Dispose()
    }
}

function Set-GitPromptWatcherStoppedState {
    param([Parameter(Mandatory)] [string] $EventName)

    $handle = Get-GitPromptWatcherStoppedEventHandle -EventName $EventName
    try {
        $handle.Set() | Out-Null
    } finally {
        $handle.Dispose()
    }
}

function Clear-GitPromptWatcherStoppedState {
    param([Parameter(Mandatory)] [string] $EventName)

    $handle = Get-GitPromptWatcherStoppedEventHandle -EventName $EventName -OpenOnly
    if (-not $handle) { return }
    try {
        $handle.Reset() | Out-Null
    } finally {
        $handle.Dispose()
    }
}

function Invoke-GitPromptWatcherRequest {
    param(
        [Parameter(Mandatory)] [string] $PipeName,
        [Parameter(Mandatory)] [hashtable] $Message,
        [int] $TimeoutMilliseconds = 250
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $pipe = [IO.Pipes.NamedPipeClientStream]::new(
            '.', $PipeName, [IO.Pipes.PipeDirection]::InOut,
            [IO.Pipes.PipeOptions]::Asynchronous,
            [Security.Principal.TokenImpersonationLevel]::Impersonation
        )
        $writer = $null
        $reader = $null
        try {
            $pipe.Connect($TimeoutMilliseconds)
            $writer = [IO.StreamWriter]::new($pipe, [Text.UTF8Encoding]::new($false), 1024, $true)
            $reader = [IO.StreamReader]::new($pipe, [Text.UTF8Encoding]::new($false), $false, 1024, $true)
            $writer.AutoFlush = $true
            $writer.WriteLine(($Message | ConvertTo-Json -Compress))
            $readTask = $reader.ReadLineAsync()
            if (-not $readTask.Wait($TimeoutMilliseconds)) {
                # Closing the pipe cancels the outstanding asynchronous read so
                # disposal cannot extend prompt latency beyond the response bound.
                $pipe.Dispose()
                throw "The Git prompt watcher response timed out after $TimeoutMilliseconds ms."
            }
            return $readTask.Result | ConvertFrom-Json
        } catch {
            $lastError = $_
        } finally {
            if ($reader) {
                try { $reader.Dispose() } catch { }
            }
            if ($writer) {
                try { $writer.Dispose() } catch { }
            }
            try { $pipe.Dispose() } catch { }
        }
        if ($attempt -lt 2) {
            Start-Sleep -Milliseconds 10
        }
    }
    throw $lastError
}

function Stop-GitPromptWatcherUnresponsiveWorker {
    param([Parameter(Mandatory)] $Identity)

    $escapedKey = [regex]::Escape([string] $Identity.Key)
    $workerPattern = "(?i)(?:^|\s)-Worker(?:\s|$).*?-WorkerIdentityKey\s+`"?$escapedKey`"?(?:\s|$)"
    Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" |
        Where-Object { $_.CommandLine -match $workerPattern } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -ErrorAction Stop
        }
}

function Start-GitPromptWatcherWorker {
    param(
        [Parameter(Mandatory)] $Identity,
        [string] $InitialPausedError,
        [switch] $StopUnresponsiveWorker
    )

    if (Test-GitPromptWatcherStoppedState -EventName $Identity.StoppedEventName) {
        return
    }

    $startMutex = [Threading.Mutex]::new($false, $Identity.StartMutexName)
    try {
        if (-not $startMutex.WaitOne(15000)) {
            throw 'Timed out while another terminal was starting the Git prompt watcher.'
        }
        try {
            try {
                Invoke-GitPromptWatcherRequest -PipeName $Identity.PipeName `
                    -Message @{ type = 'Status' } -TimeoutMilliseconds 100 | Out-Null
                return
            } catch {
                # No responsive worker exists; start a candidate. Its ownership
                # mutex is the final singleton guard.
                if ($StopUnresponsiveWorker) {
                    Stop-GitPromptWatcherUnresponsiveWorker -Identity $Identity
                }
            }

            $workerArguments = '-NoLogo -NoProfile -NonInteractive -File "{0}" -Worker -WorkerIdentityKey "{1}"' -f `
                $PSCommandPath.Replace('"', '\"'), $Identity.Key
            if ($InitialPausedError) {
                $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($InitialPausedError))
                $workerArguments += ' -InitialPausedErrorBase64 "{0}"' -f $encoded
            }
            Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden `
                -ArgumentList $workerArguments |
                Out-Null

            $deadline = [datetime]::UtcNow.AddSeconds(5)
            do {
                Start-Sleep -Milliseconds 50
                try {
                    Invoke-GitPromptWatcherRequest -PipeName $Identity.PipeName `
                        -Message @{ type = 'Status' } -TimeoutMilliseconds 100 | Out-Null
                    return
                } catch { }
            } while ([datetime]::UtcNow -lt $deadline)

            throw 'The Git prompt watcher did not become ready.'
        } finally {
            $startMutex.ReleaseMutex()
        }
    } finally {
        $startMutex.Dispose()
    }
}

function Get-GitPromptRepositorySnapshot {
    param([Parameter(Mandatory)] [string] $Path)

    $refreshDelayMs = 0
    if ([int]::TryParse([string] $env:GIT_PROMPT_WATCHER_REFRESH_DELAY_MS, [ref] $refreshDelayMs) -and
        $refreshDelayMs -gt 0) {
        Start-Sleep -Milliseconds $refreshDelayMs
    }

    $repositoryInformation = @(
        & git -C $Path rev-parse --show-toplevel --absolute-git-dir 2>$null
    )
    if ($LASTEXITCODE -ne 0 -or $repositoryInformation.Count -lt 2) {
        return $null
    }

    $repositoryRoot = [IO.Path]::GetFullPath($repositoryInformation[0])
    $gitDirectory = [IO.Path]::GetFullPath($repositoryInformation[1])
    $branch = & git -C $repositoryRoot symbolic-ref --quiet --short HEAD 2>$null
    if (-not $branch) {
        $branch = & git -C $repositoryRoot rev-parse --short HEAD 2>$null
    }
    if (-not $branch) { $branch = 'unknown' }

    $snapshot = [ordered]@{
        repositoryRoot = $repositoryRoot
        gitDirectory = $gitDirectory
        branch = [string] $branch
        upstream = $null
        hasUpstream = $false
        hasAheadBehind = $false
        ahead = 0
        behind = 0
        staged = [ordered]@{ added = 0; modified = 0; deleted = 0 }
        workingTree = [ordered]@{ added = 0; modified = 0; deleted = 0 }
        conflicts = 0
        available = $true
        refreshedAt = [datetime]::UtcNow.ToString('O')
        refreshError = $null
    }

    $statusLines = @(
        & git -C $repositoryRoot --no-optional-locks status `
            --porcelain=v2 --branch --untracked-files=normal 2>$null
    )
    if ($LASTEXITCODE -ne 0) {
        $snapshot.available = $false
        $snapshot.refreshError = 'git status failed.'
        return $snapshot
    }

    foreach ($line in $statusLines) {
        if ($line -match '^# branch\.upstream (.+)$') {
            $snapshot.upstream = $matches[1]
            $snapshot.hasUpstream = $true
        } elseif ($line -match '^# branch\.ab \+(\d+) -(\d+)$') {
            $snapshot.hasAheadBehind = $true
            $snapshot.ahead = [int] $matches[1]
            $snapshot.behind = [int] $matches[2]
        } elseif ($line.StartsWith('? ')) {
            $snapshot.workingTree.added++
        } elseif ($line.StartsWith('u ')) {
            $snapshot.conflicts++
        } elseif ($line.StartsWith('1 ') -or $line.StartsWith('2 ')) {
            $fields = $line -split '\s+'
            if ($fields.Count -lt 2 -or $fields[1].Length -lt 2) { continue }
            switch ($fields[1][0]) {
                'A' { $snapshot.staged.added++ }
                'D' { $snapshot.staged.deleted++ }
                '.' { }
                default { $snapshot.staged.modified++ }
            }
            switch ($fields[1][1]) {
                'D' { $snapshot.workingTree.deleted++ }
                '.' { }
                default { $snapshot.workingTree.modified++ }
            }
        }
    }

    return $snapshot
}

function New-GitPromptUnavailableSnapshot {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [string] $GitDirectory,
        [string] $RefreshError = 'Repository is unavailable.'
    )

    [ordered]@{
        repositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
        gitDirectory = if ($GitDirectory) { [string] $GitDirectory } else { $null }
        branch = 'unknown'
        upstream = $null
        hasUpstream = $false
        hasAheadBehind = $false
        ahead = 0
        behind = 0
        staged = [ordered]@{ added = 0; modified = 0; deleted = 0 }
        workingTree = [ordered]@{ added = 0; modified = 0; deleted = 0 }
        conflicts = 0
        available = $false
        refreshedAt = [datetime]::UtcNow.ToString('O')
        refreshError = [string] $RefreshError
    }
}

function Get-GitPromptRefreshSlotOffsetSeconds {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [int] $IntervalSeconds
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($RepositoryRoot.ToLowerInvariant())
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return [int] ($hash[0] % ([math]::Max(1, $IntervalSeconds)))
}

function Get-GitPromptNextRefreshTime {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [int] $IntervalSeconds
    )

    $offset = Get-GitPromptRefreshSlotOffsetSeconds `
        -RepositoryRoot $RepositoryRoot `
        -IntervalSeconds $IntervalSeconds
    $now = [datetime]::UtcNow
    $epoch = [datetime]::UnixEpoch
    $elapsedSeconds = [int] [math]::Floor(($now - $epoch).TotalSeconds)
    $bucketStart = $elapsedSeconds - ($elapsedSeconds % $IntervalSeconds)
    $nextDue = $bucketStart + $offset
    if ($nextDue -le $elapsedSeconds) {
        $nextDue += $IntervalSeconds
    }
    return $epoch.AddSeconds($nextDue)
}

function Invoke-GitPromptWatcherWorker {
    param(
        [Parameter(Mandatory)] $Identity,
        [string] $InitialPausedError
    )

    $ownershipMutex = [Threading.Mutex]::new($false, $Identity.MutexName)
    try {
        if (-not $ownershipMutex.WaitOne(0)) { return }
        try {
            # This dictionary is deliberately worker-local. JSON is the only
            # boundary exposed to clients, so mutable cache ownership cannot leak.
            $snapshots = [Collections.Generic.Dictionary[string, object]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
            $pathRepositories = [Collections.Generic.Dictionary[string, string]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
            $knownRepositories = [Collections.Generic.Dictionary[string, object]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
            $refreshQueue = [Collections.Concurrent.ConcurrentQueue[string]]::new()
            $queuedRefreshKeys = [Collections.Concurrent.ConcurrentDictionary[string, bool]]::new()
            $startupRefreshQueue = [Collections.Concurrent.ConcurrentQueue[string]]::new()
            $queuedStartupRefreshKeys = [Collections.Concurrent.ConcurrentDictionary[string, bool]]::new()
            $refreshJob = $null
            $refreshTargetPath = $null
            $watchers = [Collections.Generic.List[IDisposable]]::new()
            $watcherSubscriptions = [Collections.Generic.List[object]]::new()
            $metadataWatcherByGitDir = [Collections.Generic.Dictionary[string, bool]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
            $sourceLoadError = if ($InitialPausedError) { [string] $InitialPausedError } else { $null }
            $watchingPaused = [bool] $InitialPausedError
            $workerSourcePath = Get-GitPromptWatcherSourcePath
            $processPollSeconds = 30
            $configuredPollSeconds = 0
            if ([int]::TryParse([string] $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS, [ref] $configuredPollSeconds) -and
                $configuredPollSeconds -gt 0) {
                $processPollSeconds = $configuredPollSeconds
            }
            $nextProcessPollAt = [datetime]::UtcNow.AddSeconds($processPollSeconds)
            $lastClientInteractionAt = [datetime]::UtcNow
            $requireClientRequestsOnly = [string] $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS -eq '1'
            $refreshScriptBlock = {
                param([Parameter(Mandatory)] [string] $TargetPath)

                $refreshDelayMs = 0
                if ([int]::TryParse([string] $env:GIT_PROMPT_WATCHER_REFRESH_DELAY_MS, [ref] $refreshDelayMs) -and
                    $refreshDelayMs -gt 0) {
                    Start-Sleep -Milliseconds $refreshDelayMs
                }

                $repositoryInformation = @(
                    & git -C $TargetPath rev-parse --show-toplevel --absolute-git-dir 2>$null
                )
                if ($LASTEXITCODE -ne 0 -or $repositoryInformation.Count -lt 2) {
                    return $null
                }

                $repositoryRoot = [IO.Path]::GetFullPath($repositoryInformation[0])
                $gitDirectory = [IO.Path]::GetFullPath($repositoryInformation[1])
                $branch = & git -C $repositoryRoot symbolic-ref --quiet --short HEAD 2>$null
                if (-not $branch) {
                    $branch = & git -C $repositoryRoot rev-parse --short HEAD 2>$null
                }
                if (-not $branch) { $branch = 'unknown' }

                $snapshot = [ordered]@{
                    repositoryRoot = $repositoryRoot
                    gitDirectory = $gitDirectory
                    branch = [string] $branch
                    upstream = $null
                    hasUpstream = $false
                    hasAheadBehind = $false
                    ahead = 0
                    behind = 0
                    staged = [ordered]@{ added = 0; modified = 0; deleted = 0 }
                    workingTree = [ordered]@{ added = 0; modified = 0; deleted = 0 }
                    conflicts = 0
                    available = $true
                    refreshedAt = [datetime]::UtcNow.ToString('O')
                    refreshError = $null
                }

                $statusLines = @(
                    & git -C $repositoryRoot --no-optional-locks status `
                        --porcelain=v2 --branch --untracked-files=normal 2>$null
                )
                if ($LASTEXITCODE -ne 0) {
                    $snapshot.available = $false
                    $snapshot.refreshError = 'git status failed.'
                    return $snapshot
                }

                foreach ($line in $statusLines) {
                    if ($line -match '^# branch\.upstream (.+)$') {
                        $snapshot.upstream = $matches[1]
                        $snapshot.hasUpstream = $true
                    } elseif ($line -match '^# branch\.ab \+(\d+) -(\d+)$') {
                        $snapshot.hasAheadBehind = $true
                        $snapshot.ahead = [int] $matches[1]
                        $snapshot.behind = [int] $matches[2]
                    } elseif ($line.StartsWith('? ')) {
                        $snapshot.workingTree.added++
                    } elseif ($line.StartsWith('u ')) {
                        $snapshot.conflicts++
                    } elseif ($line.StartsWith('1 ') -or $line.StartsWith('2 ')) {
                        $fields = $line -split '\s+'
                        if ($fields.Count -lt 2 -or $fields[1].Length -lt 2) { continue }
                        switch ($fields[1][0]) {
                            'A' { $snapshot.staged.added++ }
                            'D' { $snapshot.staged.deleted++ }
                            '.' { }
                            default { $snapshot.staged.modified++ }
                        }
                        switch ($fields[1][1]) {
                            'D' { $snapshot.workingTree.deleted++ }
                            '.' { }
                            default { $snapshot.workingTree.modified++ }
                        }
                    }
                }

                return $snapshot
            }
            $periodicIntervalSeconds = 30
            $configuredInterval = 0
            if ([int]::TryParse([string] $env:GIT_PROMPT_WATCHER_PERIODIC_SECONDS, [ref] $configuredInterval) -and
                $configuredInterval -gt 0) {
                $periodicIntervalSeconds = $configuredInterval
            }
            $metadataEventsEnabled = [string] $env:GIT_PROMPT_WATCHER_DISABLE_METADATA_EVENTS -ne '1'

            function Get-QueueKey {
                param([string] $CandidatePath)
                return [IO.Path]::GetFullPath($CandidatePath).ToLowerInvariant()
            }

            function Enqueue-RefreshTarget {
                param([string] $CandidatePath)
                if (-not $CandidatePath) { return }
                $fullTarget = [IO.Path]::GetFullPath($CandidatePath)
                $queueKey = Get-QueueKey -CandidatePath $fullTarget
                if ($queuedRefreshKeys.TryAdd($queueKey, $true)) {
                    $discarded = $false
                    $queuedStartupRefreshKeys.TryRemove($queueKey, [ref] $discarded) | Out-Null
                    $refreshQueue.Enqueue($fullTarget)
                }
            }

            function Enqueue-StartupRefreshTarget {
                param([string] $CandidatePath)
                if (-not $CandidatePath) { return }
                $fullTarget = [IO.Path]::GetFullPath($CandidatePath)
                $queueKey = Get-QueueKey -CandidatePath $fullTarget
                if ($queuedStartupRefreshKeys.TryAdd($queueKey, $true)) {
                    $startupRefreshQueue.Enqueue($fullTarget)
                }
            }

            function Register-KnownRepository {
                param([Parameter(Mandatory)] [object] $Snapshot)

                if (-not $Snapshot.repositoryRoot) { return }
                $repositoryRoot = [IO.Path]::GetFullPath([string] $Snapshot.repositoryRoot)
                if (-not $knownRepositories.ContainsKey($repositoryRoot)) {
                    $knownRepositories[$repositoryRoot] = [ordered]@{
                        nextRefreshAt = Get-GitPromptNextRefreshTime `
                            -RepositoryRoot $repositoryRoot `
                            -IntervalSeconds $periodicIntervalSeconds
                        gitDirectory = [string] $Snapshot.gitDirectory
                    }
                } else {
                    $known = $knownRepositories[$repositoryRoot]
                    if ($Snapshot.gitDirectory) {
                        $known.gitDirectory = [string] $Snapshot.gitDirectory
                    }
                }

                if (-not $metadataEventsEnabled) { return }

                $gitDirectory = [string] $Snapshot.gitDirectory
                if (-not $gitDirectory -or -not (Test-Path -LiteralPath $gitDirectory -PathType Container)) {
                    return
                }
                if ($metadataWatcherByGitDir.ContainsKey($gitDirectory)) {
                    return
                }

                $watcher = [IO.FileSystemWatcher]::new($gitDirectory)
                $watcher.IncludeSubdirectories = $true
                $watcher.NotifyFilter = [IO.NotifyFilters]::FileName `
                    -bor [IO.NotifyFilters]::DirectoryName `
                    -bor [IO.NotifyFilters]::LastWrite `
                    -bor [IO.NotifyFilters]::CreationTime `
                    -bor [IO.NotifyFilters]::Size
                $watcher.EnableRaisingEvents = $true
                $queueContext = @{
                    queuedRefreshKeys = $queuedRefreshKeys
                    refreshQueue = $refreshQueue
                    queuePath = $repositoryRoot
                    queueKey = (Get-QueueKey -CandidatePath $repositoryRoot)
                }
                $enqueueAction = {
                    $context = $Event.MessageData
                    if ($context.queuedRefreshKeys.TryAdd($context.queueKey, $true)) {
                        $context.refreshQueue.Enqueue($context.queuePath)
                    }
                }
                foreach ($eventName in @('Changed', 'Created', 'Deleted', 'Renamed')) {
                    $subscription = Register-ObjectEvent -InputObject $watcher -EventName $eventName `
                        -MessageData $queueContext -Action $enqueueAction
                    $watcherSubscriptions.Add($subscription)
                }
                $watchers.Add($watcher)
                $metadataWatcherByGitDir[$gitDirectory] = $true
            }

            function Start-RefreshJob {
                if ($watchingPaused) { return }
                if ($refreshJob) { return }
                $nextTarget = $null
                while ($true) {
                    $isStartupRefresh = $false
                    if (-not $refreshQueue.TryDequeue([ref] $nextTarget)) {
                        if (-not $startupRefreshQueue.TryDequeue([ref] $nextTarget)) {
                            return
                        }
                        $isStartupRefresh = $true
                    }
                    if (-not $nextTarget) { continue }
                    $queueKey = Get-QueueKey -CandidatePath $nextTarget
                    $placeholder = $false
                    if ($isStartupRefresh) {
                        if (-not $queuedStartupRefreshKeys.TryRemove($queueKey, [ref] $placeholder)) {
                            continue
                        }
                    } else {
                        $queuedRefreshKeys.TryRemove($queueKey, [ref] $placeholder) | Out-Null
                    }
                    Set-Variable -Name refreshTargetPath -Scope 1 -Value $nextTarget
                    $nextJob = if (Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue) {
                        Start-ThreadJob -ScriptBlock $refreshScriptBlock -ArgumentList $nextTarget
                    } else {
                        Start-Job -ScriptBlock $refreshScriptBlock -ArgumentList $nextTarget
                    }
                    Set-Variable -Name refreshJob -Scope 1 -Value $nextJob
                    return
                }
            }

            function Complete-RefreshJob {
                if (-not $refreshJob) { return }
                if ($refreshJob.State -in @('Running', 'NotStarted')) { return }
                $targetPath = [IO.Path]::GetFullPath([string] $refreshTargetPath)
                try {
                    $result = Receive-Job -Job $refreshJob -ErrorAction Stop
                    $snapshot = if ($result -is [array]) { $result[0] } else { $result }
                    if ($snapshot -and $snapshot.repositoryRoot) {
                        $repositoryRoot = [IO.Path]::GetFullPath([string] $snapshot.repositoryRoot)
                        $snapshots[$repositoryRoot] = $snapshot
                        $pathRepositories[$targetPath] = $repositoryRoot
                        Register-KnownRepository -Snapshot $snapshot
                    } elseif ($knownRepositories.ContainsKey($targetPath)) {
                        $known = $knownRepositories[$targetPath]
                        $unavailable = New-GitPromptUnavailableSnapshot `
                            -RepositoryRoot $targetPath `
                            -GitDirectory ([string] $known.gitDirectory)
                        $snapshots[$targetPath] = $unavailable
                    }
                } catch {
                    if ($knownRepositories.ContainsKey($targetPath)) {
                        $known = $knownRepositories[$targetPath]
                        $snapshots[$targetPath] = New-GitPromptUnavailableSnapshot `
                            -RepositoryRoot $targetPath `
                            -GitDirectory ([string] $known.gitDirectory) `
                            -RefreshError $_.Exception.Message
                    }
                } finally {
                    try {
                        Remove-Job -Job $refreshJob -Force -ErrorAction SilentlyContinue
                    } catch {
                    }
                    Set-Variable -Name refreshJob -Scope 1 -Value $null
                    Set-Variable -Name refreshTargetPath -Scope 1 -Value $null
                }
            }

            function Enqueue-PeriodicRefreshes {
                if ($watchingPaused) { return }
                if ($knownRepositories.Count -eq 0) { return }
                $now = [datetime]::UtcNow
                foreach ($repositoryRoot in @($knownRepositories.Keys)) {
                    $known = $knownRepositories[$repositoryRoot]
                    if (-not $known.nextRefreshAt) {
                        $known.nextRefreshAt = Get-GitPromptNextRefreshTime `
                            -RepositoryRoot $repositoryRoot `
                            -IntervalSeconds $periodicIntervalSeconds
                    }
                    while ($known.nextRefreshAt -le $now) {
                        Enqueue-RefreshTarget -CandidatePath $repositoryRoot
                        $known.nextRefreshAt = $known.nextRefreshAt.AddSeconds($periodicIntervalSeconds)
                    }
                }
            }

            function Set-WatcherPausedState {
                param(
                    [Parameter(Mandatory)] [bool] $Paused,
                    [string] $ErrorMessage
                )

                Set-Variable -Name watchingPaused -Scope 1 -Value $Paused
                Set-Variable -Name sourceLoadError -Scope 1 -Value $ErrorMessage
                if ($Paused -and $refreshJob) {
                    try {
                        Stop-Job -Job $refreshJob -ErrorAction SilentlyContinue
                        Remove-Job -Job $refreshJob -Force -ErrorAction SilentlyContinue
                    } catch {
                    }
                    Set-Variable -Name refreshJob -Scope 1 -Value $null
                    Set-Variable -Name refreshTargetPath -Scope 1 -Value $null
                }
            }

            function Test-HasQualifyingPwshClient {
                try {
                    $currentProcess = [Diagnostics.Process]::GetCurrentProcess()
                    $currentSession = $currentProcess.SessionId
                    $processes = Get-Process -Name pwsh -ErrorAction SilentlyContinue
                    foreach ($candidate in $processes) {
                        $candidatePid = [int] $candidate.Id
                        if ($candidatePid -eq $PID) { continue }
                        if ([int] $candidate.SessionId -ne $currentSession) { continue }
                        return $true
                    }
                    return $false
                } catch {
                    # Keep the watcher alive when process discovery is temporarily unavailable.
                    return $true
                }
            }

            $pipeSecurity = [IO.Pipes.PipeSecurity]::new()
            $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().User
            $pipeSecurity.AddAccessRule([IO.Pipes.PipeAccessRule]::new(
                $currentUser,
                [IO.Pipes.PipeAccessRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow
            ))
            Get-GitPromptStartupRepositoryPaths |
                ForEach-Object { Enqueue-StartupRefreshTarget -CandidatePath $_ }

            while ($true) {
                if ([datetime]::UtcNow -ge $nextProcessPollAt) {
                    $nextProcessPollAt = [datetime]::UtcNow.AddSeconds($processPollSeconds)
                    $hasQualifyingClient = if ($requireClientRequestsOnly) {
                        $false
                    } else {
                        Test-HasQualifyingPwshClient
                    }
                    if (
                        -not $hasQualifyingClient -and
                        ([datetime]::UtcNow - $lastClientInteractionAt).TotalSeconds -ge $processPollSeconds
                    ) {
                        break
                    }
                }
                if (-not $watchingPaused) {
                    Complete-RefreshJob
                    Enqueue-PeriodicRefreshes
                    Start-RefreshJob
                }
                $server = [IO.Pipes.NamedPipeServerStreamAcl]::Create(
                    $Identity.PipeName, [IO.Pipes.PipeDirection]::InOut, 1,
                    [IO.Pipes.PipeTransmissionMode]::Byte,
                    [IO.Pipes.PipeOptions]::Asynchronous, 4096, 4096,
                    $pipeSecurity, [IO.HandleInheritability]::None,
                    [IO.Pipes.PipeAccessRights] 0
                )
                $discoveryPath = $null
                $shouldExit = $false
                $connectionCancellation = [Threading.CancellationTokenSource]::new()
                try {
                    $connectedTask = $server.WaitForConnectionAsync($connectionCancellation.Token)
                    if (-not $connectedTask.Wait(100)) {
                        if (-not $watchingPaused) {
                            Complete-RefreshJob
                            Enqueue-PeriodicRefreshes
                            Start-RefreshJob
                        }
                        # Cancel the pending asynchronous accept before disposing its
                        # server. Disposing an active accept can leave a worker unable
                        # to accept subsequent readiness requests.
                        $connectionCancellation.Cancel()
                        try {
                            $connectedTask.GetAwaiter().GetResult()
                        } catch [OperationCanceledException] {
                        }
                        # Yield so PowerShell can deliver FileSystemWatcher events
                        # before the next non-blocking metadata queue drain.
                        Start-Sleep -Milliseconds 10
                        continue
                    }
                    $reader = [IO.StreamReader]::new($server, [Text.UTF8Encoding]::new($false), $false, 1024, $true)
                    $writer = [IO.StreamWriter]::new($server, [Text.UTF8Encoding]::new($false), 1024, $true)
                    try {
                        $writer.AutoFlush = $true
                        $readTask = $null
                        while ($server.IsConnected -and -not $shouldExit) {
                            if (-not $readTask) { $readTask = $reader.ReadLineAsync() }
                            if (-not $readTask.Wait(100)) {
                                if (-not $watchingPaused) {
                                    Complete-RefreshJob
                                    Enqueue-PeriodicRefreshes
                                    Start-RefreshJob
                                }
                                continue
                            }
                            $messageText = $readTask.Result
                            if ($null -eq $messageText) { break }
                            $message = $messageText | ConvertFrom-Json
                            $readTask = $null
                        $lastClientInteractionAt = [datetime]::UtcNow
                        switch ($message.type) {
                            'Status' {
                                $response = [ordered]@{
                                    state = if ($watchingPaused) { 'Paused' } else { 'Healthy' }
                                    processId = $PID
                                    sourceLoadError = if ($watchingPaused) { [string] $sourceLoadError } else { $null }
                                }
                            }
                            'Snapshot' {
                                $fullPath = [IO.Path]::GetFullPath([string] $message.path)
                                $repositoryRoot = if ($pathRepositories.ContainsKey($fullPath)) {
                                    $pathRepositories[$fullPath]
                                } else {
                                    $candidateRoots = @()
                                    try {
                                        $candidateRoots = [string[]] $snapshots.Keys
                                    } catch {
                                        $candidateRoots = @()
                                    }
                                    $resolvedRoot = $null
                                    foreach ($candidateRoot in $candidateRoots) {
                                        $normalizedRoot = $candidateRoot.TrimEnd('\', '/')
                                        if (
                                            $fullPath.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase) -or
                                            $fullPath.StartsWith("$normalizedRoot\", [StringComparison]::OrdinalIgnoreCase)
                                        ) {
                                            $resolvedRoot = $candidateRoot
                                            break
                                        }
                                    }
                                    $resolvedRoot
                                }
                                if ($repositoryRoot) {
                                    $repositoryRoot = [string] $repositoryRoot
                                    $pathRepositories[$fullPath] = $repositoryRoot
                                }
                                $snapshot = if ($repositoryRoot -and $snapshots.ContainsKey($repositoryRoot)) {
                                    $snapshots[$repositoryRoot]
                                } else { $null }
                                if (-not $snapshot) { $discoveryPath = $fullPath }
                                $response = [ordered]@{
                                    state = if ($watchingPaused) { 'Paused' } else { 'Healthy' }
                                    snapshot = $snapshot
                                    sourceLoadError = if ($watchingPaused) { [string] $sourceLoadError } else { $null }
                                }
                            }
                            'Reload' {
                                $sourcePath = if ($message.sourcePath) {
                                    [IO.Path]::GetFullPath([string] $message.sourcePath)
                                } else {
                                    $workerSourcePath
                                }
                                try {
                                    Test-GitPromptWatcherSourceLoad -SourcePath $sourcePath
                                    $workerSourcePath = $sourcePath
                                    Set-WatcherPausedState -Paused $false -ErrorMessage $null
                                    $response = [ordered]@{
                                        state = 'Healthy'
                                        processId = $PID
                                        sourceLoadError = $null
                                    }
                                } catch {
                                    Set-WatcherPausedState -Paused $true -ErrorMessage $_.Exception.Message
                                    $response = [ordered]@{
                                        state = 'Paused'
                                        processId = $PID
                                        sourceLoadError = [string] $sourceLoadError
                                    }
                                }
                            }
                            'Pause' {
                                Set-WatcherPausedState `
                                    -Paused $true `
                                    -ErrorMessage ([string] $message.sourceLoadError)
                                $response = [ordered]@{
                                    state = 'Paused'
                                    processId = $PID
                                    sourceLoadError = [string] $sourceLoadError
                                }
                            }
                            'Stop' {
                                $response = [ordered]@{
                                    state = 'Stopping'
                                    processId = $PID
                                }
                                $shouldExit = $true
                            }
                            default {
                                $response = [ordered]@{ state = 'Error'; error = 'Unknown request type.' }
                            }
                        }
                        $writer.WriteLine(($response | ConvertTo-Json -Compress -Depth 10))
                            if ($discoveryPath) {
                                Enqueue-RefreshTarget -CandidatePath $discoveryPath
                                Start-RefreshJob
                                $discoveryPath = $null
                            }
                            break
                        }
                    } finally {
                        $writer.Dispose()
                        $reader.Dispose()
                    }
                } catch {
                    # A malformed or disconnected client must not terminate the owner.
                } finally {
                    $connectionCancellation.Dispose()
                    $server.Dispose()
                }

                if ($discoveryPath) {
                    Enqueue-RefreshTarget -CandidatePath $discoveryPath
                    Start-RefreshJob
                }
                if ($shouldExit) {
                    break
                }
            }
        } finally {
            try {
                if ($refreshJob) {
                    Stop-Job -Job $refreshJob -ErrorAction SilentlyContinue
                    Remove-Job -Job $refreshJob -Force -ErrorAction SilentlyContinue
                }
            } catch {
            }
            foreach ($subscription in @($watcherSubscriptions)) {
                try {
                    if ($subscription.PSObject.Properties.Name -contains 'SubscriptionId') {
                        Unregister-Event -SubscriptionId $subscription.SubscriptionId -ErrorAction SilentlyContinue
                    } elseif ($subscription.PSObject.Properties.Name -contains 'Name') {
                        Unregister-Event -SourceIdentifier $subscription.Name -ErrorAction SilentlyContinue
                    }
                } catch {
                }
                try {
                    if ($subscription.PSObject.Properties.Name -contains 'Action') {
                        $subscription.Action | Remove-Job -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                }
            }
            foreach ($watcher in @($watchers)) {
                try { $watcher.Dispose() } catch { }
            }
            $ownershipMutex.ReleaseMutex()
        }
    } finally {
        $ownershipMutex.Dispose()
    }
}

if (-not (Get-Variable -Name GitPromptWatcherImportOnly -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) {
    $identity = Get-GitPromptWatcherIdentity
    $sourcePath = Get-GitPromptWatcherSourcePath

    if ($Worker) {
        $initialPausedError = $null
        if ($InitialPausedErrorBase64) {
            $initialPausedError = [Text.Encoding]::UTF8.GetString(
                [Convert]::FromBase64String($InitialPausedErrorBase64)
            )
        }
        Invoke-GitPromptWatcherWorker -Identity $identity -InitialPausedError $initialPausedError
        return
    }

    if ($Status) {
        if (Test-GitPromptWatcherStoppedState -EventName $identity.StoppedEventName) {
            return [pscustomobject]@{ state = 'Stopped'; processId = $null; sourceLoadError = $null }
        }

        $statusDeadline = [datetime]::UtcNow.AddMilliseconds(500)
        do {
            try {
                return Invoke-GitPromptWatcherRequest -PipeName $identity.PipeName -Message @{ type = 'Status' }
            } catch {
                Start-Sleep -Milliseconds 25
            }
        } while ([datetime]::UtcNow -lt $statusDeadline)

        if (Test-GitPromptWatcherStoppedState -EventName $identity.StoppedEventName) {
            [pscustomobject]@{ state = 'Stopped'; processId = $null; sourceLoadError = $null }
        } else {
            [pscustomobject]@{ state = 'NotRunning'; processId = $null; sourceLoadError = $null }
        }
        return
    }

    if ($Stop) {
        Set-GitPromptWatcherStoppedState -EventName $identity.StoppedEventName
        try {
            Invoke-GitPromptWatcherRequest -PipeName $identity.PipeName -Message @{ type = 'Stop' } |
                Out-Null
        } catch {
        }
        [pscustomobject]@{ state = 'Stopped'; processId = $null; sourceLoadError = $null }
        return
    }

    if ($Reload) {
        try {
            return Invoke-GitPromptWatcherRequest -PipeName $identity.PipeName -Message @{
                type = 'Reload'
                sourcePath = $sourcePath
            }
        } catch {
            if (Test-GitPromptWatcherStoppedState -EventName $identity.StoppedEventName) {
                [pscustomobject]@{ state = 'Stopped'; processId = $null; sourceLoadError = $null }
            } else {
                [pscustomobject]@{ state = 'NotRunning'; processId = $null; sourceLoadError = $null }
            }
        }
        return
    }

    if ($Restart) {
        Clear-GitPromptWatcherStoppedState -EventName $identity.StoppedEventName
        try {
            Test-GitPromptWatcherSourceLoad -SourcePath $sourcePath
        } catch {
            $sourceError = $_.Exception.Message
            try {
                Invoke-GitPromptWatcherRequest -PipeName $identity.PipeName -Message @{
                    type = 'Pause'
                    sourceLoadError = $sourceError
                } | Out-Null
            } catch {
                Start-GitPromptWatcherWorker -Identity $identity -InitialPausedError $sourceError
            }
            return [pscustomobject]@{
                state = 'Paused'
                processId = $null
                sourceLoadError = $sourceError
            }
        }

        try {
            Invoke-GitPromptWatcherRequest -PipeName $identity.PipeName -Message @{ type = 'Stop' } | Out-Null
        } catch {
        }

        $stopDeadline = [datetime]::UtcNow.AddSeconds(5)
        $previousWorkerRunning = $false
        do {
            Start-Sleep -Milliseconds 50
            try {
                Invoke-GitPromptWatcherRequest -PipeName $identity.PipeName `
                    -Message @{ type = 'Status' } -TimeoutMilliseconds 100 | Out-Null
                $previousWorkerRunning = $true
                try {
                    Invoke-GitPromptWatcherRequest -PipeName $identity.PipeName `
                        -Message @{ type = 'Stop' } -TimeoutMilliseconds 100 | Out-Null
                } catch {
                }
            } catch {
                $previousWorkerRunning = $false
            }
        } while ($previousWorkerRunning -and [datetime]::UtcNow -lt $stopDeadline)

        if ($previousWorkerRunning) {
            throw 'The previous Git prompt watcher did not stop during restart.'
        }
        Start-GitPromptWatcherWorker -Identity $identity -StopUnresponsiveWorker
        return (& $PSCommandPath -Status)
    }

    if ($Request) {
        try {
            Invoke-GitPromptWatcherRequest -PipeName $identity.PipeName `
                -Message @{ type = $Request; path = $Path }
        } catch {
            if (Test-GitPromptWatcherStoppedState -EventName $identity.StoppedEventName) {
                [pscustomobject]@{ state = 'Stopped'; snapshot = $null; sourceLoadError = $null }
            } else {
                [pscustomobject]@{ state = 'NotRunning'; snapshot = $null; sourceLoadError = $null }
            }
        }
        return
    }

    Start-GitPromptWatcherWorker -Identity $identity
}
