[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(Mandatory,
               Position = 0)]
    [ValidateNotNull()]
    [ValidateScript({
        if ($_.Ast.EndBlock.Statements.Count -eq 0) {
            throw 'Command must contain at least one statement.'
        }
        $true
    })]
    [scriptblock]
    $Command,

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
    $Duration
)

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

try {
    $rawUI = $Host.UI.RawUI
    $windowSize = $rawUI.WindowSize
    $initialCursor = $rawUI.CursorPosition
    $rawUI.CursorPosition = $initialCursor
    if ($windowSize.Width -lt 2 -or $windowSize.Height -lt 1) {
        throw 'The terminal window has no usable drawing area.'
    }
} catch {
    throw "Watch-Command requires a terminal host with working RawUI cursor positioning. Run it in a PowerShell 7 console or Windows Terminal. $($_.Exception.Message)"
}

function Limit-WatchLines {
    param(
        [Parameter(Mandatory)]
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

$anchor = $null
$previousLineWidths = @()
$renderedLineCount = 0

try {
    while ($true) {
        $output = try {
            & $Command *>&1
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
            foreach ($line in $lines) {
                $Host.UI.WriteLine([string]$line)
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
                $Host.UI.Write($line.PadRight($writeWidth))
            }
        }

        $previousLineWidths = @($lines | ForEach-Object { ([string]$_).Length })
        $renderedLineCount = $lines.Count
        Start-Sleep -Duration $interval
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
                $Host.UI.WriteLine()
            }
        } catch {
            # Cancellation cleanup is best effort; preserve the original exit.
        }
    }
}
