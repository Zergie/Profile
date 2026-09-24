#Requires -Version 7.0

BeforeAll {
    $script:savedGlobals = @{}
    foreach ($name in @(
        'GitPromptWatcherPipeName', 'GitPromptSnapshotRefreshJob', 'GitPromptSnapshotCache',
        'GitPromptClientDiagnostics', 'GitPromptClientDiagnosticQueue', 'GitPromptAutomaticIncidentQueue',
        'GitPromptAutomaticIncidentJobs', 'GitPromptAutomaticIncidentDeduplication',
        'GitPromptAutomaticIncidentNotification'
    )) {
        $variable = Get-Variable $name -Scope Global -ErrorAction SilentlyContinue
        $script:savedGlobals[$name] = if ($variable) { [pscustomobject]@{ Value = $variable.Value } } else { $null }
    }
    $script:GitPromptWatcherImportOnly = $true
    . (Join-Path $PSScriptRoot '..\Startup\Invoke-GitPromptWatcher.ps1')
    $script:watcherPath = Join-Path $PSScriptRoot '..\Startup\Invoke-GitPromptWatcher.ps1'
    $key = [guid]::NewGuid().ToString('N')
    $script:identity = [pscustomobject]@{
        Key = $key
        PipeName = "GitPromptWatcher-Test-$key"
        MutexName = "Local\GitPromptWatcher-Test-$key"
        NotificationPipeName = "GitPromptWatcher-Notifications-Test-$key"
    }
    $script:workerJob = Start-ThreadJob -ArgumentList $script:watcherPath, $script:identity, $TestDrive -ScriptBlock {
        param($Source, $Identity, $DiagnosticsRoot)
        $script:GitPromptWatcherImportOnly = $true
        . $Source
        function Get-GitPromptStartupRepositoryPaths { @() }
        function Get-GitPromptWatcherDiagnosticsDirectory { param($IdentityKey) Join-Path $DiagnosticsRoot $IdentityKey }
        Invoke-GitPromptWatcherWorker -Identity $Identity
    }
    Initialize-GitPromptClientDiagnostics -IdentityKey $key
    $global:GitPromptWatcherPipeName = $script:identity.PipeName
    $global:GitPromptSnapshotRefreshJob = $null
    $global:GitPromptSnapshotCache = $null
    $script:repository = Join-Path $TestDrive 'repository'
    New-Item -ItemType Directory $script:repository | Out-Null
    git -C $script:repository init -b feature/initial-request | Out-Null
    $deadline = [datetime]::UtcNow.AddSeconds(10)
    $readyResponse = $null
    do {
        try {
            $readyResponse = Invoke-GitPromptWatcherRequest -PipeName $script:identity.PipeName -Message @{type='Status'}
            break
        } catch {
            $script:lastSetupError = $_
            if ($script:workerJob.State -eq 'Failed') { Receive-Job $script:workerJob -ErrorAction Stop }
            Start-Sleep -Milliseconds 25
        }
    } while ([datetime]::UtcNow -lt $deadline)
    if (-not $readyResponse) {
        Receive-Job $script:workerJob -Keep -ErrorAction Continue
        throw "Isolated worker did not start ($($script:workerJob.State)): $script:lastSetupError"
    }
}

AfterAll {
    if ($global:GitPromptSnapshotRefreshJob) { $global:GitPromptSnapshotRefreshJob | Remove-Job -Force }
    if ($script:workerJob) {
        try { Invoke-GitPromptWatcherRequest -PipeName $script:identity.PipeName -Message @{type='Stop'} | Out-Null } catch { }
        $script:workerJob | Wait-Job -Timeout 5 | Out-Null
        $script:workerJob | Remove-Job -Force
    }
    foreach ($name in $script:savedGlobals.Keys) {
        $previous = $script:savedGlobals[$name]
        if ($previous) { Set-Variable $name -Scope Global -Value $previous.Value }
        else { Remove-Variable $name -Scope Global -ErrorAction SilentlyContinue }
    }
}

Describe 'Initial Git prompt request through the real worker' {
    It 'discovers and renders the branch without a ReportBug request' {
        Push-Location $script:repository
        try {
            # Use the actual background prompt request, not the diagnostic RPC helper.
            Start-GitPromptSnapshotRefresh -Path $script:repository
            $global:GitPromptSnapshotRefreshJob | Wait-Job -Timeout 3 | Out-Null
            Receive-GitPromptSnapshotRefresh
            $global:GitPromptSnapshotCache | Should -Not -BeNullOrEmpty
            $global:GitPromptSnapshotCache.response.state | Should -Be 'Healthy'

            $deadline = [datetime]::UtcNow.AddSeconds(3)
            do {
                Start-Sleep -Milliseconds 50
                Start-GitPromptSnapshotRefresh -Path $script:repository
                $global:GitPromptSnapshotRefreshJob | Wait-Job -Timeout 1 | Out-Null
                Receive-GitPromptSnapshotRefresh
            } while (-not $global:GitPromptSnapshotCache.response.snapshot -and [datetime]::UtcNow -lt $deadline)
            Format-GitPromptSnapshot $global:GitPromptSnapshotCache.response.snapshot |
                Should -Match 'feature/initial-request'
        } finally { Pop-Location }
    }
}

