#Requires -Version 7.0

<#
.SYNOPSIS
    Implements local-tracker features iteratively with Codex or GitHub Copilot CLI.

.DESCRIPTION
    Runs one bounded agent invocation per iteration. Without Feature, the agent
    selects and continues the highest-priority unfinished feature below
    .scratch/<feature>/issues. With Feature, only that active feature is handled.

    Progress is shared through the append-only .scratch/progress.jsonl handoff log.
    Ralph validates each new record and marks its ticket complete.

.EXAMPLE
    Invoke-Ralph.ps1 -Agent codex

.EXAMPLE
    Invoke-Ralph.ps1 -Agent copilot -Iterations 5

.EXAMPLE
    Invoke-Ralph.ps1 -Agent codex -Feature watch-command
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]
    $List,

    [Parameter()]
    [switch]
    $Cleanup,

    [Parameter()]
    [ValidateSet('codex', 'copilot')]
    [string]
    $Agent = 'codex',

    [Parameter()]
    [ValidateRange(1, [int]::MaxValue)]
    [int]
    $Iterations = 32,

    [Parameter()]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete)

        $scratch = Join-Path (Get-Location) '.scratch'
        if (-not (Test-Path -LiteralPath $scratch -PathType Container)) {
            return
        }

        Get-ChildItem -LiteralPath $scratch -Directory |
            Where-Object {
                $_.Name -cne 'done' -and
                (Test-Path -LiteralPath (
                    Join-Path $_.FullName 'spec.md'
                ) -PathType Leaf) -and
                $_.Name.StartsWith(
                    $wordToComplete,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            } |
            Sort-Object Name |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_.Name,
                    $_.Name,
                    [System.Management.Automation.CompletionResultType]::ParameterValue,
                    $_.Name
                )
            }
    })]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        $scratch = Join-Path (Get-Location) '.scratch'
        $candidate = Join-Path $scratch $_
        if ($_ -ceq 'done' -or
            [System.IO.Path]::GetFileName($_) -cne $_ -or
            -not (Test-Path -LiteralPath $candidate -PathType Container) -or
            -not (Test-Path -LiteralPath (
                Join-Path $candidate 'spec.md'
            ) -PathType Leaf)) {
            throw "Feature must name a direct active tracker folder containing spec.md: $_"
        }
        $true
    })]
    [string]
    $Feature
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NativeText {
    param(
        [Parameter(Mandatory)]
        [string]
        $FilePath,

        [Parameter()]
        [string[]]
        $ArgumentList = @()
    )

    $output = & $FilePath @ArgumentList 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "'$FilePath' failed with exit code $LASTEXITCODE.$([Environment]::NewLine)$message"
    }

    return ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
}

function Invoke-Agent {
    param(
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [string]
        $CommandPath,

        [Parameter(Mandatory)]
        [string]
        $Prompt,

        [Parameter()]
        [int]
        $FrameInnerWidth = 0
    )

    $arguments = switch ($Name) {
        'codex' {
            @(
                'exec',
                '--model', "$model",
                '--config', "model_reasoning_effort=`"$effort`"",
                '--sandbox', 'workspace-write',
                $Prompt
            )
        }
        'copilot' {
            @('-p', $Prompt, '--model', "$model", '-s', '--allow-tool=read,write,shell')
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    & $CommandPath @arguments 2>&1 |
        ForEach-Object {
            if ($FrameInnerWidth -gt 0) {
                Write-AgentOutputRow -Content $_.ToString() -InnerWidth $FrameInnerWidth
            }
            else {
                Write-Host $_
            }
            $_
        } |
        ForEach-Object {
            $lines.Add($_.ToString())
        }

    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }

    return $lines -join [Environment]::NewLine
}

function Get-NewProgressEntry {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Before,

        [Parameter(Mandatory)]
        [string]
        $After
    )

    if (-not $After.StartsWith($Before, [System.StringComparison]::Ordinal)) {
        throw 'The iteration must only append to .scratch/progress.jsonl.'
    }

    if ($Before.Length -gt 0 -and -not $Before.EndsWith(
        "`n",
        [System.StringComparison]::Ordinal
    )) {
        throw '.scratch/progress.jsonl must end with a newline before appending a record.'
    }

    $appendedContent = $After.Substring($Before.Length)
    $lines = @($appendedContent -split '\r?\n' | Where-Object { $_.Length -gt 0 })
    if ($lines.Count -ne 1) {
        throw 'The iteration must append exactly one JSONL record to .scratch/progress.jsonl.'
    }

    try {
        $entry = $lines[0] | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The appended progress record is not valid JSON: $($_.Exception.Message)"
    }

    $properties = @($entry.PSObject.Properties.Name)
    foreach ($required in 'feature', 'ticket', 'changes', 'checks') {
        if ($properties -cnotcontains $required -or
            $entry.$required -isnot [string] -or
            [string]::IsNullOrWhiteSpace($entry.$required)) {
            throw "The appended progress record requires a non-empty string '$required' field."
        }
    }

    return $entry
}

function Complete-TrackerTicket {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [psobject]
        $ProgressEntry
    )

    if ($ProgressEntry.feature -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Unsafe feature slug in progress record: '$($ProgressEntry.feature)'."
    }
    if ($ProgressEntry.ticket -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*$') {
        throw "Unsafe ticket id in progress record: '$($ProgressEntry.ticket)'."
    }

    $issuesDirectory = Join-Path (
        Join-Path $ScratchDirectory $ProgressEntry.feature
    ) 'issues'
    if (-not (Test-Path -LiteralPath $issuesDirectory -PathType Container)) {
        throw "Active feature issues directory not found: $issuesDirectory"
    }

    $ticketName = $ProgressEntry.ticket
    if ($ticketName.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
        $ticketName = $ticketName.Substring(0, $ticketName.Length - 3)
    }
    if ($ticketName.EndsWith('.done', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Ticket is already completed: $($ProgressEntry.ticket)"
    }

    $source = Join-Path $issuesDirectory "$ticketName.md"
    $destination = Join-Path $issuesDirectory "$ticketName.done.md"
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        throw "Ticket is already completed: $($ProgressEntry.feature)/$ticketName"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Unfinished tracker ticket not found: $($ProgressEntry.feature)/$ticketName"
    }

    Move-Item -LiteralPath $source -Destination $destination
    return $ticketName
}

