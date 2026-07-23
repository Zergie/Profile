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

while ($true) {
    $output = try {
        & $Command *>&1
    } catch {
        $_
    }

    $updatedAt = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$updatedAt] every $intervalText | Ctrl+C to stop"
    if ($null -ne $output) {
        $output | Out-String -Stream | Write-Host
    }

    Start-Sleep -Duration $interval
}
