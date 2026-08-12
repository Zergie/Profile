#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSupport.ps1')

    $script:watcherScript = Join-Path $PSScriptRoot '..\Startup\Invoke-GitPromptWatcher.ps1'
    $quotedWatcherScript = $script:watcherScript.Replace("'", "''")
    $script:watcherModule = New-Module -Name (
        'Invoke-GitPromptWatcher.TestImport.' + [guid]::NewGuid().ToString('N')
    ) -ScriptBlock ([scriptblock]::Create(@"
`$script:GitPromptWatcherImportOnly = `$true
. '$quotedWatcherScript'
"@))
    Import-Module -ModuleInfo $script:watcherModule -Force
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

    function New-WatcherLifecycleFixture {
        $environmentNames = @(
            'GIT_PROMPT_WATCHER_TEST_ID',
            'GIT_PROMPT_WATCHER_PERIODIC_SECONDS',
            'GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS',
            'GIT_PROMPT_WATCHER_REFRESH_DELAY_MS',
            'GIT_PROMPT_WATCHER_SOURCE_PATH',
            'GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS'
        )
        $environment = @{}
        foreach ($name in $environmentNames) {
            $value = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            $environment[$name] = [pscustomobject]@{
                Exists = $null -ne $value
                Value = if ($value) { $value.Value } else { $null }
            }
        }

        $testId = [guid]::NewGuid().ToString('N')
        $env:GIT_PROMPT_WATCHER_TEST_ID = $testId
        $env:GIT_PROMPT_WATCHER_PERIODIC_SECONDS = '3'
        $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = '2'
        Remove-Item Env:GIT_PROMPT_WATCHER_REFRESH_DELAY_MS -ErrorAction SilentlyContinue
        Remove-Item Env:GIT_PROMPT_WATCHER_SOURCE_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS -ErrorAction SilentlyContinue

        $sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
        $userName = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $bytes = [Text.Encoding]::UTF8.GetBytes("$userName|$sessionId|$testId")
        $key = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).Substring(0, 24)
        $created = $false
        $stoppedEvent = [Threading.EventWaitHandle]::new(
            $false,
            [Threading.EventResetMode]::ManualReset,
            "Local\GitPromptWatcher-Stopped-$key",
            [ref] $created
        )
        $stoppedEvent.Reset() | Out-Null

        [pscustomobject]@{
            Environment = $environment
            Key = $key
            PipeName = "GitPromptWatcher-$key"
            NotificationPipeName = "GitPromptWatcher-Notifications-$key"
            StoppedEvent = $stoppedEvent
            WorkerPids = [Collections.Generic.List[int]]::new()
        }
    }

    function Add-WatcherWorkerPid {
        param($Fixture, [int] $ProcessId)

        if (-not $Fixture.WorkerPids.Contains($ProcessId)) {
            $Fixture.WorkerPids.Add($ProcessId)
        }
    }

    function Get-WatcherWorkerDiagnostics {
        param($Worker)

        $stdout = if (Test-Path -LiteralPath $Worker.StdOutPath) {
            Get-Content -LiteralPath $Worker.StdOutPath -Raw
        } else {
            ''
        }
        $stderr = if (Test-Path -LiteralPath $Worker.StdErrPath) {
            Get-Content -LiteralPath $Worker.StdErrPath -Raw
        } else {
            ''
        }
        "process id $($Worker.Process.Id); stdout: $stdout; stderr: $stderr"
    }

    function Start-TestWatcherWorker {
        param(
            [Parameter(Mandatory)] $Fixture,
            [string] $IdentityKey = $Fixture.Key
        )

        $token = [guid]::NewGuid().ToString('N')
        $stdoutPath = Join-Path $TestDrive "watcher-$token.stdout"
        $stderrPath = Join-Path $TestDrive "watcher-$token.stderr"
        $process = Start-Process -FilePath (Get-Process -Id $PID).Path `
            -ArgumentList @(
                '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $script:watcherScript,
                '-Worker', '-WorkerIdentityKey', $IdentityKey
            ) `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -WindowStyle Hidden -PassThru
        Add-WatcherWorkerPid -Fixture $Fixture -ProcessId $process.Id
        [pscustomobject]@{
            Process = $process
            StdOutPath = $stdoutPath
            StdErrPath = $stderrPath
        }
    }

    function Wait-WatcherStatus {
        param(
            [Parameter(Mandatory)] $Fixture,
            [Parameter(Mandatory)] [string] $ExpectedState,
            [int] $TimeoutSeconds = 5,
            $DiagnosticWorker
        )

        $lastStatus = $null
        try {
            Wait-TestCondition -Operation "Git prompt watcher status '$ExpectedState'" `
                -TimeoutSeconds $TimeoutSeconds -Condition {
                    $lastStatus = & $script:watcherScript -Status
                    if ($lastStatus.state -eq $ExpectedState) {
                        if ($lastStatus.processId) {
                            Add-WatcherWorkerPid -Fixture $Fixture -ProcessId ([int] $lastStatus.processId)
                        }
                        return $lastStatus
                    }
                    return $false
                } | Out-Null
        } catch {
            $diagnostics = if ($DiagnosticWorker) {
                Get-WatcherWorkerDiagnostics -Worker $DiagnosticWorker
            } else {
                "last status: $($lastStatus | ConvertTo-Json -Compress)"
            }
            throw "$($_.Exception.Message)`n$diagnostics"
        }
        return $lastStatus
    }

    function Connect-TestWatcherPipe {
        param(
            [Parameter(Mandatory)] $Fixture,
            [string] $PipeName = $Fixture.PipeName,
            [int] $TimeoutSeconds = 5,
            $DiagnosticWorker
        )

        $pipe = [IO.Pipes.NamedPipeClientStream]::new(
            '.', $PipeName, [IO.Pipes.PipeDirection]::InOut,
            [IO.Pipes.PipeOptions]::Asynchronous,
            [Security.Principal.TokenImpersonationLevel]::Impersonation
        )
        try {
            Wait-TestCondition -Operation "connection to watcher pipe '$PipeName'" `
                -TimeoutSeconds $TimeoutSeconds -Condition {
                    try {
                        $pipe.Connect(100)
                        return $true
                    } catch [TimeoutException] {
                        return $false
                    }
                } | Out-Null
            return $pipe
        } catch {
            $pipe.Dispose()
            if ($DiagnosticWorker) {
                throw "$($_.Exception.Message)`n$(Get-WatcherWorkerDiagnostics -Worker $DiagnosticWorker)"
            }
            throw
        }
    }

    function Read-TestWatcherPipeLine {
        param(
            [Parameter(Mandatory)] [IO.StreamReader] $Reader,
            [Parameter(Mandatory)] [IO.Pipes.NamedPipeClientStream] $Pipe,
            [int] $TimeoutMilliseconds = 1000
        )

        $readTask = $Reader.ReadLineAsync()
        if (-not $readTask.Wait($TimeoutMilliseconds)) {
            $Pipe.Dispose()
            throw "Watcher pipe response timed out after $TimeoutMilliseconds ms."
        }
        return $readTask.Result
    }

    function Complete-TestWatcherJobs {
        param(
            [Parameter(Mandatory)] [object[]] $Jobs,
            [int] $TimeoutSeconds = 10
        )

        Wait-TestCondition -Operation 'concurrent watcher startup jobs' `
            -TimeoutSeconds $TimeoutSeconds -Condition {
                @($Jobs | Where-Object State -ne 'Completed').Count -eq 0
            } | Out-Null
        $jobErrors = @()
        $output = @($Jobs | Receive-Job -ErrorAction SilentlyContinue -ErrorVariable +jobErrors)
        if ($jobErrors) {
            throw "Concurrent watcher startup jobs failed: $($jobErrors | Out-String)`nOutput: $($output | Out-String)"
        }
    }

    function Remove-WatcherLifecycleFixture {
        param([Parameter(Mandatory)] $Fixture)

        try {
            & $script:watcherScript -Stop | Out-Null
        } catch {
        }
        foreach ($processId in @($Fixture.WorkerPids | Select-Object -Unique)) {
            $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($process -and -not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                $process.WaitForExit(3000) | Out-Null
            }
            if ($process) {
                $process.Dispose()
            }
        }
        try {
            $Fixture.StoppedEvent.Dispose()
        } finally {
            foreach ($name in $Fixture.Environment.Keys) {
                $original = $Fixture.Environment[$name]
                if ($original.Exists) {
                    Set-Item -LiteralPath "Env:$name" -Value $original.Value
                } else {
                    Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

AfterAll {
    & $script:watcherScript -Stop | Out-Null
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
    if ($script:watcherModule) {
        Remove-Module -ModuleInfo $script:watcherModule -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-GitPromptWatcher internals' -Tag 'Internal' {
    It 'is the single runtime script for watcher control and prompt installation' {
        $scripts = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..') -Recurse -File -Filter 'Invoke-Git*.ps1')
        $runtimeScripts = @($scripts | Where-Object FullName -NotLike '*\Tests\*')
        $testScripts = @($scripts | Where-Object Name -Like '*.Tests.ps1')

        $runtimeScripts | Should -HaveCount 1
        $runtimeScripts[0].FullName | Should -Be ([IO.Path]::GetFullPath($script:watcherScript))
        $testScripts | Should -HaveCount 1
        $testScripts[0].FullName | Should -Be ([IO.Path]::GetFullPath($PSCommandPath))
        Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\Install-Prompt.ps1') |
            Should -BeFalse
        Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\Microsoft.PowerShell_profile.ps1') |
            Should -Match ([regex]::Escape('. "$PSScriptRoot\Startup\Invoke-GitPromptWatcher.ps1" -InstallPrompt'))
    }
    It 'imports private request behavior without starting a worker' {
        & $script:watcherModule {
            Get-Command Invoke-GitPromptWatcherRequest | Should -Not -BeNullOrEmpty
        }
        (& $script:watcherScript -Status).state | Should -Be 'NotRunning'
    }

    It 'parses without errors' {
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile(
            $script:watcherScript, [ref] $null, [ref] $errors
        ) | Out-Null
        $errors | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-GitPromptWatcher snapshots' -Tag 'Command' {

    It 'preloads direct C:\GIT repositories without a snapshot request' {
        (& $script:watcherScript -Restart).state | Should -Be 'Healthy'
        Start-Sleep -Seconds 3
        $snapshot = (& $script:watcherScript -Request Snapshot -Path $script:startupRepository).snapshot

        $snapshot.available | Should -BeTrue
        $snapshot.branch | Should -Be 'feature/startup'
        $snapshot.repositoryRoot | Should -Be ([IO.Path]::GetFullPath($script:startupRepository))
    }

    It 'accepts a structured request without exposing mutable cache ownership' {
        $response = & $script:watcherScript -Request Snapshot -Path $TestDrive
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
            $baselineStagedAdded = [int] $snapshot.staged.added

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
                    [int] $updated.staged.added -le $baselineStagedAdded
                ) -and
                [datetime]::UtcNow -lt $deadline
            )

            $updated | Should -Not -BeNullOrEmpty
            $updated.staged.added | Should -BeGreaterThan $baselineStagedAdded
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
            {
                & $script:watcherModule {
                    param($PipeName)
                    Invoke-GitPromptWatcherRequest -PipeName $PipeName -Message @{ type = 'Status' }
                } $pipeName
            } |
                Should -Throw '*timed out*'
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 1000
        } finally {
            $serverJob | Stop-Job -ErrorAction SilentlyContinue
            $serverJob | Remove-Job -Force
        }
    }

}

Describe 'Invoke-GitPromptWatcher lifecycle' -Tag 'Command' {
    BeforeEach {
        $script:lifecycleFixture = New-WatcherLifecycleFixture
    }

    AfterEach {
        if ($script:lifecycleFixture) {
            Remove-WatcherLifecycleFixture -Fixture $script:lifecycleFixture
            $script:lifecycleFixture = $null
        }
    }

    It 'reports NotRunning before startup' {
        (& $script:watcherScript -Status).state | Should -Be 'NotRunning'
    }

    It 'starts exactly one healthy owner for concurrent clients' {
        $jobs = 1..4 | ForEach-Object {
            Start-Job -ScriptBlock {
                param($Pwsh, $Script, $TestId)
                $env:GIT_PROMPT_WATCHER_TEST_ID = $TestId
                & $Pwsh -NoLogo -NoProfile -NonInteractive -File $Script
            } -ArgumentList (Get-Process -Id $PID).Path, $script:watcherScript, $env:GIT_PROMPT_WATCHER_TEST_ID
        }
        try {
            Complete-TestWatcherJobs -Jobs $jobs
            $statuses = 1..4 | ForEach-Object { & $script:watcherScript -Status }
            @($statuses.state | Select-Object -Unique) | Should -Be @('Healthy')
            $ownerPids = @($statuses.processId | Select-Object -Unique)
            $ownerPids.Count | Should -Be 1
            Add-WatcherWorkerPid -Fixture $script:lifecycleFixture -ProcessId ([int] $ownerPids[0])
            (Get-Process -Id $ownerPids[0] -ErrorAction Stop).HasExited | Should -BeFalse
        } finally {
            $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
        }
    }

    It 'remains ready across repeated restarts' {
        1..10 | ForEach-Object {
            $restart = & $script:watcherScript -Restart
            $restart.state | Should -Be 'Healthy'
            Add-WatcherWorkerPid -Fixture $script:lifecycleFixture -ProcessId ([int] $restart.processId)
        }
        Wait-WatcherStatus -Fixture $script:lifecycleFixture -ExpectedState Healthy | Out-Null
        (& $script:watcherScript -Status).state | Should -Be 'Healthy'
    }

    It 'replaces an unresponsive worker that owns the current identity' {
        $worker = Start-TestWatcherWorker -Fixture $script:lifecycleFixture
        $pipe = Connect-TestWatcherPipe -Fixture $script:lifecycleFixture -DiagnosticWorker $worker
        try {
            $restart = & $script:watcherScript -Restart
            $restart.state | Should -Be 'Healthy'
            $restart.processId | Should -Not -Be $worker.Process.Id
            Add-WatcherWorkerPid -Fixture $script:lifecycleFixture -ProcessId ([int] $restart.processId)
        } finally {
            $pipe.Dispose()
        }
    }

    It 'does not let a completed client connection block another request' {
        $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = '60'
        $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS = '1'
        $worker = Start-TestWatcherWorker -Fixture $script:lifecycleFixture
        Wait-WatcherStatus -Fixture $script:lifecycleFixture -ExpectedState Healthy -DiagnosticWorker $worker | Out-Null
        $pipe = Connect-TestWatcherPipe -Fixture $script:lifecycleFixture -DiagnosticWorker $worker
        $reader = $null
        $writer = $null
        try {
            $writer = [IO.StreamWriter]::new($pipe, [Text.UTF8Encoding]::new($false), 1024, $true)
            $reader = [IO.StreamReader]::new($pipe, [Text.UTF8Encoding]::new($false), $false, 1024, $true)
            $writer.AutoFlush = $true
            $writer.WriteLine('{"type":"Status"}')
            (Read-TestWatcherPipeLine -Reader $reader -Pipe $pipe | ConvertFrom-Json).state | Should -Be 'Healthy'
            Wait-WatcherStatus -Fixture $script:lifecycleFixture -ExpectedState Healthy | Out-Null
            (& $script:watcherScript -Status).state | Should -Be 'Healthy'
        } finally {
            if ($reader) { $reader.Dispose() }
            if ($writer) { $writer.Dispose() }
            $pipe.Dispose()
        }
    }

    It 'does not kill a live owner when startup cannot connect to its pipe' {
        $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = '60'
        $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS = '1'
        $worker = Start-TestWatcherWorker -Fixture $script:lifecycleFixture
        $pipe = Connect-TestWatcherPipe -Fixture $script:lifecycleFixture -DiagnosticWorker $worker
        try {
            { & $script:watcherScript } | Should -Throw '*did not become ready*'
            (Get-Process -Id $worker.Process.Id -ErrorAction Stop).HasExited | Should -BeFalse
        } finally {
            $pipe.Dispose()
        }
    }

    It 'distinguishes Stopped from NotRunning and blocks auto-start until restart' {
        & $script:watcherScript -Stop | Out-Null
        (& $script:watcherScript -Status).state | Should -Be 'Stopped'
        & $script:watcherScript | Out-Null
        (& $script:watcherScript -Status).state | Should -Be 'Stopped'
        $restart = & $script:watcherScript -Restart
        $restart.state | Should -Be 'Healthy'
        Add-WatcherWorkerPid -Fixture $script:lifecycleFixture -ProcessId ([int] $restart.processId)
    }

    It 'recovers from a failed reload preflight' {
        & $script:watcherScript | Out-Null
        Wait-WatcherStatus -Fixture $script:lifecycleFixture -ExpectedState Healthy | Out-Null
        $env:GIT_PROMPT_WATCHER_SOURCE_PATH = Join-Path $TestDrive 'missing-reload-source.ps1'
        try {
            $reload = & $script:watcherScript -Reload
            $reload.state | Should -Be 'Paused'
            $reload.sourceLoadError | Should -Match 'source'
            Wait-WatcherStatus -Fixture $script:lifecycleFixture -ExpectedState Paused | Out-Null
            (& $script:watcherScript -Status).sourceLoadError | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Item Env:GIT_PROMPT_WATCHER_SOURCE_PATH -ErrorAction SilentlyContinue
        }
        $recovered = & $script:watcherScript -Reload
        $recovered.state | Should -Be 'Healthy'
        $recovered.sourceLoadError | Should -BeNullOrEmpty
    }

    It 'keeps a recoverable paused owner after restart preflight fails' {
        $env:GIT_PROMPT_WATCHER_SOURCE_PATH = Join-Path $TestDrive 'missing-restart-source.ps1'
        try {
            $restart = & $script:watcherScript -Restart
            $restart.state | Should -Be 'Paused'
            $restart.sourceLoadError | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Item Env:GIT_PROMPT_WATCHER_SOURCE_PATH -ErrorAction SilentlyContinue
        }
        Wait-WatcherStatus -Fixture $script:lifecycleFixture -ExpectedState Paused | Out-Null
        $paused = & $script:watcherScript -Status
        Add-WatcherWorkerPid -Fixture $script:lifecycleFixture -ProcessId ([int] $paused.processId)
        (& $script:watcherScript -Restart).state | Should -Be 'Healthy'
    }

    It 'stays alive while a prompt notification subscriber is connected' {
        $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = '2'
        $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS = '1'
        $worker = Start-TestWatcherWorker -Fixture $script:lifecycleFixture
        Wait-WatcherStatus -Fixture $script:lifecycleFixture -ExpectedState Healthy -DiagnosticWorker $worker | Out-Null
        $subscriberJob = Start-ThreadJob -ScriptBlock {
            param($PipeName)
            $pipe = [IO.Pipes.NamedPipeClientStream]::new(
                '.', $PipeName, [IO.Pipes.PipeDirection]::InOut,
                [IO.Pipes.PipeOptions]::Asynchronous,
                [Security.Principal.TokenImpersonationLevel]::Impersonation
            )
            try {
                $pipe.Connect(2000)
                $reader = [IO.StreamReader]::new($pipe, [Text.UTF8Encoding]::new($false), $false, 1024, $true)
                $writer = [IO.StreamWriter]::new($pipe, [Text.UTF8Encoding]::new($false), 1024, $true)
                try {
                    $writer.AutoFlush = $true
                    $writer.WriteLine('{"type":"Subscribe"}')
                    $reader.ReadLine()
                    while ($pipe.IsConnected) {
                        $line = $reader.ReadLine()
                        if ($null -eq $line) { break }
                        $line
                    }
                } finally {
                    $writer.Dispose()
                    $reader.Dispose()
                }
            } finally {
                $pipe.Dispose()
            }
        } -ArgumentList $script:lifecycleFixture.NotificationPipeName
        try {
            $acknowledgement = Wait-TestCondition -Operation 'prompt notification subscription' -Condition {
                $lines = @($subscriberJob | Receive-Job -ErrorAction SilentlyContinue)
                if ($lines) { return $lines[0] | ConvertFrom-Json }
                return $null
            }
            $acknowledgement.type | Should -Be 'Subscribed'

            Start-Sleep -Seconds 5

            (& $script:watcherScript -Status).state | Should -Be 'Healthy'
        } finally {
            $subscriberJob | Stop-Job -ErrorAction SilentlyContinue
            $subscriberJob | Remove-Job -Force -ErrorAction SilentlyContinue
        }
    }
    It 'exits when no qualifying PowerShell process remains after the poll interval' {
        $env:GIT_PROMPT_WATCHER_PROCESS_POLL_SECONDS = '1'
        $env:GIT_PROMPT_WATCHER_REQUIRE_CLIENT_REQUESTS = '1'
        $worker = Start-TestWatcherWorker -Fixture $script:lifecycleFixture
        try {
            Wait-TestProcessExit -Process $worker.Process -Operation 'unclaimed watcher worker exit' -TimeoutSeconds 6
            $worker.Process.HasExited | Should -BeTrue
        } catch {
            throw "$($_.Exception.Message)`n$(Get-WatcherWorkerDiagnostics -Worker $worker)"
        }
    }
}


Describe 'Git prompt snapshot integration' -Tag 'Internal' {
    BeforeAll {
        . $script:watcherScript -InstallPrompt -SkipGitPromptWatcherStart
    }

    It 'drains a completed initial snapshot request while the prompt is idle' {
        $snapshotJob = $global:GitPromptSnapshotRefreshJob
        $snapshotCache = $global:GitPromptSnapshotCache
        $path = (Get-Location).Path
        Mock Invoke-GitPromptStatusRowRefresh { $true }
        $completedJob = Start-ThreadJob -ScriptBlock {
            param($RequestPath)
            [pscustomobject]@{
                path = $RequestPath
                response = [pscustomobject]@{
                    state = 'Healthy'
                    snapshot = [pscustomobject]@{
                        available = $true
                        repositoryRoot = $RequestPath
                        branch = 'feature/initial-idle-refresh'
                    }
                }
            }
        } -ArgumentList $path
        try {
            $completedJob | Wait-Job | Out-Null
            $global:GitPromptSnapshotRefreshJob = $completedJob
            $global:GitPromptSnapshotCache = $null

            New-Event -SourceIdentifier PowerShell.OnIdle | Out-Null
            Wait-TestCondition -Operation 'idle initial Git prompt snapshot drain' -Condition {
                $global:GitPromptSnapshotCache.response.snapshot.branch -eq 'feature/initial-idle-refresh'
            } | Out-Null

            $global:GitPromptSnapshotCache.response.snapshot.branch |
                Should -Be 'feature/initial-idle-refresh'
            Should -Invoke Invoke-GitPromptStatusRowRefresh -Times 1 -Exactly
        } finally {
            $global:GitPromptSnapshotRefreshJob = $snapshotJob
            $global:GitPromptSnapshotCache = $snapshotCache
            $completedJob | Remove-Job -Force -ErrorAction SilentlyContinue
        }
    }
    It 'replaces the existing status row without appending another prompt on idle refresh' {
        $snapshotCache = $global:GitPromptSnapshotCache
        $rows = [Collections.Generic.List[string]]::new()
        $rows.Add('┌ old status')
        $rows.Add('└ ')
        $terminal = [pscustomobject]@{
            Cursor = [Management.Automation.Host.Coordinates]::new(0, 1)
            Rows = $rows
        }
        $terminal | Add-Member ScriptMethod GetCursor { $this.Cursor }
        $terminal | Add-Member ScriptMethod ReadRow { param($rowNumber) $this.Rows[$rowNumber] }
        $terminal | Add-Member ScriptMethod WriteRow {
            param($rowNumber, $text, $cursor)
            $this.Rows[$rowNumber] = $text
        }
        $script:cleanRefreshTerminal = $terminal
        Mock Receive-GitPromptSnapshotRefresh { $true }
        Mock Receive-GitPromptNotifications { $false }
        Mock New-GitPromptTerminal { $script:cleanRefreshTerminal }
        Mock Invoke-GitPromptRedraw {
            $script:cleanRefreshTerminal.Rows.Add('┌ duplicate status')
            $script:cleanRefreshTerminal.Rows.Add('└ ')
        }
        try {
            $global:GitPromptSnapshotCache = [pscustomobject]@{
                path = (Get-Location).Path
                response = [pscustomobject]@{
                    state = 'Healthy'
                    snapshot = [pscustomobject]@{
                        available = $true; branch = 'feature/clean-refresh'; hasUpstream = $false
                        hasAheadBehind = $false; ahead = 0; behind = 0; conflicts = 0
                        staged = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }
                        workingTree = [pscustomobject]@{ added = 0; modified = 1; deleted = 0 }
                    }
                }
            }

            Receive-GitPromptIdleUpdates

            $terminal.Rows | Should -HaveCount 2
            $terminal.Rows[0] | Should -Match 'feature/clean-refresh'
            $terminal.Rows[1] | Should -Be '└ '
            Should -Invoke Invoke-GitPromptRedraw -Times 0 -Exactly
        } finally {
            $global:GitPromptSnapshotCache = $snapshotCache
            Remove-Variable -Scope Script -Name cleanRefreshTerminal -ErrorAction SilentlyContinue
        }
    }
    It 'drains pushed snapshots while the prompt is idle' {
        $global:GitPromptNotificationIdleJob | Should -Not -BeNullOrEmpty
        @(
            Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue |
                Where-Object Action -eq $global:GitPromptNotificationIdleJob
        ) | Should -HaveCount 1

        $listenerJob = $global:GitPromptNotificationJob
        $snapshotCache = $global:GitPromptSnapshotCache
        $repositoryRoot = (Get-Location).Path
        $notificationJob = Start-ThreadJob -ScriptBlock {
            param($Root)
            [ordered]@{
                type = 'Snapshot'
                repositoryRoot = $Root
                snapshot = [ordered]@{
                    available = $true
                    repositoryRoot = $Root
                    branch = 'feature/idle-refresh'
                }
            } | ConvertTo-Json -Compress -Depth 5
        } -ArgumentList $repositoryRoot
        try {
            $notificationJob | Wait-Job | Out-Null
            $global:GitPromptNotificationJob = $notificationJob
            $global:GitPromptSnapshotCache = $null

            New-Event -SourceIdentifier PowerShell.OnIdle | Out-Null
            Wait-TestCondition -Operation 'idle Git prompt snapshot drain' -Condition {
                $global:GitPromptSnapshotCache.response.snapshot.branch -eq 'feature/idle-refresh'
            } | Out-Null

            $global:GitPromptSnapshotCache.response.snapshot.branch | Should -Be 'feature/idle-refresh'
        } finally {
            $global:GitPromptNotificationJob = $listenerJob
            $global:GitPromptSnapshotCache = $snapshotCache
            $notificationJob | Remove-Job -Force -ErrorAction SilentlyContinue
        }
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
        $global:GitPromptSnapshotRefreshJob = $null
        $global:GitPromptSnapshotCache = [pscustomobject]@{
            path = (Get-Location).Path
            response = (Invoke-GitPromptWatcherSnapshotRequest -Path (Get-Location).Path)
        }
        $rendered = prompt 6>&1 | Out-String
        $rendered | Should -Match 'Invoke-GitPromptWatcher: reload failed'
    }

    It 'renders a ready snapshot through the public prompt function without invoking Git' {
        Mock Invoke-GitPromptWatcherSnapshotRequest {
            [pscustomobject]@{
                state = 'Healthy'
                snapshot = [pscustomobject]@{
                    available = $true; branch = 'feature/123'; hasUpstream = $false
                    hasAheadBehind = $false; ahead = 0; behind = 0; conflicts = 0
                    staged = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }
                    workingTree = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }
                }
            }
        }

        $global:GitPromptSnapshotRefreshJob = $null
        $global:GitPromptSnapshotCache = [pscustomobject]@{
            path = (Get-Location).Path
            response = Invoke-GitPromptWatcherSnapshotRequest -Path $PSScriptRoot
        }
        $global:GitPromptSnapshotCache.response.snapshot.branch | Should -Be 'feature/123'
        (Get-GitPromptCached).Contains('feature/') | Should -BeTrue
        (Get-GitPromptCached -replace "`e\]8;;.*?`e\\", '').Contains('123') | Should -BeTrue
        $rendered = prompt 6>&1 | Out-String
        $rendered.Contains('feature/') | Should -BeTrue
        $rendered.Contains('123') | Should -BeTrue
    }

    It 'returns the complete multiline prompt through the success stream' {
        $snapshotCache = $global:GitPromptSnapshotCache
        try {
            $global:GitPromptSnapshotCache = [pscustomobject]@{
                path = (Get-Location).Path
                response = [pscustomobject]@{
                    state = 'Healthy'
                    snapshot = [pscustomobject]@{
                        available = $true; repositoryRoot = (Get-Location).Path; branch = 'feature/returned-prompt'
                        hasUpstream = $false; hasAheadBehind = $false; ahead = 0; behind = 0; conflicts = 0
                        staged = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }
                        workingTree = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }
                    }
                }
            }

            $returnedPrompt = prompt 6>$null | Out-String

            $returnedPrompt | Should -Match '┌'
            $returnedPrompt | Should -Match 'feature/returned-prompt'
            $returnedPrompt | Should -Match '└'
            $returnedPrompt.TrimEnd("`r", "`n") | Should -Match (([regex]::Escape("`e[0m")) + '$')
        } finally {
            $global:GitPromptSnapshotCache = $snapshotCache
        }
    }
    It 'builds the production terminal adapter with callable methods' {
        $terminal = New-GitPromptTerminal

        foreach ($methodName in @('GetCursor', 'ReadRow', 'WriteRow')) {
            ($terminal.PSObject.Methods | Where-Object Name -eq $methodName).MemberType |
                Should -Be 'ScriptMethod'
        }
    }
    It 'replaces a marked status row and restores the cursor through the terminal seam' {
        $snapshot = [pscustomobject]@{
            available = $true; branch = 'feature/live'; hasUpstream = $false; hasAheadBehind = $false
            ahead = 0; behind = 0; conflicts = 0
            staged = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }
            workingTree = [pscustomobject]@{ added = 0; modified = 1; deleted = 0 }
        }
        $terminal = [pscustomobject]@{ Cursor = [Management.Automation.Host.Coordinates]::new(12, 4); Written = $null }
        $terminal | Add-Member ScriptMethod GetCursor { $this.Cursor }
        $terminal | Add-Member ScriptMethod ReadRow { param($row) '┌ old status' }
        $terminal | Add-Member ScriptMethod WriteRow {
            param($rowNumber, $text, $cursor)
            $this.Written = [pscustomobject]@{ RowNumber = $rowNumber; Text = $text; Cursor = $cursor }
        }

        Invoke-GitPromptStatusRowRefresh -Snapshot $snapshot -Terminal $terminal | Should -BeTrue
        $terminal.Written.RowNumber | Should -Be 3
        $terminal.Written.Cursor.X | Should -Be 12
        $terminal.Written.Cursor.Y | Should -Be 4
        $terminal.Written.Text | Should -Match '^\[0m┌'
        $terminal.Written.Text | Should -Match (([regex]::Escape("`e[0m")) + '$')
        $terminal.Written.Text | Should -Match 'feature/live'
        $terminal.Written.Text | Should -Match ''
    }

    It 'does not repaint when the row marker is absent' {
        $terminal = [pscustomobject]@{ Cursor = [Management.Automation.Host.Coordinates]::new(0, 2); Writes = 0 }
        $terminal | Add-Member ScriptMethod GetCursor { $this.Cursor }
        $terminal | Add-Member ScriptMethod ReadRow { param($row) 'ordinary output' }
        $terminal | Add-Member ScriptMethod WriteRow { $this.Writes++ }
        $snapshot = [pscustomobject]@{ available = $true; branch = 'main'; staged = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 }; workingTree = [pscustomobject]@{ added = 0; modified = 0; deleted = 0 } }

        Invoke-GitPromptStatusRowRefresh -Snapshot $snapshot -Terminal $terminal | Should -BeFalse
        $terminal.Writes | Should -Be 0
    }

    It 'silently ignores terminal read and repaint failures' {
        $terminal = [pscustomobject]@{ Cursor = [Management.Automation.Host.Coordinates]::new(0, 2) }
        $terminal | Add-Member ScriptMethod GetCursor { $this.Cursor }
        $terminal | Add-Member ScriptMethod ReadRow { throw 'unsupported buffer' }
        $terminal | Add-Member ScriptMethod WriteRow { throw 'unsupported repaint' }
        $snapshot = [pscustomobject]@{ available = $false }

        { Invoke-GitPromptStatusRowRefresh -Snapshot $snapshot -Terminal $terminal } | Should -Not -Throw
    }
}