function Move-CompletedTrackerFeature {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [string]
        $Feature
    )

    $featureDirectory = Join-Path $ScratchDirectory $Feature
    $issuesDirectory = Join-Path $featureDirectory 'issues'
    $unfinishedTickets = @(
        Get-ChildItem -LiteralPath $issuesDirectory -File -Filter '*.md' |
            Where-Object {
                -not $_.Name.EndsWith(
                    '.done.md',
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    if ($unfinishedTickets.Count -gt 0) {
        return $null
    }

    $doneDirectory = Join-Path $ScratchDirectory 'done'
    if (-not (Test-Path -LiteralPath $doneDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $doneDirectory | Out-Null
    }

    $archiveName = $Feature
    $suffix = 2
    while (Test-Path -LiteralPath (
        Join-Path $doneDirectory $archiveName
    )) {
        $archiveName = "$Feature-$suffix"
        $suffix++
    }

    $archivePath = Join-Path $doneDirectory $archiveName
    Move-Item -LiteralPath $featureDirectory -Destination $archivePath
    return $archivePath
}

function Get-UnfinishedTrackerTickets {
    param(
        [Parameter(Mandatory)]
        [string]
        $FeatureDirectory
    )

    $issuesDirectory = Join-Path $FeatureDirectory 'issues'
    if (-not (Test-Path -LiteralPath $issuesDirectory -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $issuesDirectory -File -Filter '*.md' |
            Where-Object {
                -not $_.Name.EndsWith(
                    '.done.md',
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
    )
}

function Get-ActiveTrackerFeatures {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory
    )

    return @(
        Get-ChildItem -LiteralPath $ScratchDirectory -Directory |
            Where-Object {
                $_.Name -cne 'done' -and
                @(
                    Get-UnfinishedTrackerTickets -FeatureDirectory $_.FullName
                ).Count -gt 0
            }
    )
}

function Get-MarkdownHeading {
    param(
        [Parameter(Mandatory)]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [string]
        $Fallback
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $Fallback
    }

    $match = [regex]::Match(
        [System.IO.File]::ReadAllText($Path),
        '(?m)^#\s+(.+?)\s*$'
    )
    if (-not $match.Success) {
        return $Fallback
    }

    return $match.Groups[1].Value
}

function Get-NaturalSortKey {
    param(
        [Parameter(Mandatory)]
        [string]
        $Value
    )

    return [regex]::Replace(
        $Value.ToLowerInvariant(),
        '\d+',
        { param($match) $match.Value.PadLeft(20, '0') }
    )
}

function Format-TrackerMetadataRow {
    param(
        [Parameter(Mandatory)]
        [string]
        $Label,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Value
    )

    $muted = $PSStyle.Foreground.BrightBlack
    $valueColor = $PSStyle.Foreground.BrightWhite
    $reset = $PSStyle.Reset
    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = '-'
    }

    return "${muted}${Label}:${reset} ${valueColor}${Value}${reset}"
}

function Format-TrackerHeaderRow {
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Repository = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $AgentSummary = '',

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $InnerWidth = 0
    )

    $repositoryText = Format-TrackerMetadataRow -Label 'Repository' -Value $Repository
    if ([string]::IsNullOrWhiteSpace($AgentSummary)) {
        return $repositoryText
    }

    $dimAgent = "`e[2;38;5;8m${AgentSummary}$($PSStyle.Reset)"
    $gap = 2
    if ($InnerWidth -gt 0) {
        $gap = [Math]::Max(
            2,
            $InnerWidth -
                (Get-DisplayCellWidth -Text $repositoryText) -
                (Get-DisplayCellWidth -Text $dimAgent)
        )
    }

    return "$repositoryText$(' ' * $gap)$dimAgent"
}

function Get-TrackerLines {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        # Feature directory names that were active at startup and must remain
        # visible after they complete and are archived.
        [Parameter()]
        [string[]]
        $RetainedFeatureNames = @(),

        # When set, render only these feature directory names. This keeps a
        # selected-feature workboard focused while allowing automatic runs to
        # continue showing every active feature.
        [Parameter()]
        [string[]]
        $DisplayFeatureNames = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Repository = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $AgentSummary = '',

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $InnerWidth = 0,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $CurrentIteration = 0,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $TotalIterations = 0,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $CompletedIterations = 0
    )

    $displayFeatureNameSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($displayFeatureName in $DisplayFeatureNames) {
        if (-not [string]::IsNullOrWhiteSpace($displayFeatureName)) {
            [void] $displayFeatureNameSet.Add($displayFeatureName)
        }
    }

    $activeFeatureNameSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $activeFeatures = @(
        Get-ChildItem -LiteralPath $ScratchDirectory -Directory |
            Where-Object {
                $_.Name -cne 'done' -and
                ($displayFeatureNameSet.Count -eq 0 -or
                    $displayFeatureNameSet.Contains($_.Name))
            } |
            ForEach-Object {
                [void] $activeFeatureNameSet.Add($_.Name)
                $_
            } |
            Sort-Object { $_.Name.ToLowerInvariant() }
    )

    # Find retained features that have since been archived into done/.
    $doneDirectory = Join-Path $ScratchDirectory 'done'
    $displayEntries = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($f in $activeFeatures) {
        $displayEntries.Add([pscustomobject]@{
            Directory   = $f
            DisplayName = $f.Name
            IsRetained  = $false
        })
    }
    foreach ($retainedName in $RetainedFeatureNames) {
        if ($activeFeatureNameSet.Contains($retainedName)) { continue }
        if (-not (Test-Path -LiteralPath $doneDirectory -PathType Container)) { continue }
        $archivedDir = @(
            Get-ChildItem -LiteralPath $doneDirectory -Directory |
                Where-Object {
                    $_.Name -ceq $retainedName -or
                    $_.Name -cmatch ('^' + [regex]::Escape($retainedName) + '-\d+$')
                } |
                Sort-Object Name
        ) | Select-Object -First 1
        if ($archivedDir) {
            $displayEntries.Add([pscustomobject]@{
                Directory   = $archivedDir
                DisplayName = $retainedName
                IsRetained  = $true
            })
        }
    }
    $features = @($displayEntries | Sort-Object { $_.DisplayName.ToLowerInvariant() })

    $featureRows = [System.Collections.Generic.List[object]]::new()
    $unfinishedCount = 0
    foreach ($entry in $features) {
        $featureDir = $entry.Directory
        $issuesDirectory = Join-Path $featureDir.FullName 'issues'
        $tickets = @(
            if (Test-Path -LiteralPath $issuesDirectory -PathType Container) {
                Get-ChildItem -LiteralPath $issuesDirectory -File -Filter '*.md' |
                    ForEach-Object {
                        $completed = $entry.IsRetained -or $_.Name.EndsWith(
                            '.done.md',
                            [System.StringComparison]::OrdinalIgnoreCase
                        )
                        [pscustomobject]@{
                            File      = $_
                            Completed = $completed
                            SortKey   = Get-NaturalSortKey -Value $_.Name
                        }
                    } |
                    Sort-Object SortKey
            }
        )
        $unfinishedCount += @($tickets | Where-Object { -not $_.Completed }).Count
        $featureRows.Add([pscustomobject]@{
            Directory = $featureDir
            Heading   = Get-MarkdownHeading `
                -Path (Join-Path $featureDir.FullName 'spec.md') `
                -Fallback $entry.DisplayName
            Tickets   = $tickets
        })
    }

    $accent  = $PSStyle.Foreground.BrightCyan
    $muted   = $PSStyle.Foreground.BrightBlack
    $success = $PSStyle.Foreground.BrightGreen
    $reset   = $PSStyle.Reset

    $cappedTotal = if ($TotalIterations -gt 0 -and $CurrentIteration -gt 0) {
        [Math]::Min($TotalIterations, $CompletedIterations + $unfinishedCount)
    } else { 0 }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add((Format-TrackerHeaderRow -Repository $Repository `
        -AgentSummary $AgentSummary -InnerWidth $InnerWidth))
    $iterationValue = if ($cappedTotal -gt 0) {
        "$CurrentIteration of $cappedTotal"
    } else { '' }
    $lines.Add((Format-TrackerMetadataRow -Label 'Iteration' -Value $iterationValue))

    if ($features.Count -eq 0) {
        $lines.Add('')
        $lines.Add("${muted}No active features.${reset}")
        return $lines
    }

    foreach ($featureRow in $featureRows) {
        $lines.Add('')
        $lines.Add(
            "${accent}$($featureRow.Heading)${reset} " +
            "${muted}($($featureRow.Directory.Name))${reset}"
        )
        if ($featureRow.Tickets.Count -eq 0) {
            $lines.Add("${muted}└─ no tickets${reset}")
            continue
        }

        for ($index = 0; $index -lt $featureRow.Tickets.Count; $index++) {
            $ticket   = $featureRow.Tickets[$index]
            $branch   = if ($index -eq $featureRow.Tickets.Count - 1) { '└─' } else { '├─' }
            $ticketId = $ticket.File.BaseName
            if ($ticketId.EndsWith('.done', [System.StringComparison]::OrdinalIgnoreCase)) {
                $ticketId = $ticketId.Substring(0, $ticketId.Length - 5)
            }
            $heading = Get-MarkdownHeading `
                -Path $ticket.File.FullName `
                -Fallback $ticketId
            if ($ticket.Completed) {
                $lines.Add("${muted}$branch [✓] $heading${reset}")
            }
            else {
                $lines.Add("$branch ${success}[ ]${reset} $heading")
            }
        }
    }

    return $lines
}

function Format-PanelTopBorder {
    param(
        [Parameter(Mandatory)]
        [string]
        $Label,

        [Parameter(Mandatory)]
        [int]
        $Width
    )

    if ($Width -lt 2) { $Width = 2 }

    # Intensity alone inherits the current foreground colour. Select grey
    # explicitly so a coloured label cannot bleed into either frame border.
    $frame  = "`e[2;38;5;8m"
    $accent = $PSStyle.Foreground.BrightCyan
    $reset  = $PSStyle.Reset

    # Top border: ╭─ <label> ─...─╮  (total printable width = $Width)
    # Structure: ╭─(2) + space(1) + label + space(1) + fill + ╮(1)
    $fillLen = [Math]::Max(0, $Width - 4 - $Label.Length - 1)
    return "${frame}╭─ ${accent}${Label}${frame} $('─' * $fillLen)╮${reset}"
}

function Format-PanelBottomBorder {
    param(
        [Parameter(Mandatory)]
        [int]
        $Width
    )

    if ($Width -lt 2) { $Width = 2 }

    $frame = "`e[2;38;5;8m"
    $reset = $PSStyle.Reset
    return "${frame}╰$('─' * ($Width - 2))╯${reset}"
}

function Get-AgentOutputBlankRow {
    param(
        [Parameter(Mandatory)]
        [int]
        $InnerWidth
    )

    $frame = "`e[2;38;5;8m"
    $reset = $PSStyle.Reset
    return "${frame}│${reset}$(' ' * ($InnerWidth + 2))${frame}│${reset}"
}

function Get-DisplayCellWidth {
    param(
        [Parameter()]
        [AllowNull()]
        [string]
        $Text
    )

    if ($null -eq $Text -or $Text.Length -eq 0) { return 0 }

    $width = 0
    $index = 0
    while ($index -lt $Text.Length) {
        if (
            $Text[$index] -eq [char]27 -and
            ($index + 1) -lt $Text.Length -and
            $Text[$index + 1] -eq '['
        ) {
            $sequenceEnd = $index + 2
            while ($sequenceEnd -lt $Text.Length) {
                $value = [int][char]$Text[$sequenceEnd]
                if ($value -ge 0x40 -and $value -le 0x7E) { break }
                $sequenceEnd++
            }
            if ($sequenceEnd -lt $Text.Length) {
                $index = $sequenceEnd + 1
                continue
            }
        }

        $codePoint = [char]::ConvertToUtf32($Text, $index)
        $charLen = if ($codePoint -gt 0xFFFF) { 2 } else { 1 }
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($Text, $index)
        $cellWidth = switch ($category) {
            ([System.Globalization.UnicodeCategory]::Control) { 0; break }
            ([System.Globalization.UnicodeCategory]::NonSpacingMark) { 0; break }
            ([System.Globalization.UnicodeCategory]::SpacingCombiningMark) { 0; break }
            ([System.Globalization.UnicodeCategory]::EnclosingMark) { 0; break }
            default {
                if (
                    $codePoint -eq 0x200D -or
                    ($codePoint -ge 0xFE00 -and $codePoint -le 0xFE0F)
                ) {
                    0
                }
                elseif (
                    ($codePoint -ge 0x1100 -and $codePoint -le 0x115F) -or
                    ($codePoint -ge 0x2329 -and $codePoint -le 0x232A) -or
                    ($codePoint -ge 0x2E80 -and $codePoint -le 0xA4CF) -or
                    ($codePoint -ge 0xAC00 -and $codePoint -le 0xD7A3) -or
                    ($codePoint -ge 0xF900 -and $codePoint -le 0xFAFF) -or
                    ($codePoint -ge 0xFE10 -and $codePoint -le 0xFE19) -or
                    ($codePoint -ge 0xFE30 -and $codePoint -le 0xFE6F) -or
                    ($codePoint -ge 0xFF00 -and $codePoint -le 0xFF60) -or
                    ($codePoint -ge 0xFFE0 -and $codePoint -le 0xFFE6) -or
                    ($codePoint -ge 0x1F300 -and $codePoint -le 0x1FAFF) -or
                    ($codePoint -ge 0x20000 -and $codePoint -le 0x3FFFD)
                ) {
                    2
                }
                else {
                    1
                }
            }
        }

        $width += $cellWidth
        $index += $charLen
    }

    return $width
}

function Split-AgentOutputContent {
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Content = '',

        [Parameter(Mandatory)]
        [int]
        $InnerWidth
    )

    if ($InnerWidth -lt 0) { $InnerWidth = 0 }
    if ($null -eq $Content) { $Content = '' }

    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    $builder = [System.Text.StringBuilder]::new()
    $rowWidth = 0
    $index = 0
    while ($index -lt $Content.Length) {
        if (
            $Content[$index] -eq [char]27 -and
            ($index + 1) -lt $Content.Length -and
            $Content[$index + 1] -eq '['
        ) {
            $sequenceEnd = $index + 2
            while ($sequenceEnd -lt $Content.Length) {
                $value = [int][char]$Content[$sequenceEnd]
                if ($value -ge 0x40 -and $value -le 0x7E) { break }
                $sequenceEnd++
            }
            if ($sequenceEnd -lt $Content.Length) {
                [void]$builder.Append($Content.Substring($index, $sequenceEnd - $index + 1))
                $index = $sequenceEnd + 1
                continue
            }
        }

        $codePoint = [char]::ConvertToUtf32($Content, $index)
        $charLen = if ($codePoint -gt 0xFFFF) { 2 } else { 1 }
        $textElement = $Content.Substring($index, $charLen)
        $elementWidth = Get-DisplayCellWidth -Text $textElement
        if (
            $InnerWidth -gt 0 -and
            $elementWidth -gt 0 -and
            $rowWidth -gt 0 -and
            ($rowWidth + $elementWidth -gt $InnerWidth)
        ) {
            $rows.Add([pscustomobject]@{
                    Text  = $builder.ToString()
                    Width = $rowWidth
                })
            $builder.Clear() | Out-Null
            $rowWidth = 0
        }

        [void]$builder.Append($textElement)
        $rowWidth += $elementWidth
        $index += $charLen
    }

    if ($builder.Length -gt 0 -or $rows.Count -eq 0) {
        $rows.Add([pscustomobject]@{
                Text  = $builder.ToString()
                Width = $rowWidth
            })
    }

    return @($rows)
}

function Write-AgentOutputRow {
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Content = '',

        [Parameter(Mandatory)]
        [int]
        $InnerWidth
    )

    $frame = "`e[2;38;5;8m"
    $reset = $PSStyle.Reset
    $rows = Split-AgentOutputContent -Content $Content -InnerWidth $InnerWidth
    foreach ($row in $rows) {
        $pad = ' ' * [Math]::Max(0, $InnerWidth - [int]$row.Width)
        [Console]::WriteLine("${frame}│${reset} $($row.Text)$pad ${frame}│${reset}")
    }
}

function Compact-AgentOutputPanel {
    param(
        [Parameter(Mandatory)]
        [hashtable]
        $State
    )

    $oldBottomRow = if ($State.ContainsKey('BottomRow')) { [int]$State.BottomRow } else { 0 }
    if ($oldBottomRow -le 0) { return }

    $windowWidth = try { [Console]::WindowWidth } catch { 0 }
    if ($windowWidth -lt 1) {
        $windowWidth = [Math]::Max(2, (4 + [int]$State.InnerWidth))
    }
    $windowHeight = try { [Console]::WindowHeight } catch { 0 }
    if ($windowHeight -lt 1) {
        $windowHeight = if ($State.ContainsKey('WindowHeight')) {
            [int]$State.WindowHeight
        }
        else {
            $oldBottomRow
        }
    }

    $newBottomRow = try { [Console]::CursorTop + 1 } catch { $oldBottomRow }
    if ($newBottomRow -lt 1) { $newBottomRow = $oldBottomRow }
    $newBottomRow = [Math]::Min($windowHeight, $newBottomRow)

    if ($oldBottomRow -gt $newBottomRow) {
        $blankLine = ' ' * $windowWidth
        for ($row = $newBottomRow; $row -le $oldBottomRow; $row++) {
            [Console]::Write("`e[${row};1H$blankLine")
        }
    }

    [Console]::Write("`e[${newBottomRow};1H")
    [Console]::Write((Format-PanelBottomBorder -Width $windowWidth))
    $State.BottomRow = $newBottomRow
}

function Get-AgentOutputPanelLayout {
    param(
        [Parameter(Mandatory)]
        [int]
        $TrackerPanelHeight,

        [Parameter(Mandatory)]
        [int]
        $WindowWidth,

        [Parameter(Mandatory)]
        [int]
        $WindowHeight
    )

    if ($WindowWidth -lt 1) { $WindowWidth = 120 }
    if ($WindowHeight -lt 1) { $WindowHeight = 24 }

    $messageTop = [Math]::Min(
        [Math]::Max(1, $TrackerPanelHeight + 2),
        $WindowHeight
    )
    $messageBottom = [Math]::Max($messageTop, $WindowHeight - 1)
    $topRow = [Math]::Max(1, $messageTop - 1)
    $bottomRow = [Math]::Min($WindowHeight, $messageBottom + 1)

    return @{
        TopRow      = $topRow
        BottomRow   = $bottomRow
        MessageTop  = $messageTop
        MessageBottom = $messageBottom
        InnerWidth  = [Math]::Max(0, $WindowWidth - 4)
        TopBorder   = Format-PanelTopBorder -Label 'Agent output' -Width $WindowWidth
        BottomBorder = Format-PanelBottomBorder -Width $WindowWidth
    }
}

function Format-TrackerPanel {
    param(
        [string[]]
        $TrackerLines,

        [Parameter(Mandatory)]
        [int]
        $Width
    )

    if ($Width -lt 2) { $Width = 2 }
    $frame       = "`e[2;38;5;8m"
    $reset       = $PSStyle.Reset
    $topBorder   = Format-PanelTopBorder -Label 'Ralph tracker' -Width $Width
    $bottomBorder = Format-PanelBottomBorder -Width $Width

    # Inner content area width: Width - │(1) - space(1) - space(1) - │(1) = Width - 4
    $innerWidth = [Math]::Max(0, $Width - 4)

    $result = [System.Collections.Generic.List[string]]::new()
    $result.Add($topBorder)
    foreach ($line in $TrackerLines) {
        # Strip ANSI sequences to calculate visible length for right-padding.
        $visible  = $line -replace "`e\[[^m]*m", ''
        $padCount = [Math]::Max(0, $innerWidth - $visible.Length)
        $result.Add("${frame}│${reset} ${line}$(' ' * $padCount) ${frame}│${reset}")
    }
    $result.Add($bottomBorder)

    return $result
}

function Show-RalphTracker {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory
    )

    foreach ($line in Get-TrackerLines -ScratchDirectory $ScratchDirectory) {
        Write-Host $line
    }
}

function Enter-RalphWorkboard {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [string]
        $Repository,

        [Parameter(Mandatory)]
        [string]
        $AgentSummary,

        [Parameter(Mandatory)]
        [int]
        $CurrentIteration,

        [Parameter(Mandatory)]
        [int]
        $TotalIterations,

        [Parameter()]
        [string[]]
        $DisplayFeatureNames = @()
    )

    $displayFeatureNameSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($displayFeatureName in $DisplayFeatureNames) {
        if (-not [string]::IsNullOrWhiteSpace($displayFeatureName)) {
            [void] $displayFeatureNameSet.Add($displayFeatureName)
        }
    }
    $normalizedDisplayFeatureNames = @($displayFeatureNameSet)

    # Snapshot active features at startup so they can be retained after archival.
    $startupFeatureNames = @(
        Get-ActiveTrackerFeatures -ScratchDirectory $ScratchDirectory |
            Where-Object {
                $displayFeatureNameSet.Count -eq 0 -or
                $displayFeatureNameSet.Contains($_.Name)
            } |
            ForEach-Object { $_.Name }
    )

    $windowWidth   = try { [Console]::WindowWidth } catch { 0 }
    if ($windowWidth -lt 1) { $windowWidth = 120 }
    $lines         = Get-TrackerLines `
        -ScratchDirectory $ScratchDirectory `
        -DisplayFeatureNames $normalizedDisplayFeatureNames `
        -Repository $Repository `
        -AgentSummary $AgentSummary `
        -InnerWidth ([Math]::Max(0, $windowWidth - 4)) `
        -CurrentIteration $CurrentIteration `
        -TotalIterations $TotalIterations
    $trackerHeight = $lines.Count
    $windowHeight  = try { [Console]::WindowHeight } catch { 0 }
    if ($windowHeight -lt 1) { $windowHeight = 24 }

    $panelLines   = Format-TrackerPanel -TrackerLines $lines -Width $windowWidth
    $panelHeight  = $panelLines.Count  # trackerHeight + 2 borders
    $outputLayout = Get-AgentOutputPanelLayout `
        -TrackerPanelHeight $panelHeight `
        -WindowWidth $windowWidth `
        -WindowHeight $windowHeight

    # Hide the cursor for the duration of the interactive workboard.
    [Console]::Write("`e[?25l")
    # Clear the screen and draw the tracker panel at the top.
    [Console]::Write("`e[2J`e[1;1H")
    foreach ($panelLine in $panelLines) {
        [Console]::WriteLine($panelLine)
    }
    [Console]::Write("`e[$($outputLayout.TopRow);1H")
    [Console]::WriteLine($outputLayout.TopBorder)
    # Draw blank rows explicitly before establishing the scroll region. Without
    # these rows, vertical frame edges appear only after the agent emits output.
    $blankOutputRow = Get-AgentOutputBlankRow -InnerWidth $outputLayout.InnerWidth
    for ($row = $outputLayout.MessageTop; $row -le $outputLayout.MessageBottom; $row++) {
        [Console]::Write("`e[${row};1H$blankOutputRow")
    }
    [Console]::Write("`e[$($outputLayout.BottomRow);1H")
    [Console]::Write($outputLayout.BottomBorder)

    # Confine scrolling to the agent-output region between fixed borders.
    [Console]::Write(
        "`e[$($outputLayout.MessageTop);$($outputLayout.MessageBottom)r"
    )
    [Console]::Write("`e[$($outputLayout.MessageTop);1H")

    return @{
        Height               = $trackerHeight
        ScrollTop            = $outputLayout.MessageTop
        BottomRow            = $outputLayout.BottomRow
        InnerWidth           = $outputLayout.InnerWidth
        WindowHeight         = $windowHeight
        RetainedFeatureNames = $startupFeatureNames
        DisplayFeatureNames  = $normalizedDisplayFeatureNames
        Repository           = $Repository
        AgentSummary         = $AgentSummary
        CurrentIteration     = $CurrentIteration
        TotalIterations      = $TotalIterations
        CompletedIterations  = 0
    }
}

function Update-RalphWorkboard {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory,

        [Parameter(Mandatory)]
        [hashtable]
        $State
    )

    $retainedNames = if ($State.ContainsKey('RetainedFeatureNames')) {
        $State.RetainedFeatureNames
    }
    else {
        @()
    }
    $displayNames = if ($State.ContainsKey('DisplayFeatureNames')) {
        $State.DisplayFeatureNames
    }
    else {
        @()
    }
    $repository = if ($State.ContainsKey('Repository')) {
        [string] $State.Repository
    }
    else {
        ''
    }
    $agentSummary = if ($State.ContainsKey('AgentSummary')) {
        [string] $State.AgentSummary
    }
    else {
        ''
    }
    $currentIteration = if ($State.ContainsKey('CurrentIteration')) {
        [int] $State.CurrentIteration
    }
    else {
        0
    }
    $totalIterations = if ($State.ContainsKey('TotalIterations')) {
        [int] $State.TotalIterations
    }
    else {
        0
    }
    $completedIterations = if ($State.ContainsKey('CompletedIterations')) {
        [int] $State.CompletedIterations
    }
    else {
        0
    }
    $lineWidth = try { [Console]::WindowWidth } catch { 0 }
    if ($lineWidth -lt 1) { $lineWidth = 120 }
    $lines = Get-TrackerLines -ScratchDirectory $ScratchDirectory `
        -RetainedFeatureNames $retainedNames `
        -DisplayFeatureNames $displayNames `
        -Repository $repository `
        -AgentSummary $agentSummary `
        -InnerWidth ([Math]::Max(0, $lineWidth - 4)) `
        -CurrentIteration $currentIteration `
        -TotalIterations $totalIterations `
        -CompletedIterations $completedIterations
    $trackerHeight = $lines.Count
    $currentHeight = if ($State.ContainsKey('Height')) { [int]$State.Height } else { 0 }

    $panelLines  = Format-TrackerPanel -TrackerLines $lines -Width $lineWidth
    $panelHeight = $panelLines.Count  # trackerHeight + 2 borders

    if ($trackerHeight -ne $currentHeight) {
        # Tracker-height changes must reposition both adjacent panels and recreate
        # the message scroll region so borders and content remain coherent.
        $windowHeight = try { [Console]::WindowHeight } catch { 0 }
        if ($windowHeight -lt 1) {
            if ($State.ContainsKey('WindowHeight')) {
                $windowHeight = [int]$State.WindowHeight
            }
            else {
                $windowHeight = 24
            }
        }
        $outputLayout = Get-AgentOutputPanelLayout `
            -TrackerPanelHeight $panelHeight `
            -WindowWidth $lineWidth `
            -WindowHeight $windowHeight

        [Console]::Write("`e[2J`e[1;1H")
        foreach ($panelLine in $panelLines) {
            [Console]::WriteLine($panelLine)
        }
        [Console]::Write("`e[$($outputLayout.TopRow);1H")
        [Console]::WriteLine($outputLayout.TopBorder)
        $blankOutputRow = Get-AgentOutputBlankRow -InnerWidth $outputLayout.InnerWidth
        for ($row = $outputLayout.MessageTop; $row -le $outputLayout.MessageBottom; $row++) {
            [Console]::Write("`e[${row};1H$blankOutputRow")
        }
        [Console]::Write("`e[$($outputLayout.BottomRow);1H")
        [Console]::Write($outputLayout.BottomBorder)
        [Console]::Write(
            "`e[$($outputLayout.MessageTop);$($outputLayout.MessageBottom)r"
        )
        [Console]::Write("`e[$($outputLayout.MessageTop);1H")

        $State.Height = $trackerHeight
        $State.ScrollTop = $outputLayout.MessageTop
        $State.BottomRow = $outputLayout.BottomRow
        $State.InnerWidth = $outputLayout.InnerWidth
        $State.WindowHeight = $windowHeight
        return $State
    }

    # Save the current scroll-region cursor position, redraw the panel, then restore.
    [Console]::Write("`e[s`e[1;1H")
    $blankLine       = ' ' * $lineWidth
    $oldPanelHeight  = $currentHeight + 2
    $rowsToRedraw    = [Math]::Max($oldPanelHeight, $panelHeight)
    for ($index = 0; $index -lt $rowsToRedraw; $index++) {
        if ($index -lt $panelHeight) {
            [Console]::WriteLine($panelLines[$index])
        }
        else {
            [Console]::WriteLine($blankLine)
        }
    }
    [Console]::Write("`e[u")

    return $State
}

function Exit-RalphWorkboard {
    param(
        [Parameter(Mandatory)]
        [hashtable]
        $State
    )

    # Restore the terminal's full-screen scrolling region.
    [Console]::Write("`e[r")
    # Position cursor at the bottom border row so the prompt appears below the frame.
    $bottomRow = if ($State.ContainsKey('BottomRow')) { [int]$State.BottomRow } else { 0 }
    if ($bottomRow -gt 0) {
        [Console]::Write("`e[${bottomRow};1H")
        [Console]::WriteLine()
    }
    # Make the cursor visible again after tearing down the interactive workboard.
    [Console]::Write("`e[?25h")
}

function Invoke-RalphCleanup {
    param(
        [Parameter(Mandatory)]
        [string]
        $ScratchDirectory
    )

    $doneDirectory = Join-Path $ScratchDirectory 'done'
    $archiveDirectories = @(
        if (Test-Path -LiteralPath $doneDirectory -PathType Container) {
            Get-ChildItem -LiteralPath $doneDirectory -Directory
        }
    )
    foreach ($archive in $archiveDirectories) {
        if ($archive.Name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            throw "Unsafe archived feature directory: '$($archive.Name)'."
        }
    }

    foreach ($archive in $archiveDirectories) {
        Remove-Item -LiteralPath $archive.FullName -Recurse -Force
    }

    if ($archiveDirectories.Count -eq 0) {
        Write-Host 'Cleanup complete: nothing to remove.'
    }
    else {
        $removed = @($archiveDirectories.Name) | Sort-Object
        Write-Host "Cleanup complete: removed $($removed -join ', ')."
    }
}

$git = Get-Command git -ErrorAction Stop

$repositoryRoot = Invoke-NativeText -FilePath $git.Source -ArgumentList @(
    'rev-parse',
    '--show-toplevel'
)
$repositoryRoot = $repositoryRoot.Trim()

if ([string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'Could not determine the Git repository root.'
}

Set-Location -LiteralPath $repositoryRoot

$scratchDirectory = Join-Path $repositoryRoot '.scratch'
if (-not (Test-Path -LiteralPath $scratchDirectory -PathType Container)) {
    throw "Local issue tracker directory not found: $scratchDirectory"
}

if ($List) {
    $incompatibleOptions = @(
        @('Cleanup', 'Agent', 'Iterations', 'Feature') |
            Where-Object { $PSBoundParameters.ContainsKey($_) }
    )
    if ($incompatibleOptions.Count -gt 0) {
        throw "-List cannot be combined with: $($incompatibleOptions -join ', ')."
    }

    Show-RalphTracker -ScratchDirectory $scratchDirectory
    exit 0
}

$progressFile = Join-Path $scratchDirectory 'progress.jsonl'
if (-not (Test-Path -LiteralPath $progressFile -PathType Leaf)) {
    New-Item -ItemType File -Path $progressFile | Out-Null
}

if ($Cleanup) {
    $incompatibleOptions = @(
        @('Agent', 'Iterations', 'Feature') |
            Where-Object { $PSBoundParameters.ContainsKey($_) }
    )
    if ($incompatibleOptions.Count -gt 0) {
        throw "-Cleanup cannot be combined with: $($incompatibleOptions -join ', ')."
    }
    Invoke-RalphCleanup -ScratchDirectory $scratchDirectory
    exit 0
}

$agentCommand = Get-Command $Agent -ErrorAction Stop
$gitStatus = Invoke-NativeText -FilePath $git.Source -ArgumentList @(
    'status',
    '--porcelain'
)
if (-not [string]::IsNullOrWhiteSpace($gitStatus)) {
    throw 'The Git working tree is not clean. Commit or stash all changes before running Invoke-Ralph.'
}

$scopeKind = 'automatic'
$scopeFeature = $null
$scopeInstruction = if ($PSBoundParameters.ContainsKey('Feature')) {
    $scopeFeature = $Feature
    $scopeKind = 'feature'
    $specPath = [System.IO.Path]::GetRelativePath(
        $repositoryRoot,
        (Join-Path (Join-Path $scratchDirectory $Feature) 'spec.md')
    )

    @"
Work only on the selected feature '$Feature', whose specification is '$specPath'.
Complete successive unfinished tickets for that feature until it archives.
Ralph determines completion from the resulting tracker state.
"@
}
else {
    $issueDirectories = @(
        Get-ActiveTrackerFeatures -ScratchDirectory $scratchDirectory |
            ForEach-Object {
                [System.IO.Path]::GetRelativePath(
                    $repositoryRoot,
                    (Join-Path $_.FullName 'issues')
                )
            }
    )

    if ($issueDirectories.Count -eq 0) {
        Write-Host 'Requested scope complete.'
        exit 0
    }

    $issueDirectoryList = $issueDirectories -join [Environment]::NewLine
    @"
Choose the highest-priority unfinished feature from these local issue directories:
$issueDirectoryList

Use the specs, tickets, dependencies, and tracker filenames to decide priority.
If a feature was started in an earlier iteration, continue it until it is complete
before selecting another feature.
"@
}

$prompt = @"
You are implementing work in the Git repository at '$repositoryRoot'.

$scopeInstruction

For this iteration:
1. Read the relevant spec, every ticket for the selected feature, repository
   instructions, and .scratch/progress.jsonl.
2. Select exactly one unblocked ticket that is not already recorded as completed.
3. Implement only that ticket as an end-to-end, verifiable slice.
4. Determine and run the repository's relevant tests, type checks, linters, or
   build checks. Do not claim completion if a relevant check fails.
5. Append exactly one JSON object on one line to .scratch/progress.jsonl with
   non-empty string fields "feature", "ticket", "changes", and "checks".
6. Leave ticket renaming, staging, and committing to Ralph after success.

Do not work on more than one ticket in this iteration. Do not modify ticket or spec
files merely to track status. Do not rename tickets or stage,
commit, push, rewrite history, reset, clean, discard unrelated work, use destructive
Git commands, or change anything outside this repository.

If the entire requested scope was already complete at the start, do not invent work
or request an empty commit.
"@

$isInteractive = (
    -not [Console]::IsOutputRedirected -and
    $host.Name -ceq 'ConsoleHost'
)
if ($env:RALPH_FORCE_INTERACTIVE -eq '1') { $isInteractive = $true }

$model = if ($Agent -ceq 'codex') { 'gpt-5.6-sol' } else { 'auto' }
$effort = if ($Agent -ceq 'codex') { 'low' } else { '' }
$agentSummary = "$Agent / $model$(if ($effort) { " ($effort)" } else { '' })"

$workboardState = $null
$compactOutputPanelOnExit = $false
if ($isInteractive) {
    $workboardParameters = @{
        ScratchDirectory = $scratchDirectory
        Repository       = $repositoryRoot
        AgentSummary      = $agentSummary
        CurrentIteration  = 1
        TotalIterations   = $Iterations
    }
    if ($scopeKind -eq 'feature') {
        $workboardParameters.DisplayFeatureNames = @($scopeFeature)
    }
    $workboardState = Enter-RalphWorkboard @workboardParameters
}

try {

if (-not $workboardState) {
    Write-Host "Repository: $repositoryRoot"
    Write-Host "Agent: $agentSummary"
}

for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    if ($workboardState -and $workboardState.CurrentIteration -ne $iteration) {
        $workboardState.CurrentIteration = $iteration
        $workboardState = Update-RalphWorkboard `
            -ScratchDirectory $scratchDirectory `
            -State $workboardState
    }

    if ($workboardState) {
        $frameWidth = [int]$workboardState.InnerWidth
        Write-AgentOutputRow -Content '' -InnerWidth $frameWidth
        Write-AgentOutputRow -Content "`e[2mIteration $iteration of $Iterations`e[0m" `
            -InnerWidth $frameWidth
        Write-AgentOutputRow `
            -Content "`e[2m$('─' * [Math]::Min(40, $frameWidth))`e[0m" `
            -InnerWidth $frameWidth
    }
    else {
        Write-Host ''
        Write-Host "Iteration $iteration of $Iterations"
        Write-Host ('-' * 40)
    }

    if ($scopeKind -eq 'automatic') {
        $currentIssueDirectories = @(
            Get-ActiveTrackerFeatures -ScratchDirectory $scratchDirectory |
                ForEach-Object {
                    [System.IO.Path]::GetRelativePath(
                        $repositoryRoot,
                        (Join-Path $_.FullName 'issues')
                    )
                }
        )
        if ($currentIssueDirectories.Count -eq 0) {
            if ($workboardState) {
                Write-AgentOutputRow -Content 'Requested scope complete.' `
                    -InnerWidth ([int]$workboardState.InnerWidth)
                $compactOutputPanelOnExit = $true
            }
            else {
                Write-Host 'Requested scope complete.'
            }
            exit 0
        }
        $currentScopeInstruction = @"
Choose the highest-priority unfinished feature from these local issue directories:
$($currentIssueDirectories -join [Environment]::NewLine)

Use the specs, tickets, dependencies, and tracker filenames to decide priority.
If a feature was started in an earlier iteration, continue it until it is complete
before selecting another feature.
"@
        $prompt = $prompt.Replace($scopeInstruction, $currentScopeInstruction)
        $scopeInstruction = $currentScopeInstruction
    }

    $progressBeforeIteration = [System.IO.File]::ReadAllText($progressFile)
    $frameWidth = if ($workboardState) { [int]$workboardState.InnerWidth } else { 0 }
    Invoke-Agent -Name $Agent -CommandPath $agentCommand.Source -Prompt $prompt `
        -FrameInnerWidth $frameWidth | Out-Null
    $progressAfterIteration = [System.IO.File]::ReadAllText($progressFile)
    $progressChanged = -not [string]::Equals(
        $progressBeforeIteration,
        $progressAfterIteration,
        [System.StringComparison]::Ordinal
    )
    $gitStatus = Invoke-NativeText -FilePath $git.Source -ArgumentList @(
        'status',
        '--porcelain',
        '--untracked-files=all'
    )
    $hasChanges = $progressChanged -or -not [string]::IsNullOrWhiteSpace($gitStatus)

    if (-not $hasChanges) {
        throw 'The agent completed successfully but produced no changes.'
    }

    if (-not $progressChanged) {
        throw 'The agent changed the repository without updating .scratch/progress.jsonl.'
    }

    $progressEntry = Get-NewProgressEntry `
        -Before $progressBeforeIteration `
        -After $progressAfterIteration
    if ($scopeKind -ne 'automatic' -and $progressEntry.feature -cne $scopeFeature) {
        throw "Progress record does not match requested feature '$scopeFeature'."
    }
    $completedTicket = Complete-TrackerTicket `
        -ScratchDirectory $scratchDirectory `
        -ProgressEntry $progressEntry
    $archivePath = Move-CompletedTrackerFeature `
        -ScratchDirectory $scratchDirectory `
        -Feature $progressEntry.feature
    $featureCompleted = $null -ne $archivePath
    $commitSubject = "ralph: $($progressEntry.feature)/$completedTicket"
    if ($featureCompleted) {
        $commitSubject += ', FEATURE completed'
    }

    Invoke-NativeText -FilePath $git.Source -ArgumentList @('add', '--all') | Out-Null
    $trackerStatePath = if ($featureCompleted) {
        $archivePath
    }
    else {
        Join-Path $scratchDirectory (
            "$($progressEntry.feature)\issues\$completedTicket.done.md"
        )
    }
    Invoke-NativeText -FilePath $git.Source -ArgumentList @(
        'add',
        '--force',
        '--',
        $progressFile,
        $trackerStatePath
    ) | Out-Null
    Invoke-NativeText -FilePath $git.Source -ArgumentList @(
        'commit',
        '--message',
        $commitSubject
    ) | Out-Null
    if ($workboardState) {
        $workboardState.CurrentIteration = $iteration
        $workboardState.CompletedIterations = [int]$workboardState.CompletedIterations + 1
        $workboardState = Update-RalphWorkboard `
            -ScratchDirectory $scratchDirectory `
            -State $workboardState
    }

    $scopeComplete = switch ($scopeKind) {
        'feature' { $featureCompleted }
        'automatic' {
            @(
                Get-ActiveTrackerFeatures -ScratchDirectory $scratchDirectory
            ).Count -eq 0
        }
    }
    if ($scopeComplete) {
        if ($workboardState) {
            Write-AgentOutputRow -Content 'Requested scope complete.' `
                -InnerWidth ([int]$workboardState.InnerWidth)
            $compactOutputPanelOnExit = $true
        }
        else {
            Write-Host 'Requested scope complete.'
        }
        exit 0
    }
}

if ($workboardState) {
    Write-AgentOutputRow -Content "Reached the iteration limit ($Iterations)." `
        -InnerWidth ([int]$workboardState.InnerWidth)
}
else {
    Write-Host "Reached the iteration limit ($Iterations)."
}
exit 0

} finally {
    if ($workboardState) {
        if ($compactOutputPanelOnExit) {
            Compact-AgentOutputPanel -State $workboardState
        }
        Exit-RalphWorkboard -State $workboardState
    }
}
