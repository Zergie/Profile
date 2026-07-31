#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$watchScript = Join-Path $PSScriptRoot '..\Startup\Watch-Command.ps1'

function Assert-Equal {
    param($Expected, $Actual, [string] $Because)
    if ($Expected -cne $Actual) {
        throw "$Because`nExpected: <$Expected>`nActual:   <$Actual>"
    }
}

function Assert-True {
    param([bool] $Condition, [string] $Because)
    if (-not $Condition) {
        throw $Because
    }
}

$passed = 0
$failed = 0

function Invoke-Test {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
        $script:passed++
    } catch {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $_" -ForegroundColor Red
        $script:failed++
    }
}

# ---------------------------------------------------------------------------
# Extract helper functions from AST once (avoids re-parsing per test)
# ---------------------------------------------------------------------------
$watchAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $watchScript, [ref] $null, [ref] $null
)

$colorHeaderDef = $watchAst.FindAll(
    { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                   $n.Name -ceq 'Format-WatchColorHeader' },
    $true
) | Select-Object -First 1

$limitLinesDef = $watchAst.FindAll(
    { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                   $n.Name -ceq 'Limit-WatchLines' },
    $true
) | Select-Object -First 1

$resolveAnchorDef = $watchAst.FindAll(
    { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                   $n.Name -ceq 'Resolve-WatchColorAnchor' },
    $true
) | Select-Object -First 1

# Dot-source the extracted functions into the current scope so tests can call them.
if ($null -ne $colorHeaderDef) {
    . ([scriptblock]::Create($colorHeaderDef.ToString()))
}
if ($null -ne $limitLinesDef) {
    . ([scriptblock]::Create($limitLinesDef.ToString()))
}
if ($null -ne $resolveAnchorDef) {
    . ([scriptblock]::Create($resolveAnchorDef.ToString()))
}

# ---------------------------------------------------------------------------
# Script exists and parses without errors
# ---------------------------------------------------------------------------
Invoke-Test 'Watch-Command.ps1 file exists' {
    Assert-True (Test-Path -LiteralPath $watchScript -PathType Leaf) `
        "Watch-Command.ps1 not found at $watchScript"
}

Invoke-Test 'Watch-Command.ps1 parses without syntax errors' {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $watchScript, [ref] $null, [ref] $errors
    ) | Out-Null
    Assert-True ($errors.Count -eq 0) "Syntax errors: $($errors -join '; ')"
}

# ---------------------------------------------------------------------------
# Parameter interface — -Color switch and interval parameters are declared
# ---------------------------------------------------------------------------
Invoke-Test 'Watch-Command declares -Color switch parameter' {
    $params = $watchAst.ParamBlock.Parameters
    $colorParam = $params | Where-Object { $_.Name.VariablePath.UserPath -ceq 'Color' }
    Assert-True ($null -ne $colorParam) '-Color parameter not declared'
    $typeName = $colorParam.StaticType.Name
    Assert-Equal 'SwitchParameter' $typeName '-Color must be a switch parameter'
}

Invoke-Test 'Watch-Command declares -Seconds interval parameter' {
    $params = $watchAst.ParamBlock.Parameters
    $secondsParam = $params | Where-Object { $_.Name.VariablePath.UserPath -ceq 'Seconds' }
    Assert-True ($null -ne $secondsParam) '-Seconds parameter not declared'
}

Invoke-Test 'Watch-Command declares -Milliseconds interval parameter' {
    $params = $watchAst.ParamBlock.Parameters
    $msParam = $params | Where-Object { $_.Name.VariablePath.UserPath -ceq 'Milliseconds' }
    Assert-True ($null -ne $msParam) '-Milliseconds parameter not declared'
}

# ---------------------------------------------------------------------------
# Help text — Color mode limitation must be documented
# ---------------------------------------------------------------------------
Invoke-Test 'Watch-Command help text documents Color mode limitation' {
    $content = Get-Content -LiteralPath $watchScript -Raw
    Assert-True ($content -match 'LIMITATION') `
        'Help block must contain a LIMITATION section'
    Assert-True ($content -match 'alternate-') `
        'LIMITATION section must mention alternate-screen buffers'
    Assert-True ($content -match 'progress bar') `
        'LIMITATION section must mention progress bars'
}

