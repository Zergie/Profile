<#
.SYNOPSIS
    Repeatedly runs a ScriptBlock in the terminal, refreshing its output in place.

.DESCRIPTION
    Watch-Command runs a ScriptBlock on a fixed interval and redraws its output in
    the same terminal area on each refresh.  The default mode captures all output
    streams, formats them as text, and redraws within the visible window.

    When -Color is specified, the ScriptBlock is invoked without capturing or
    reformatting any output.  All streams — including stdout, stderr, host, and
    native command output — pass directly to the active terminal.  The watcher
    renders a status header and repositions the cursor to the tracked output area
    before each refresh.  A shorter result removes only the stale rows left over
    from the preceding run.

    LIMITATION — Color mode (-Color):
    Commands that actively move the cursor, render progress bars, use alternate-
    screen buffers, or otherwise take ownership of the terminal layout are not
    supported in color mode.  Only ordinary line-oriented output with ANSI color
    sequences is supported.  Use Watch-Command without -Color for such commands.

.PARAMETER ScriptBlock
    The command to execute on each refresh.  Must contain at least one statement.

.PARAMETER Seconds
    Refresh interval in seconds.  Defaults to 0.5 s when no interval is given.

.PARAMETER Milliseconds
    Refresh interval in milliseconds.

.PARAMETER Duration
    Refresh interval as a TimeSpan.

.PARAMETER Color
    Run in color-preserving mode: the ScriptBlock is invoked directly, its output
    reaches the terminal without capture, and ANSI colors are preserved.
    Cursor-driven and full-screen commands are not supported in this mode.

.EXAMPLE
    Watch-Command { Get-Process | Select-Object -First 5 }

    Captures and redraws the first five processes every 500 ms.

.EXAMPLE
    Watch-Command -Color -Seconds 5 { gh workflow list }

    Monitors GitHub workflow status in color, refreshing every 5 seconds.
    Because gh CLI uses ANSI colors in its output, -Color preserves them.
#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(Mandatory,
               Position = 0)]
    [ValidateNotNull()]
    [ValidateScript({
        if ($_.Ast.EndBlock.Statements.Count -eq 0) {
            throw 'ScriptBlock must contain at least one statement.'
        }
        $true
    })]
    [scriptblock]
    $ScriptBlock,

    [Parameter(ParameterSetName = 'Seconds')]
    [ValidateRange(0, [double]::MaxValue)]
    [double]
    $Seconds,

    [Parameter(ParameterSetName = 'Milliseconds')]
    [Alias('ms')]
    [ValidateRange(0, [int]::MaxValue)]
    [int]
    $Milliseconds,

    [Parameter(ParameterSetName = 'Duration')]
    [Alias('ts')]
    [ValidateScript({
        if ($_ -lt [TimeSpan]::Zero) {
            throw 'Duration must not be negative.'
        }
        $true
    })]
    [TimeSpan]
    $Duration,

    [switch]
    $Color
)

function Limit-WatchLines {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]
        $Lines,

        [Parameter(Mandatory)]
        [int]
        $Width,

        [Parameter(Mandatory)]
        [int]
        $FirstLineOffset,

        [Parameter(Mandatory)]
        [int]
        $Height
    )

    $result = [System.Collections.Generic.List[string]]::new()
    $wasTruncated = $Lines.Count -gt $Height
    $lineCount = [Math]::Min($Lines.Count, $Height)

    for ($index = 0; $index -lt $lineCount; $index++) {
        $availableWidth = $Width - $(if ($index -eq 0) { $FirstLineOffset } else { 0 })
        # Leave the final column unused so writing a full line cannot wrap.
        $availableWidth = [Math]::Max(1, $availableWidth - 1)
        $line = [string]$Lines[$index]
        if ($line.Length -gt $availableWidth) {
            $line = $line.Substring(0, $availableWidth)
            $wasTruncated = $true
        }
        $result.Add($line)
    }

    if ($wasTruncated -and $Height -gt 0) {
        $indicatorIndex = [Math]::Max(0, $result.Count - 1)
        $indicatorOffset = if ($indicatorIndex -eq 0) { $FirstLineOffset } else { 0 }
        $indicatorWidth = [Math]::Max(1, $Width - $indicatorOffset - 1)
        $indicator = '[output truncated]'
        if ($indicator.Length -gt $indicatorWidth) {
            $indicator = $indicator.Substring(0, $indicatorWidth)
        }

        if ($result.Count -eq 0) {
            $result.Add($indicator)
        } else {
            $result[$indicatorIndex] = $indicator
        }
    }

    return $result.ToArray()
}

