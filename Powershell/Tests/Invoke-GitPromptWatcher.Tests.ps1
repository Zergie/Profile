#Requires -Version 7.0

BeforeAll {
    $script:watcherScript = Join-Path $PSScriptRoot '..\Startup\Invoke-GitPromptWatcher.ps1'
    $script:workerPid = $null
    $env:GIT_PROMPT_WATCHER_TEST_ID = [guid]::NewGuid().ToString('N')
    $env:GIT_PROMPT_WATCHER_PERIODIC_SECONDS = '3'
    $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = '2'
    $sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $userName = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $bytes = [Text.Encoding]::UTF8.GetBytes("$userName|$sessionId|$($env:GIT_PROMPT_WATCHER_TEST_ID)")
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).Substring(0, 24)
    $stoppedEventName = "Local\GitPromptWatcher-Stopped-$hash"
    $created = $false
    $script:pipeName = "GitPromptWatcher-$hash"
    $script:stoppedEventHandle = [Threading.EventWaitHandle]::new(
        $false,
        [Threading.EventResetMode]::ManualReset,
        $stoppedEventName,
        [ref] $created
    )
    $script:stoppedEventHandle.Reset() | Out-Null
    $script:testRepository = Join-Path $env:TEMP "git-prompt-watcher-$($env:GIT_PROMPT_WATCHER_TEST_ID)"
    $script:externalRepository = Join-Path $env:TEMP "git-prompt-watcher-external-$($env:GIT_PROMPT_WATCHER_TEST_ID)"
    $script:startupRepository = Join-Path C:\GIT "git-prompt-watcher-startup-$($env:GIT_PROMPT_WATCHER_TEST_ID)"
    New-Item -ItemType Directory -Path $script:testRepository | Out-Null
    New-Item -ItemType Directory -Path $script:externalRepository | Out-Null
    New-Item -ItemType Directory -Path $script:startupRepository | Out-Null
    & git -C $script:testRepository init -b feature/123 | Out-Null
    & git -C $script:externalRepository init -b feature/987 | Out-Null
    & git -C $script:startupRepository init -b feature/startup | Out-Null
    & git -C $script:testRepository config user.email test@example.invalid
    & git -C $script:testRepository config user.name 'Watcher Test'
    & git -C $script:externalRepository config user.email test@example.invalid
    & git -C $script:externalRepository config user.name 'Watcher Test'
    & git -C $script:startupRepository config user.email test@example.invalid
    & git -C $script:startupRepository config user.name 'Watcher Test'
    Set-Content -LiteralPath (Join-Path $script:testRepository 'tracked.txt') -Value 'initial'
    Set-Content -LiteralPath (Join-Path $script:externalRepository 'tracked.txt') -Value 'initial'
    Set-Content -LiteralPath (Join-Path $script:startupRepository 'tracked.txt') -Value 'initial'
    & git -C $script:testRepository add tracked.txt
    & git -C $script:externalRepository add tracked.txt
    & git -C $script:startupRepository add tracked.txt
    & git -C $script:testRepository commit -m initial | Out-Null
    & git -C $script:externalRepository commit -m initial | Out-Null
    & git -C $script:startupRepository commit -m initial | Out-Null
    (Get-Item -LiteralPath $script:startupRepository).LastWriteTime = [datetime]::MaxValue
}