Invoke-Test 'Watch-Command help text documents -Color parameter' {
    $content = Get-Content -LiteralPath $watchScript -Raw
    Assert-True ($content -match '\.PARAMETER Color') `
        'Help block must contain a .PARAMETER Color entry'
}

Invoke-Test 'Watch-Command help text states unsupported cursor-driven limitation' {
    $content = Get-Content -LiteralPath $watchScript -Raw
    Assert-True ($content -match 'cursor') `
        'Help block must mention cursor-driven commands as unsupported'
    Assert-True ($content -match 'not supported') `
        'Help block must state that these commands are not supported'
}

# ---------------------------------------------------------------------------
# Format-WatchColorHeader helper — returns exactly 3 lines
# ---------------------------------------------------------------------------
Invoke-Test 'Format-WatchColorHeader function found in script' {
    Assert-True ($null -ne $colorHeaderDef) `
        'Format-WatchColorHeader function not found in Watch-Command.ps1 AST'
}

Invoke-Test 'Format-WatchColorHeader returns 3 lines' {
    $result = Format-WatchColorHeader -UpdatedAt '12:00:00' -IntervalText '500 ms'
    Assert-Equal 3 $result.Count 'Format-WatchColorHeader must return exactly 3 lines'
}

Invoke-Test 'Format-WatchColorHeader rule line matches status line printable width' {
    $result = Format-WatchColorHeader -UpdatedAt '12:00:00' -IntervalText '500 ms'
    $printable = "● WATCHING | 12:00:00 | every 500 ms | Ctrl+C to stop"
    $rule = '─' * $printable.Length
    Assert-True ($result[0] -match [regex]::Escape($rule)) `
        'Top rule ANSI line must contain the expected rule characters'
    Assert-True ($result[2] -match [regex]::Escape($rule)) `
        'Bottom rule ANSI line must contain the expected rule characters'
}

Invoke-Test 'Format-WatchColorHeader status line contains WATCHING and timestamp' {
    $result = Format-WatchColorHeader -UpdatedAt '09:15:42' -IntervalText '5 s'
    Assert-True ($result[1] -match 'WATCHING') 'Status line must contain WATCHING'
    Assert-True ($result[1] -match '09:15:42') 'Status line must contain the timestamp'
    Assert-True ($result[1] -match '5 s') 'Status line must contain the interval'
}

Invoke-Test 'Format-WatchColorHeader status line contains Ctrl+C to stop' {
    $result = Format-WatchColorHeader -UpdatedAt '00:00:00' -IntervalText '1 s'
    Assert-True ($result[1] -match 'Ctrl\+C') 'Status line must contain Ctrl+C to stop'
}

# ---------------------------------------------------------------------------
# Limit-WatchLines helper — functional, non-interactive
# ---------------------------------------------------------------------------
Invoke-Test 'Limit-WatchLines function found in script' {
    Assert-True ($null -ne $limitLinesDef) `
        'Limit-WatchLines function not found in Watch-Command.ps1 AST'
}

Invoke-Test 'Limit-WatchLines truncates to requested height' {
    $result = Limit-WatchLines -Lines @('a','b','c','d','e') -Width 80 -FirstLineOffset 0 -Height 3
    Assert-True ($result.Count -le 3) "Height 3 must yield at most 3 lines; got $($result.Count)"
}

Invoke-Test 'Limit-WatchLines replaces last line with truncation indicator when content exceeds height' {
    $result = Limit-WatchLines -Lines @('a','b','c','d') -Width 80 -FirstLineOffset 0 -Height 2
    Assert-True ($result[-1] -match 'truncated') `
        "Last line must contain 'truncated' indicator when output is cut; got: $($result[-1])"
}

Invoke-Test 'Limit-WatchLines passes short content through unchanged' {
    $result = Limit-WatchLines -Lines @('hello','world') -Width 80 -FirstLineOffset 0 -Height 10
    Assert-Equal 2 $result.Count 'Short content must not be padded or altered in count'
    Assert-Equal 'hello' $result[0] 'First line content must be preserved'
    Assert-Equal 'world' $result[1] 'Second line content must be preserved'
}

Invoke-Test 'Limit-WatchLines truncates line that exceeds available width' {
    $longLine = 'x' * 200
    # Wrap in @() so a single-element return is not unwrapped to a bare string.
    $result = @(Limit-WatchLines -Lines @($longLine) -Width 20 -FirstLineOffset 0 -Height 5)
    Assert-True ($result[0].Length -lt 200) `
        "Line must be truncated to fit width 20; got length $($result[0].Length)"
}

Invoke-Test 'Limit-WatchLines respects FirstLineOffset for first line width' {
    $longLine = 'x' * 100
    $result = Limit-WatchLines -Lines @($longLine, $longLine) -Width 40 -FirstLineOffset 10 -Height 5
    Assert-True ($result[0].Length -le 29) `
        "First line with offset 10 on width 40 must fit in 29 chars (40-10-1); got $($result[0].Length)"
    Assert-True ($result[1].Length -le 39) `
        "Subsequent line on width 40 must fit in 39 chars (40-1); got $($result[1].Length)"
}

# ---------------------------------------------------------------------------
# Resolve-WatchColorAnchor helper — color marker validation and recovery
# ---------------------------------------------------------------------------
Invoke-Test 'Resolve-WatchColorAnchor function found in script' {
    Assert-True ($null -ne $resolveAnchorDef) `
        'Resolve-WatchColorAnchor function not found in Watch-Command.ps1 AST'
}