function Format-WatchColorHeader {
    param(
        [Parameter(Mandatory)] [string] $UpdatedAt,
        [Parameter(Mandatory)] [string] $IntervalText
    )
    $printable = "● WATCHING | $UpdatedAt | every $IntervalText | Ctrl+C to stop"
    $rule = '─' * $printable.Length
    return @(
        "`e[90m$rule`e[0m",
        "`e[97;1m● WATCHING`e[0m `e[90m| $UpdatedAt | every $IntervalText | Ctrl+C to stop`e[0m",
        "`e[90m$rule`e[0m"
    )
}

function Get-WatchVisibleLines {
    param(
        [Parameter(Mandatory)]
        $RawUi,

        [Parameter(Mandatory)]
        [System.Management.Automation.Host.Coordinates]
        $WindowPosition,

        [Parameter(Mandatory)]
        [System.Management.Automation.Host.Size]
        $WindowSize
    )

    $rectangle = [System.Management.Automation.Host.Rectangle]::new(
        $WindowPosition.X,
        $WindowPosition.Y,
        $WindowPosition.X + $WindowSize.Width - 1,
        $WindowPosition.Y + $WindowSize.Height - 1
    )
    $bufferCells = $RawUi.GetBufferContents($rectangle)
    $dim0 = $bufferCells.GetLength(0)
    $dim1 = $bufferCells.GetLength(1)
    $isColumnRow = $dim0 -eq $WindowSize.Width -and $dim1 -eq $WindowSize.Height
    $isRowColumn = $dim0 -eq $WindowSize.Height -and $dim1 -eq $WindowSize.Width
    if (-not $isColumnRow -and -not $isRowColumn) {
        throw "Unexpected buffer dimensions: $dim0 x $dim1 for window $($WindowSize.Width) x $($WindowSize.Height)."
    }

    $visibleLines = [string[]]::new($WindowSize.Height)
    for ($row = 0; $row -lt $WindowSize.Height; $row++) {
        $lineChars = [char[]]::new($WindowSize.Width)
        for ($column = 0; $column -lt $WindowSize.Width; $column++) {
            $cell = if ($isColumnRow) {
                $bufferCells[$column, $row]
            } else {
                $bufferCells[$row, $column]
            }
            $lineChars[$column] = [char]$cell.Character
        }
        $visibleLines[$row] = (-join $lineChars).TrimEnd()
    }

    return $visibleLines
}

function Resolve-WatchColorAnchor {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]
        $VisibleLines,

        [Parameter(Mandatory)]
        [int]
        $WindowLeft,

        [Parameter(Mandatory)]
        [int]
        $WindowTop,

        [Parameter(Mandatory)]
        [System.Management.Automation.Host.Coordinates]
        $ProposedAnchor
    )

    $markerPrefix = '● WATCHING'
    $windowBottom = $WindowTop + $VisibleLines.Count
    $markerRow = $ProposedAnchor.Y + 1

    if ($markerRow -ge $WindowTop -and $markerRow -lt $windowBottom) {
        $candidate = [string]$VisibleLines[$markerRow - $WindowTop]
        if ($candidate.StartsWith($markerPrefix, [System.StringComparison]::Ordinal)) {
            return $ProposedAnchor
        }
    }

    $searchStart = [Math]::Min($markerRow - 1, $windowBottom - 1)
    for ($row = $searchStart; $row -ge $WindowTop; $row--) {
        $candidate = [string]$VisibleLines[$row - $WindowTop]
        if ($candidate.StartsWith($markerPrefix, [System.StringComparison]::Ordinal)) {
            return [System.Management.Automation.Host.Coordinates]::new(
                $WindowLeft,
                [Math]::Max($WindowTop, $row - 1)
            )
        }
    }

    return [System.Management.Automation.Host.Coordinates]::new($WindowLeft, $WindowTop)
}