AfterAll {
    if ($script:workerPid) {
        Stop-Process -Id $script:workerPid -Force -ErrorAction SilentlyContinue
    }
    if ($script:stoppedEventHandle) {
        $script:stoppedEventHandle.Dispose()
    }
    Remove-Item Env:GIT_PROMPT_WATCHER_TEST_ID -ErrorAction Ignore
    Remove-Item Env:GIT_PROMPT_WATCHER_PERIODIC_SECONDS -ErrorAction Ignore
    Remove-Item Env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS -ErrorAction Ignore
    Remove-Item Env:GIT_PROMPT_WATCHER_REFRESH_DELAY_MS -ErrorAction Ignore
    Remove-Item Env:GIT_PROMPT_WATCHER_SOURCE_PATH -ErrorAction Ignore
    Remove-Item Env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS -ErrorAction Ignore
    Remove-Item -LiteralPath $script:testRepository -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:externalRepository -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:startupRepository -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-GitPromptWatcher' {
    It 'parses without errors' {
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile(
            $script:watcherScript, [ref] $null, [ref] $errors
        ) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'reports NotRunning before startup' {
        $status = & $script:watcherScript -Status
        $status.state | Should -Be 'NotRunning'
    }

    It 'starts exactly one healthy owner for concurrent clients' {
        $jobs = 1..4 | ForEach-Object {
            Start-Job -ScriptBlock {
                param($Pwsh, $Script)
                & $Pwsh -NoLogo -NoProfile -NonInteractive -File $Script
            } -ArgumentList (Get-Process -Id $PID).Path, $script:watcherScript
        }
        try {
            $jobs | Wait-Job | Receive-Job | Out-Null
            @($jobs.State | Where-Object { $_ -ne 'Completed' }) | Should -BeNullOrEmpty
        } finally {
            $jobs | Remove-Job -Force
        }

        $statuses = 1..4 | ForEach-Object { & $script:watcherScript -Status }
        @($statuses.state | Select-Object -Unique) | Should -Be @('Healthy')
        $ownerPids = @($statuses.processId | Select-Object -Unique)
        $ownerPids.Count | Should -Be 1
        $script:workerPid = [int] $ownerPids[0]
        (Get-Process -Id $script:workerPid -ErrorAction Stop).HasExited | Should -BeFalse
    }

    It 'remains ready across repeated restarts' {
        1..10 | ForEach-Object {
            (& $script:watcherScript -Restart).state | Should -Be 'Healthy'
        }
    }

    It 'replaces an unresponsive worker that owns the current identity' {
        & $script:watcherScript -Stop | Out-Null
        $worker = Start-Process -FilePath (Get-Process -Id $PID).Path `
            -ArgumentList @(
                '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $script:watcherScript,
                '-Worker', '-WorkerIdentityKey', ($script:pipeName -replace '^GitPromptWatcher-')
            ) `
            -WindowStyle Hidden -PassThru
        $pipe = [IO.Pipes.NamedPipeClientStream]::new(
            '.', $script:pipeName, [IO.Pipes.PipeDirection]::InOut,
            [IO.Pipes.PipeOptions]::Asynchronous,
            [Security.Principal.TokenImpersonationLevel]::Impersonation
        )
        try {
            $deadline = [datetime]::UtcNow.AddSeconds(5)
            do {
                try {
                    $pipe.Connect(100)
                    $connected = $true
                } catch {
                    if ($_.Exception.InnerException -isnot [TimeoutException]) {
                        throw
                    }
                    Start-Sleep -Milliseconds 50
                }
            } while (-not $connected -and [datetime]::UtcNow -lt $deadline)
            $connected | Should -BeTrue

            $restart = & $script:watcherScript -Restart
            $restart.state | Should -Be 'Healthy'
            $restart.processId | Should -Not -Be $worker.Id
            $script:workerPid = [int] $restart.processId
        } finally {
            $pipe.Dispose()
            if (-not $worker.HasExited) {
                Stop-Process -Id $worker.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'preloads direct C:\GIT repositories without a snapshot request' {
        (& $script:watcherScript -Restart).state | Should -Be 'Healthy'
        Start-Sleep -Seconds 3
        $snapshot = (& $script:watcherScript -Request Snapshot -Path $script:startupRepository).snapshot

        $snapshot.available | Should -BeTrue
        $snapshot.branch | Should -Be 'feature/startup'
        $snapshot.repositoryRoot | Should -Be ([IO.Path]::GetFullPath($script:startupRepository))
    }

    It 'does not let a completed client connection block another request' {
        & $script:watcherScript -Stop | Out-Null
        $script:stoppedEventHandle.Reset() | Out-Null
        $oldPollSeconds = $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS
        $oldRequireClientRequests = $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS
        $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = '60'
        $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS = '1'
        $worker = Start-Process -FilePath (Get-Process -Id $PID).Path `
            -ArgumentList @(
                '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $script:watcherScript,
                '-Worker', '-WorkerIdentityKey', ($script:pipeName -replace '^GitPromptWatcher-')
            ) `
            -WindowStyle Hidden -PassThru
        $pipe = [IO.Pipes.NamedPipeClientStream]::new(
            '.', $script:pipeName, [IO.Pipes.PipeDirection]::InOut,
            [IO.Pipes.PipeOptions]::Asynchronous,
            [Security.Principal.TokenImpersonationLevel]::Impersonation
        )
        $reader = $null
        $writer = $null
        try {
            $deadline = [datetime]::UtcNow.AddSeconds(5)
            do {
                Start-Sleep -Milliseconds 50
                $status = & $script:watcherScript -Status
            } while ($status.state -ne 'Healthy' -and -not $worker.HasExited -and [datetime]::UtcNow -lt $deadline)
            $status.state | Should -Be 'Healthy'

            $pipe.Connect(1000)
            $writer = [IO.StreamWriter]::new($pipe, [Text.UTF8Encoding]::new($false), 1024, $true)
            $reader = [IO.StreamReader]::new($pipe, [Text.UTF8Encoding]::new($false), $false, 1024, $true)
            try {
                $writer.AutoFlush = $true
                $writer.WriteLine('{"type":"Status"}')
                ($reader.ReadLine() | ConvertFrom-Json).state | Should -Be 'Healthy'
                (& $script:watcherScript -Status).state | Should -Be 'Healthy'
            } finally {
                if ($reader) { $reader.Dispose() }
                if ($writer) { $writer.Dispose() }
            }
        } finally {
            $pipe.Dispose()
            if ($worker -and -not $worker.HasExited) {
                Stop-Process -Id $worker.Id -Force -ErrorAction SilentlyContinue
            }
            $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = $oldPollSeconds
            if ($null -eq $oldRequireClientRequests) {
                Remove-Item Env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS -ErrorAction SilentlyContinue
            } else {
                $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS = $oldRequireClientRequests
            }
            & $script:watcherScript -Restart | Out-Null
        }
    }

    It 'does not kill a live owner when startup cannot connect to its pipe' {
        & $script:watcherScript -Stop | Out-Null
        $script:stoppedEventHandle.Reset() | Out-Null
        $oldPollSeconds = $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS
        $oldRequireClientRequests = $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS
        $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = '60'
        $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS = '1'
        $worker = Start-Process -FilePath (Get-Process -Id $PID).Path `
            -ArgumentList @(
                '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $script:watcherScript,
                '-Worker', '-WorkerIdentityKey', ($script:pipeName -replace '^GitPromptWatcher-')
            ) `
            -WindowStyle Hidden -PassThru
        $pipe = [IO.Pipes.NamedPipeClientStream]::new(
            '.', $script:pipeName, [IO.Pipes.PipeDirection]::InOut,
            [IO.Pipes.PipeOptions]::Asynchronous,
            [Security.Principal.TokenImpersonationLevel]::Impersonation
        )
        try {
            $deadline = [datetime]::UtcNow.AddSeconds(5)
            do {
                try {
                    $pipe.Connect(100)
                    $connected = $true
                } catch {
                    if ($_.Exception.InnerException -isnot [TimeoutException]) {
                        throw
                    }
                    Start-Sleep -Milliseconds 50
                }
            } while (-not $connected -and [datetime]::UtcNow -lt $deadline)
            $connected | Should -BeTrue

            { & $script:watcherScript } | Should -Throw '*did not become ready*'
            (Get-Process -Id $worker.Id -ErrorAction Stop).HasExited | Should -BeFalse
        } finally {
            $pipe.Dispose()
            if (-not $worker.HasExited) {
                Stop-Process -Id $worker.Id -Force -ErrorAction SilentlyContinue
            }
            $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = $oldPollSeconds
            if ($null -eq $oldRequireClientRequests) {
                Remove-Item Env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS -ErrorAction SilentlyContinue
            } else {
                $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS = $oldRequireClientRequests
            }
            & $script:watcherScript -Restart | Out-Null
        }
    }

    It 'accepts a structured request without exposing mutable cache ownership' {
        $response = & $script:watcherScript -Request Snapshot -Path $PSScriptRoot
        $response.state | Should -Be 'Healthy'
        $response.snapshot | Should -BeNullOrEmpty
        $response.PSObject.Properties.Name | Should -Not -Contain 'cache'
    }

    It 'returns empty promptly, then returns a complete asynchronously discovered snapshot' {
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        $first = & $script:watcherScript -Request Snapshot -Path $script:testRepository
        $stopwatch.Stop()
        $first.snapshot | Should -BeNullOrEmpty
        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 1000

        $snapshot = $null
        $deadline = [datetime]::UtcNow.AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 50
            $snapshot = (& $script:watcherScript -Request Snapshot -Path $script:testRepository).snapshot
        } while (-not $snapshot -and [datetime]::UtcNow -lt $deadline)

        $snapshot.available | Should -BeTrue
        $snapshot.branch | Should -Be 'feature/123'
        $snapshot.repositoryRoot | Should -Be ([IO.Path]::GetFullPath($script:testRepository))
        $snapshot.gitDirectory | Should -Not -BeNullOrEmpty
        $snapshot.PSObject.Properties.Name | Should -Contain 'upstream'
        $snapshot.PSObject.Properties.Name | Should -Contain 'ahead'
        $snapshot.PSObject.Properties.Name | Should -Contain 'behind'
        $snapshot.PSObject.Properties.Name | Should -Contain 'staged'
        $snapshot.PSObject.Properties.Name | Should -Contain 'workingTree'
        $snapshot.PSObject.Properties.Name | Should -Contain 'conflicts'
        $snapshot.PSObject.Properties.Name | Should -Contain 'refreshedAt'
        $snapshot.PSObject.Properties.Name | Should -Contain 'refreshError'
    }

    It 'shares a ready repository snapshot immediately with a sibling directory' {
        $sibling = Join-Path $script:testRepository 'nested'
        New-Item -ItemType Directory -Path $sibling -Force | Out-Null
        $response = & $script:watcherScript -Request Snapshot -Path $sibling
        $response.snapshot.repositoryRoot | Should -Be ([IO.Path]::GetFullPath($script:testRepository))
    }

    It 'enqueues metadata-driven refreshes and updates snapshot state' {
        $baseline = (& $script:watcherScript -Request Snapshot -Path $script:testRepository).snapshot
        $baseline.refreshedAt | Should -Not -BeNullOrEmpty

        $targetFile = Join-Path $script:testRepository 'tracked.txt'
        $writeAttempts = 0
        do {
            $writeAttempts++
            try {
                Set-Content -LiteralPath $targetFile -Value "update-$([guid]::NewGuid().ToString('N'))"
                $writeSucceeded = $true
            } catch [System.IO.IOException] {
                Start-Sleep -Milliseconds 100
                $writeSucceeded = $false
            }
        } while (-not $writeSucceeded -and $writeAttempts -lt 10)
        $writeSucceeded | Should -BeTrue

        $updated = $null
        $deadline = [datetime]::UtcNow.AddSeconds(8)
        do {
            Start-Sleep -Milliseconds 100
            $updated = (& $script:watcherScript -Request Snapshot -Path $script:testRepository).snapshot
        } while (
            (
                -not $updated -or
                [string] $updated.refreshedAt -eq [string] $baseline.refreshedAt -or
                (
                    $updated.workingTree.added +
                    $updated.workingTree.modified +
                    $updated.workingTree.deleted +
                    $updated.staged.added +
                    $updated.staged.modified +
                    $updated.staged.deleted +
                    $updated.conflicts
                ) -lt 1
            ) -and [datetime]::UtcNow -lt $deadline
        )

        (
            $updated.workingTree.added +
            $updated.workingTree.modified +
            $updated.workingTree.deleted +
            $updated.staged.added +
            $updated.staged.modified +
            $updated.staged.deleted +
            $updated.conflicts
        ) | Should -BeGreaterThan 0
        $updated.refreshedAt | Should -Not -Be $baseline.refreshedAt
    }

    It 'refreshes a cached snapshot promptly after git add updates repository metadata' {
        try {
            $env:GIT_PROMPT_WATCHER_PERIODIC_SECONDS = '60'
            (& $script:watcherScript -Restart).state | Should -Be 'Healthy'

            $snapshot = $null
            $readyDeadline = [datetime]::UtcNow.AddSeconds(5)
            do {
                Start-Sleep -Milliseconds 50
                $snapshot = (& $script:watcherScript -Request Snapshot -Path $script:testRepository).snapshot
            } while (-not $snapshot -and [datetime]::UtcNow -lt $readyDeadline)
            $snapshot | Should -Not -BeNullOrEmpty
            $baseline = [string] $snapshot.refreshedAt

            $addedFile = Join-Path $script:testRepository "event-add-$([guid]::NewGuid().ToString('N')).txt"
            Set-Content -LiteralPath $addedFile -Value 'staged through metadata event'
            & git -C $script:testRepository add -- $addedFile

            $updated = $snapshot
            $deadline = [datetime]::UtcNow.AddSeconds(5)
            do {
                Start-Sleep -Milliseconds 50
                $updated = (& $script:watcherScript -Request Snapshot -Path $script:testRepository).snapshot
            } while (
                (
                    -not $updated -or
                    [string] $updated.refreshedAt -eq $baseline
                ) -and
                [datetime]::UtcNow -lt $deadline
            )

            $updated | Should -Not -BeNullOrEmpty
            $updated.refreshedAt | Should -Not -Be $baseline
            $updated.staged.added | Should -BeGreaterThan 0
        } finally {
            $env:GIT_PROMPT_WATCHER_PERIODIC_SECONDS = '3'
            (& $script:watcherScript -Restart).state | Should -Be 'Healthy'
        }
    }

    It 'keeps snapshot requests non-blocking while refresh work is in progress' {
        $env:GIT_PROMPT_WATCHER_REFRESH_DELAY_MS = '1200'
        try {
            Set-Content -LiteralPath (Join-Path $script:testRepository 'tracked.txt') -Value "slow-$([guid]::NewGuid().ToString('N'))"
            & git -C $script:testRepository add tracked.txt | Out-Null

            Start-Sleep -Milliseconds 150
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            $response = & $script:watcherScript -Request Snapshot -Path $script:testRepository
            $stopwatch.Stop()

            $response.state | Should -Be 'Healthy'
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 700
        } finally {
            Remove-Item Env:GIT_PROMPT_WATCHER_REFRESH_DELAY_MS -ErrorAction SilentlyContinue
        }
    }

    It 'refreshes known repositories periodically including repositories outside the workspace' {
        $first = $null
        $deadline = [datetime]::UtcNow.AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 100
            $first = (& $script:watcherScript -Request Snapshot -Path $script:externalRepository).snapshot
        } while (-not $first -and [datetime]::UtcNow -lt $deadline)
        $first | Should -Not -BeNullOrEmpty

        $startTime = [string] $first.refreshedAt
        $periodic = $first
        $periodicDeadline = [datetime]::UtcNow.AddSeconds(8)
        do {
            Start-Sleep -Milliseconds 150
            $periodic = (& $script:watcherScript -Request Snapshot -Path $script:externalRepository).snapshot
        } while (
            (
                -not $periodic -or
                [string] $periodic.refreshedAt -eq $startTime
            ) -and [datetime]::UtcNow -lt $periodicDeadline
        )

        $periodic.refreshedAt | Should -Not -Be $startTime
    }

    It 'marks snapshots unavailable after refresh cannot reach a known repository' {
        $ephemeralRepository = Join-Path $env:TEMP "git-prompt-watcher-ephemeral-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $ephemeralRepository | Out-Null
        & git -C $ephemeralRepository init -b feature/404 | Out-Null
        & git -C $ephemeralRepository config user.email test@example.invalid
        & git -C $ephemeralRepository config user.name 'Watcher Test'
        Set-Content -LiteralPath (Join-Path $ephemeralRepository 'tracked.txt') -Value 'initial'
        & git -C $ephemeralRepository add tracked.txt
        & git -C $ephemeralRepository commit -m initial | Out-Null
        try {
            $readyDeadline = [datetime]::UtcNow.AddSeconds(5)
            do {
                Start-Sleep -Milliseconds 100
                $readySnapshot = (& $script:watcherScript -Request Snapshot -Path $ephemeralRepository).snapshot
            } while (-not $readySnapshot -and [datetime]::UtcNow -lt $readyDeadline)
            $readySnapshot.available | Should -BeTrue

            Remove-Item -LiteralPath $ephemeralRepository -Recurse -Force

            $unavailable = $null
            $unavailableDeadline = [datetime]::UtcNow.AddSeconds(8)
            do {
                Start-Sleep -Milliseconds 150
                $unavailable = (& $script:watcherScript -Request Snapshot -Path $ephemeralRepository).snapshot
            } while (
                (
                    -not $unavailable -or
                    $unavailable.available
                ) -and [datetime]::UtcNow -lt $unavailableDeadline
            )

            $unavailable.available | Should -BeFalse
        } finally {
            Remove-Item -LiteralPath $ephemeralRepository -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'bounds response reads when a connected pipe stalls' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            $script:watcherScript, [ref] $tokens, [ref] $errors
        )
        $requestFunction = $ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Invoke-GitPromptWatcherRequest'
        }, $true)[0]
        . ([scriptblock]::Create($requestFunction.Extent.Text))

        $pipeName = "GitPromptWatcher-Stall-$([guid]::NewGuid().ToString('N'))"
        $serverJob = Start-Job -ScriptBlock {
            param($Name)
            $server = [IO.Pipes.NamedPipeServerStream]::new($Name, [IO.Pipes.PipeDirection]::InOut)
            try {
                $server.WaitForConnection()
                $reader = [IO.StreamReader]::new($server, [Text.UTF8Encoding]::new($false), $false, 1024, $true)
                $reader.ReadLine() | Out-Null
                Start-Sleep -Seconds 2
            } finally {
                if ($reader) { $reader.Dispose() }
                $server.Dispose()
            }
        } -ArgumentList $pipeName
        try {
            Start-Sleep -Milliseconds 100
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            { Invoke-GitPromptWatcherRequest -PipeName $pipeName -Message @{ type = 'Status' } } |
                Should -Throw '*timed out*'
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 1000
        } finally {
            $serverJob | Stop-Job -ErrorAction SilentlyContinue
            $serverJob | Remove-Job -Force
        }
    }

    It 'distinguishes Stopped from NotRunning and blocks auto-start until restart' {
        & $script:watcherScript -Stop | Out-Null
        $status = & $script:watcherScript -Status
        $status.state | Should -Be 'Stopped'

        & $script:watcherScript | Out-Null
        (& $script:watcherScript -Status).state | Should -Be 'Stopped'

        & $script:watcherScript -Restart | Out-Null
        (& $script:watcherScript -Status).state | Should -Be 'Healthy'
    }

    It 'supports explicit reload and reports paused recovery errors from failed reload preflight' {
        $badSource = Join-Path $TestDrive 'missing-reload-source.ps1'
        $goodSource = $script:watcherScript
        $env:GIT_PROMPT_WATCHER_SOURCE_PATH = $badSource
        try {
            $reload = & $script:watcherScript -Reload
            $reload.state | Should -Be 'Paused'
            $reload.sourceLoadError | Should -Match 'source'

            $status = & $script:watcherScript -Status
            $status.state | Should -Be 'Paused'
            $status.sourceLoadError | Should -Not -BeNullOrEmpty
        } finally {
            $env:GIT_PROMPT_WATCHER_SOURCE_PATH = $goodSource
        }

        $recovered = & $script:watcherScript -Reload
        $recovered.state | Should -Be 'Healthy'
        $recovered.sourceLoadError | Should -BeNullOrEmpty
    }

    It 'keeps a recoverable paused owner after restart preflight fails' {
        $env:GIT_PROMPT_WATCHER_SOURCE_PATH = (Join-Path $TestDrive 'missing-restart-source.ps1')
        try {
            $restart = & $script:watcherScript -Restart
            $restart.state | Should -Be 'Paused'
            $restart.sourceLoadError | Should -Not -BeNullOrEmpty
        } finally {
            $env:GIT_PROMPT_WATCHER_SOURCE_PATH = $script:watcherScript
        }

        (& $script:watcherScript -Status).state | Should -Be 'Paused'
        (& $script:watcherScript -Restart).state | Should -Be 'Healthy'
    }

    It 'exits when no qualifying PowerShell process remains after poll interval' {
        $isolatedKey = [guid]::NewGuid().ToString('N').Substring(0, 24)
        $quotedScript = $script:watcherScript.Replace("'", "''")
        $workerCommand = @"
`$env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = '1'
`$env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS = '1'
& '$quotedScript' -Worker -WorkerIdentityKey '$isolatedKey'
"@
        $runner = Start-Process -FilePath (Get-Process -Id $PID).Path `
            -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', $workerCommand) `
            -WindowStyle Hidden -PassThru
        try {
            $runner.WaitForExit(6000) | Should -BeTrue
        } finally {
            if (-not $runner.HasExited) {
                Stop-Process -Id $runner.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
}


Describe 'Git prompt snapshot integration' {
    BeforeAll {
        $script:promptScript = Join-Path $PSScriptRoot '..\Install-Prompt.ps1'
        . $script:promptScript -SkipGitPromptWatcherStart
    }

    It 'preserves formatter colors counters and branch link from raw state' {
        $snapshot = [pscustomobject]@{
            available = $true; branch = 'feature/123'; hasUpstream = $true
            hasAheadBehind = $true; ahead = 2; behind = 1; conflicts = 1
            staged = [pscustomobject]@{ added = 1; modified = 2; deleted = 3 }
            workingTree = [pscustomobject]@{ added = 4; modified = 5; deleted = 6 }
        }
        $text = Format-GitPromptSnapshot $snapshot
        $text | Should -Match ([regex]::Escape('https://dev.azure.com/rocom-service/TauOffice/_workitems/edit/123'))
        $text | Should -Match ([regex]::Escape("`e[33m1 2"))
        $text | Should -Match ([regex]::Escape("`e[32m+1 ~2 -3"))
        $text | Should -Match ([regex]::Escape("`e[31m+4 ~5 -6"))
    }

    It 'renders no segment for missing unavailable or timed-out state' {
        (Format-GitPromptSnapshot $null) | Should -Be ''
        (Format-GitPromptSnapshot ([pscustomobject]@{ available = $false })) | Should -Be ''

        $global:GitPromptWatcherScript = Join-Path $env:TEMP 'missing-watcher-script.ps1'
        (Get-GitPromptCached) | Should -Be ''
    }

    It 'renders paused watcher load errors above the prompt' {
        $fakeWatcher = Join-Path $TestDrive 'paused-watcher.ps1'
        Set-Content -LiteralPath $fakeWatcher -Value @'
[pscustomobject]@{
    state = 'Paused'
    sourceLoadError = 'reload failed'
    snapshot = [pscustomobject]@{
        available = $true; branch = 'feature/123'; hasUpstream = $false
        hasAheadBehind = $false; ahead = 0; behind = 0; conflicts = 0
        staged = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }
        workingTree = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }
    }
}
'@
        $global:GitPromptWatcherScript = $fakeWatcher
        Mock Invoke-GitPromptWatcherSnapshotRequest { & $global:GitPromptWatcherScript }
        $rendered = prompt 6>&1 | Out-String
        $rendered | Should -Match 'Invoke-GitPromptWatcher: reload failed'
    }

    It 'renders a ready snapshot through the public prompt function without invoking Git' {
        $fakeWatcher = Join-Path $TestDrive 'fake-watcher.ps1'
        Set-Content -LiteralPath $fakeWatcher -Value @'
[pscustomobject]@{
    snapshot = [pscustomobject]@{
        available = $true; branch = 'feature/123'; hasUpstream = $false
        hasAheadBehind = $false; ahead = 0; behind = 0; conflicts = 0
        staged = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }
        workingTree = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }
    }
}
'@
        $global:GitPromptWatcherScript = $fakeWatcher
        Mock Invoke-GitPromptWatcherSnapshotRequest { & $global:GitPromptWatcherScript }
        function global:git { throw 'prompt invoked Git synchronously' }
        try {
            $rendered = prompt 6>&1 | Out-String
            $rendered | Should -Match 'feature/123'
        } finally {
            Remove-Item Function:\git -ErrorAction SilentlyContinue
        }
    }
}
