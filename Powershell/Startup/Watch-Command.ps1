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

$rawUI = $Host.UI.RawUI
$initialCursor = $rawUI.CursorPosition
$anchor = $null
$previousLineWidths = @()

while ($true) {
    $output = try {
        & $Command *>&1
    } catch {
        $_
    }

    $updatedAt = Get-Date -Format 'HH:mm:ss'
    $lines = @("[$updatedAt] every $intervalText | Ctrl+C to stop")
    if ($null -ne $output) {
        $lines += @($output | Out-String -Stream)
    }

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
        $lineCount = [Math]::Max($lines.Count, $previousLineWidths.Count)
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
            $column = if ($index -eq 0) { $anchor.X } else { 0 }

            $rawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(
                $column,
                $anchor.Y + $index
            )
            $Host.UI.Write($line.PadRight([Math]::Max($line.Length, $previousWidth)))
        }
    }

    $previousLineWidths = @($lines | ForEach-Object { ([string]$_).Length })
    Start-Sleep -Duration $interval
}
