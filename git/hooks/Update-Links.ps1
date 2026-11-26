<#
.SYNOPSIS
    Brings app configs up to date after git replaced their repo files (checkout, merge, rebase).

.DESCRIPTION
    Run from the post-checkout, post-merge and post-rewrite hooks (core.hooksPath = git/hooks,
    set by Install-Tools.ps1 -junctions). Handles the file entries from Install-Tools.ps1 -links; folder
    junctions follow the repo on their own.

    Hard links: git updates a file by deleting it and writing a new one, so the app's path still
    points to the old content. The link is re-created only when that loses nothing:
      - the app's file is missing or has the same content as the repo file, or
      - it has the content the repo file had at -PreviousRef, i.e. git just broke the link.
    Otherwise the app rewrote the file after its link broke; it is left as is, with a warning.

    Copies (type 'copy', git/copy-links.conf): the repo file is copied to the app. The
    fsmonitor hook imports the app's file before every git command, so normally the app has
    nothing the repo lacks. If its settings (after the machine-keys filter) match neither the
    previous nor the current commit, it is backed up as <file>.bak-<timestamp> first.
#>
param(
    # The commit before the checkout/merge/rebase (post-checkout $1, or ORIG_HEAD).
    [string] $PreviousRef
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path

function Get-RepoRelativePath([string] $Path) {
    if (-not $Path.StartsWith("$repo\", [StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $Path.Substring($repo.Length + 1).Replace('\', '/')
}

function Get-PreviousHash([string] $Source) {
    $relativePath = Get-RepoRelativePath $Source
    if (-not $PreviousRef -or -not $relativePath) { return $null }
    $temp = New-TemporaryFile
    try {
        # --filters applies smudge and line-ending conversion, giving the file as git wrote it.
        git -C $repo cat-file --filters "${PreviousRef}:$relativePath" > $temp.FullName 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return (Get-FileHash -LiteralPath $temp.FullName).Hash
    } finally {
        Remove-Item -LiteralPath $temp.FullName -Force
    }
}

function Get-BlobId([string] $Ref, [string] $RelativePath) {
    if (-not $Ref) { return $null }
    $id = git -C $repo rev-parse --verify --quiet "${Ref}:$RelativePath" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return $id
}

function Update-HardLink([string] $Source, [string] $Destination) {
    if (Test-Path -LiteralPath $Destination) {
        $linkedPaths = fsutil hardlink list $Destination 2>$null
        $canListLinks = $LASTEXITCODE -eq 0
        if ($linkedPaths -contains $Source.Substring(2)) { return }

        $destinationHash = (Get-FileHash -LiteralPath $Destination).Hash
        $sameContent = $destinationHash -eq (Get-FileHash -LiteralPath $Source).Hash
        # Some folders don't support listing links (fsutil error 50); identical content is good enough there.
        if ($sameContent -and -not $canListLinks) { return }

        if (-not $sameContent -and $destinationHash -ne (Get-PreviousHash $Source)) {
            Write-Warning "$Destination is not linked to $Source and has local changes; left as is."
            return
        }
        Remove-Item -LiteralPath $Destination -Force
    }

    New-Item -ItemType HardLink -Path $Destination -Value $Source | Out-Null
    Write-Host "Re-linked $Destination"
}

function Update-Copy([string] $Source, [string] $Destination, [string[]] $Writers) {
    if ((Test-Path -LiteralPath $Destination) -and
        (Get-FileHash -LiteralPath $Destination).Hash -eq (Get-FileHash -LiteralPath $Source).Hash) { return }

    $relativePath = Get-RepoRelativePath $Source
    if ((Test-Path -LiteralPath $Destination) -and $relativePath) {
        # hash-object --path applies this path's clean filter, so machine-specific keys don't count.
        $appBlob = git -C $repo hash-object --path=$relativePath -- $Destination
        if ($appBlob -notin @((Get-BlobId $PreviousRef $relativePath), (Get-BlobId 'HEAD' $relativePath))) {
            $backup = "$Destination.bak-$(Get-Date -Format yyyyMMddHHmmss)"
            Copy-Item -LiteralPath $Destination -Destination $backup
            Write-Warning "$Destination had settings that are in no commit; saved it as $backup"
        }
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Write-Host "Updated $Destination"

    # The pre-rebase guard covers pulls; checkouts and merges have no hook that runs before them.
    $running = @(Get-Process | Where-Object { $process = $_; $process.Path -and @($Writers | Where-Object { $process.Path -like $_ }).Count })
    if ($running) {
        Write-Warning ("$(($running.Path | Sort-Object -Unique) -join ', ') is running and may write its old settings " +
                       "back to $Destination. Close it; if git then shows $Source as changed, run: " +
                       "git checkout -- $(Get-RepoRelativePath $Source)")
    }
}

foreach ($link in & "$repo\Install-Tools.ps1" -links) {
    $source = [IO.Path]::GetFullPath($link.source)
    $destination = $link.destination
    if ($source.Contains('*') -or $destination.Contains('*')) { continue }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    if (-not (Test-Path -LiteralPath (Split-Path $destination))) { continue }

    if ($link.PSObject.Properties['type'] -and $link.type -eq 'copy') {
        Update-Copy $source $destination $link.writers
    } else {
        Update-HardLink $source $destination
    }
}
