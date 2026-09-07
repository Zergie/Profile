#Requires -Version 7.0

BeforeAll {
    $script:GitPromptWatcherImportOnly = $true
    $script:watcher = Join-Path $PSScriptRoot '..\Startup\Invoke-GitPromptWatcher.ps1'
    . $script:watcher
    $script:previousTestId = $env:GIT_PROMPT_WATCHER_TEST_ID
    $script:previousCache = Get-Variable GitPromptSnapshotCache -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    $script:previousNotificationJob = Get-Variable GitPromptNotificationJob -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    $env:GIT_PROMPT_WATCHER_TEST_ID = 'boundaries-' + [guid]::NewGuid().ToString('N')
    $script:parent = Join-Path $TestDrive 'parent'
    $script:child = Join-Path $script:parent 'Firmware\child'
    $script:ordinary = Join-Path $script:parent 'ordinary'
    New-Item -ItemType Directory -Path $script:child, $script:ordinary | Out-Null
    & git init -b parent $script:parent | Out-Null
    # A .git file reproduces submodule/worktree boundaries without a remote.
    & git init -b child --separate-git-dir (Join-Path $TestDrive 'child-metadata') $script:child | Out-Null
    $script:childSnapshot = Get-GitPromptRepositorySnapshot $script:child
    $script:parentSnapshot = Get-GitPromptRepositorySnapshot $script:parent
}

AfterAll {
    & $script:watcher -Stop | Out-Null
    $env:GIT_PROMPT_WATCHER_TEST_ID = $script:previousTestId
    $global:GitPromptSnapshotCache = $script:previousCache
    $global:GitPromptNotificationJob = $script:previousNotificationJob
}

Describe 'Git prompt repository boundaries' {
    It 'recognizes a .git directory below an already cached ordinary path' {
        $nested = Join-Path $script:ordinary 'new-repository'
        New-Item -ItemType Directory -Path $nested | Out-Null
        Test-GitPromptRepositoryPath $nested $script:parent | Should -BeTrue
        & git init -b nested $nested | Out-Null
        Test-GitPromptRepositoryPath $nested $script:parent | Should -BeFalse
        Test-GitPromptRepositoryPath $nested $nested | Should -BeTrue
    }

    It 'discovers a nested repository instead of reusing a cached parent' {
        & $script:watcher
        $deadline = [datetime]::UtcNow.AddSeconds(10)
        do {
            $response = & $script:watcher -Request Snapshot -Path $script:parent
            if ($response.snapshot) { break }
            Start-Sleep -Milliseconds 50
        } while ([datetime]::UtcNow -lt $deadline)
        $response.snapshot.branch | Should -Be 'parent'
        (& $script:watcher -Request Snapshot -Path $script:ordinary).snapshot.branch | Should -Be 'parent'

        $deadline = [datetime]::UtcNow.AddSeconds(10)
        do {
            $response = & $script:watcher -Request Snapshot -Path $script:child
            if ($response.snapshot) { break }
            Start-Sleep -Milliseconds 50
        } while ([datetime]::UtcNow -lt $deadline)
        $response.snapshot.repositoryRoot | Should -Be $script:child
        $response.snapshot.branch | Should -Be 'child'
    }

    It 'does not render a parent cache after entering a nested repository' {
        Mock Receive-GitPromptSnapshotRefresh {}
        Mock Receive-GitPromptNotifications {}
        Mock Start-GitPromptSnapshotRefresh {}
        $global:GitPromptSnapshotCache = [pscustomobject]@{
            path = $script:parent
            response = [pscustomobject]@{ state = 'Healthy'; snapshot = [pscustomobject]$script:parentSnapshot }
        }
        Push-Location $script:child
        try {
            Get-GitPromptCached | Should -Be ''
            Should -Invoke Start-GitPromptSnapshotRefresh -Times 1 -Exactly
        } finally { Pop-Location }
    }

    It 'ignores parent notifications while inside a nested repository' {
        $global:GitPromptNotificationJob = Start-ThreadJob {
            param($Root, $Snapshot)
            @{ repositoryRoot = $Root; snapshot = $Snapshot } | ConvertTo-Json -Depth 5 -Compress
        } -ArgumentList $script:parent, $script:parentSnapshot
        $global:GitPromptNotificationJob | Wait-Job | Out-Null
        $global:GitPromptSnapshotCache = [pscustomobject]@{
            path = $script:child
            response = [pscustomobject]@{ state = 'Healthy'; snapshot = [pscustomobject]$script:childSnapshot }
        }
        Push-Location $script:child
        try {
            Receive-GitPromptNotifications -PassThru | Should -BeFalse
            $global:GitPromptSnapshotCache.response.snapshot.branch | Should -Be 'child'
        } finally {
            Pop-Location
            $global:GitPromptNotificationJob | Remove-Job -Force
            $global:GitPromptNotificationJob = $null
        }
    }
}