function Invoke-WatchCommandLifecycle {
    param(
        [Parameter(Mandatory)] [scriptblock] $ScriptBlock,
        [Parameter(Mandatory)] [TimeSpan] $Interval,
        [Parameter(Mandatory)] [string] $IntervalText,
        [switch] $Color,
        $RawUi = $Host.UI.RawUI,
        [scriptblock] $Write = { param($line) $Host.UI.Write($line) },
        [scriptblock] $WriteLine = { param($line) $Host.UI.WriteLine($line) },
        [scriptblock] $WriteErrorLine = { param($line) $Host.UI.WriteErrorLine($line) },
        [scriptblock] $Sleep = { param($duration) Start-Sleep -Duration $duration },
        [ValidateRange(0, [int]::MaxValue)] [int] $RefreshCount = 0
    )

    try {
        $rawUI = $RawUi
        $cursorSize = $rawUI.CursorSize
        $windowSize = $rawUI.WindowSize
        $initialCursor = $rawUI.CursorPosition
        $rawUI.CursorPosition = $initialCursor
        if ($windowSize.Width -lt 2 -or $windowSize.Height -lt 1) {
            throw 'The terminal window has no usable drawing area.'
        }
    } catch {
        throw "Watch-Command requires a terminal host with working RawUI cursor positioning. Run it in a PowerShell 7 console or Windows Terminal. $($_.Exception.Message)"
    }

    $anchor = $null
    $previousLineWidths = @()
    $renderedLineCount = 0
    $completedRefreshes = 0

    if ($Color) {
    $colorAnchor = $null
    $prevTotalLines = 0

    try {
        while ($RefreshCount -eq 0 -or $completedRefreshes -lt $RefreshCount) {
            $windowSize = $rawUI.WindowSize
            $windowPosition = $rawUI.WindowPosition
            if ($windowSize.Width -lt 2 -or $windowSize.Height -lt 1) {
                throw 'Watch-Command cannot draw because the terminal window has no usable area.'
            }
            $windowBottom = $windowPosition.Y + $windowSize.Height

            if ($null -ne $colorAnchor -and
                ($colorAnchor.Y -lt $windowPosition.Y -or $colorAnchor.Y -ge $windowBottom)) {
                $colorAnchor = [System.Management.Automation.Host.Coordinates]::new(
                    $windowPosition.X,
                    $windowPosition.Y
                )
                $prevTotalLines = 0
            }

            $updatedAt = Get-Date -Format 'HH:mm:ss'
            $headerLines = Format-WatchColorHeader -UpdatedAt $updatedAt -IntervalText $intervalText

            if ($null -eq $colorAnchor) {
                $colorAnchor = $rawUI.CursorPosition
                $rawUI.CursorSize = 0
                } else {
                $visibleLines = Get-WatchVisibleLines -RawUi $rawUI `
                    -WindowPosition $windowPosition `
                    -WindowSize $windowSize
                $colorAnchor = Resolve-WatchColorAnchor -VisibleLines $visibleLines `
                    -WindowLeft $windowPosition.X `
                    -WindowTop $windowPosition.Y `
                    -ProposedAnchor $colorAnchor
                $rawUI.CursorPosition = $colorAnchor
                }

            foreach ($line in $headerLines) {
                & $WriteLine $line
            }

            try {
                & $ScriptBlock
            } catch {
                & $WriteErrorLine $_
            }

            $curPos = $rawUI.CursorPosition
            $lastUsedRow = if ($curPos.X -gt 0) { $curPos.Y } else { $curPos.Y - 1 }
            $newTotalLines = [Math]::Max(3, $lastUsedRow - $colorAnchor.Y + 1)

            # Erase rows left over from a longer previous result.
            if ($prevTotalLines -gt $newTotalLines) {
                $windowSize = $rawUI.WindowSize
                $windowPosition = $rawUI.WindowPosition
                $windowBottom = $windowPosition.Y + $windowSize.Height
                for ($i = $newTotalLines; $i -lt $prevTotalLines; $i++) {
                    $row = $colorAnchor.Y + $i
                    if ($row -ge $windowBottom) { break }
                    $rawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(
                        $windowPosition.X,
                        $row
                    )
                    & $Write (' ' * [Math]::Max(1, $windowSize.Width - 1))
                }
            }
            $prevTotalLines = $newTotalLines

            $completedRefreshes++
            if ($RefreshCount -eq 0 -or $completedRefreshes -lt $RefreshCount) {
                & $Sleep $Interval
            }
        }
    } finally {
        if ($null -ne $colorAnchor -and $prevTotalLines -gt 0) {
            try {
                $windowSize = $rawUI.WindowSize
                $windowPosition = $rawUI.WindowPosition
                $windowBottom = $windowPosition.Y + $windowSize.Height
                $finalRow = [Math]::Min(
                    $colorAnchor.Y + $prevTotalLines,
                    $windowBottom - 1
                )
                $rawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(
                    $windowPosition.X,
                    [Math]::Max($windowPosition.Y, $finalRow)
                )
                if ($finalRow -eq $windowBottom - 1) {
                    & $WriteLine ''
                }
            } catch {
                # Cancellation cleanup is best effort; preserve the original exit.
            }
        }
        $rawUI.CursorSize = $cursorSize
    }
} else {
    try {
        while ($RefreshCount -eq 0 -or $completedRefreshes -lt $RefreshCount) {
        $output = try {
            & $ScriptBlock *>&1
        } catch {
            $_
        }

        $windowSize = $rawUI.WindowSize
        $windowPosition = $rawUI.WindowPosition
        if ($windowSize.Width -lt 2 -or $windowSize.Height -lt 1) {
            throw 'Watch-Command cannot draw because the terminal window has no usable area.'
        }
        $windowBottom = $windowPosition.Y + $windowSize.Height

        if ($null -ne $anchor -and
            ($anchor.Y -lt $windowPosition.Y -or $anchor.Y -ge $windowBottom)) {
            $anchor = [System.Management.Automation.Host.Coordinates]::new(
                [Math]::Max($windowPosition.X, $anchor.X),
                $windowPosition.Y
            )
            $previousLineWidths = @()
        }

        $updatedAt = Get-Date -Format 'HH:mm:ss'
        $unboundedLines = @("[$updatedAt] every $intervalText | Ctrl+C to stop")
        if ($null -ne $output) {
            $formatWidth = [Math]::Max(1, $windowSize.Width - 1)
            $unboundedLines += @($output | Out-String -Stream -Width $formatWidth)
        }

        $firstLineOffset = if ($null -eq $anchor) {
            [Math]::Max(0, $initialCursor.X - $windowPosition.X)
        } else {
            [Math]::Max(0, $anchor.X - $windowPosition.X)
        }
        $availableHeight = if ($null -eq $anchor) {
            $windowSize.Height
        } else {
            [Math]::Max(1, $windowBottom - $anchor.Y)
        }
        $lines = @(Limit-WatchLines -Lines $unboundedLines `
                -Width $windowSize.Width `
                -FirstLineOffset $firstLineOffset `
                -Height $availableHeight)

        if ($null -eq $anchor) {
            $rawUI.CursorPosition = $initialCursor
            $rawUI.CursorSize = 0
            foreach ($line in $lines) {
                & $WriteLine ([string]$line)
            }

            $cursorAfterFirstRender = $rawUI.CursorPosition
            $anchor = [System.Management.Automation.Host.Coordinates]::new(
                $initialCursor.X,
                [Math]::Max(0, $cursorAfterFirstRender.Y - $lines.Count)
            )
        } else {
            $lineCount = [Math]::Min(
                [Math]::Max($lines.Count, $previousLineWidths.Count),
                $availableHeight
            )
            for ($index = 0; $index -lt $lineCount; $index++) {
                $line = if ($index -lt $lines.Count) {
                    [string]$lines[$index]
                } else {
                    ''
                }
                $previousWidth = if ($index -lt $previousLineWidths.Count) {
                    $previousLineWidths[$index]
                } else {
                    0
                }
                $column = if ($index -eq 0) { $anchor.X } else { $windowPosition.X }
                $maximumWidth = [Math]::Max(
                    1,
                    $windowPosition.X + $windowSize.Width - $column - 1
                )
                $writeWidth = [Math]::Min(
                    [Math]::Max($line.Length, $previousWidth),
                    $maximumWidth
                )

                $rawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(
                    $column,
                    $anchor.Y + $index
                )
                & $Write ($line.PadRight($writeWidth))
            }
        }

        $previousLineWidths = @($lines | ForEach-Object { ([string]$_).Length })
        $renderedLineCount = $lines.Count
        $completedRefreshes++
        if ($RefreshCount -eq 0 -or $completedRefreshes -lt $RefreshCount) {
            & $Sleep $Interval
        }
    }
    } finally {
        if ($null -ne $anchor -and $renderedLineCount -gt 0) {
            try {
                $windowSize = $rawUI.WindowSize
                $windowPosition = $rawUI.WindowPosition
                $windowBottom = $windowPosition.Y + $windowSize.Height
                $finalRow = [Math]::Min(
                    $anchor.Y + $renderedLineCount,
                    $windowBottom - 1
                )
                $rawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(
                    $windowPosition.X,
                    [Math]::Max($windowPosition.Y, $finalRow)
                )
                if ($finalRow -eq $windowBottom - 1) {
                    & $WriteLine ''
                }
            } catch {
                # Cancellation cleanup is best effort; preserve the original exit.
            }
        }
        $rawUI.CursorSize = $cursorSize
    }
}
}

if (-not $script:WatchCommandImportOnly) {
    $interval = switch ($PSCmdlet.ParameterSetName) {
        'Seconds'      { [TimeSpan]::FromSeconds($Seconds) }
        'Milliseconds' { [TimeSpan]::FromMilliseconds($Milliseconds) }
        'Duration'     { $Duration }
        default        { [TimeSpan]::FromMilliseconds(500) }
    }
    $intervalText = if ($interval.TotalSeconds -ge 1) {
        '{0:g}' -f $interval
    } else {
        '{0:0.###} ms' -f $interval.TotalMilliseconds
    }
    Invoke-WatchCommandLifecycle -ScriptBlock $ScriptBlock -Interval $interval `
        -IntervalText $intervalText -Color:$Color
}