Invoke-Test 'Resolve-WatchColorAnchor keeps anchor when marker row is valid' {
    $visibleLines = @(
        'line 100',
        'line 101',
        'line 102',
        'line 103',
        'line 104',
        '● WATCHING | 10:00:00 | every 1 s | Ctrl+C to stop',
        'body',
        'tail'
    )
    $proposed = [System.Management.Automation.Host.Coordinates]::new(7, 104)
    $resolved = Resolve-WatchColorAnchor -VisibleLines $visibleLines `
        -WindowLeft 2 -WindowTop 100 -ProposedAnchor $proposed
    Assert-Equal 7 $resolved.X 'Valid marker should preserve anchor X'
    Assert-Equal 104 $resolved.Y 'Valid marker should preserve anchor Y'
}

Invoke-Test 'Resolve-WatchColorAnchor recovers nearest valid marker above stale anchor' {
    $visibleLines = @(
        'line 100',
        '● WATCHING | old',
        'line 102',
        '● WATCHING | newest above',
        'line 104',
        'no marker here',
        'body',
        'tail'
    )
    $proposed = [System.Management.Automation.Host.Coordinates]::new(9, 104)
    $resolved = Resolve-WatchColorAnchor -VisibleLines $visibleLines `
        -WindowLeft 2 -WindowTop 100 -ProposedAnchor $proposed
    Assert-Equal 2 $resolved.X 'Recovered anchor should align with visible window left'
    Assert-Equal 102 $resolved.Y 'Recovered anchor should be row above nearest marker above stale anchor'
}

Invoke-Test 'Resolve-WatchColorAnchor requires full WATCHING prefix, not bullet only' {
    $visibleLines = @(
        'line 100',
        'line 101',
        '● unrelated bullet line',
        'line 103',
        'line 104',
        'no marker here',
        'body',
        'tail'
    )
    $proposed = [System.Management.Automation.Host.Coordinates]::new(0, 104)
    $resolved = Resolve-WatchColorAnchor -VisibleLines $visibleLines `
        -WindowLeft 2 -WindowTop 100 -ProposedAnchor $proposed
    Assert-Equal 2 $resolved.X 'No valid marker should reset to visible window left'
    Assert-Equal 100 $resolved.Y 'No valid marker should reset to visible window top'
}

Invoke-Test 'Resolve-WatchColorAnchor does not recover from marker below stale anchor' {
    $visibleLines = @(
        'line 100',
        'line 101',
        'line 102',
        'line 103',
        'line 104',
        'no marker here',
        '● WATCHING | marker below',
        'tail'
    )
    $proposed = [System.Management.Automation.Host.Coordinates]::new(0, 104)
    $resolved = Resolve-WatchColorAnchor -VisibleLines $visibleLines `
        -WindowLeft 2 -WindowTop 100 -ProposedAnchor $proposed
    Assert-Equal 2 $resolved.X 'Marker below stale anchor must be ignored'
    Assert-Equal 100 $resolved.Y 'Marker below stale anchor must be ignored'
}

# ---------------------------------------------------------------------------
# Default mode regression: -Color switch absence does not change mode
# ---------------------------------------------------------------------------
Invoke-Test 'Watch-Command.ps1 contains default captured-output mode branch' {
    $content = Get-Content -LiteralPath $watchScript -Raw
    Assert-True ($content -match '\*>&1') `
        'Default mode must still capture all streams with *>&1'
}

Invoke-Test 'Watch-Command.ps1 contains both Color-mode and default-mode branches' {
    $content = Get-Content -LiteralPath $watchScript -Raw
    Assert-True ($content -match '\bif\s*\(\s*\$Color\s*\)') `
        'Script must branch on $Color'
    Assert-True ($content -match 'colorAnchor') 'Color-mode anchor variable must be present'
    Assert-True ($content -match '\$anchor\b') 'Default-mode anchor variable must be present'
}

Invoke-Test 'Watch-Command.ps1 color-mode cleans up on cancellation via finally' {
    $content = Get-Content -LiteralPath $watchScript -Raw
    # Both modes must have a finally block for cleanup.
    $finallyMatches = ([regex]::Matches($content, '\bfinally\b')).Count
    Assert-True ($finallyMatches -ge 2) `
        "Script must have at least 2 finally blocks (one per mode); found $finallyMatches"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
if ($failed -gt 0) {
    Write-Host "$passed passed, $failed failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host "$passed passed." -ForegroundColor Green
}
