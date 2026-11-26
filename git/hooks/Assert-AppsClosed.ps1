<#
.SYNOPSIS
    Refuses a pull/rebase that changes a copy-synced app config while that app is running.

.DESCRIPTION
    Run by the pre-rebase hook; `git pull` rebases here (pull.rebase = true in git/.gitconfig).
    A running app keeps its settings in memory and writes them back on its next save, which would
    undo the pulled change. Writer processes per file are listed in git/copy-links.conf.
    Exits 1 with a message naming the processes to close; set SKIP_APP_GUARD=1 to skip the check.
#>
param(
    [Parameter(Mandatory)] [string] $Upstream
)

$ErrorActionPreference = 'Stop'
if ($env:SKIP_APP_GUARD) { exit 0 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path

$base = git -C $repo merge-base HEAD $Upstream 2>$null
if ($LASTEXITCODE -ne 0) { exit 0 }

$copyLinks = @(& "$repo\Install-Tools.ps1" -links | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'copy' })
$paths = @($copyLinks | ForEach-Object { $_.source.Substring($repo.Length + 1).Replace('\', '/') } | Sort-Object -Unique)
if (-not $paths) { exit 0 }

$changed = @(git -C $repo diff --name-only $base $Upstream -- @paths)
if (-not $changed) { exit 0 }

$processes = Get-Process | Where-Object Path
$blocking = foreach ($link in $copyLinks) {
    $relativePath = $link.source.Substring($repo.Length + 1).Replace('\', '/')
    if ($relativePath -notin $changed) { continue }
    foreach ($process in $processes) {
        if (@($link.writers | Where-Object { $process.Path -like $_ }).Count -gt 0) {
            [pscustomobject]@{ File = $relativePath; Process = $process.Path }
        }
    }
}

if ($blocking) {
    [Console]::Error.WriteLine("The pull changes app configs whose apps are running; they would write their old settings back.")
    foreach ($group in $blocking | Group-Object File) {
        [Console]::Error.WriteLine("  $($group.Name): close $(($group.Group.Process | Sort-Object -Unique) -join ', ')")
    }
    [Console]::Error.WriteLine("Close them and pull again, or set SKIP_APP_GUARD=1 to pull anyway.")
    exit 1
}
exit 0
