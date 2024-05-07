[cmdletbinding()]
param(
    [Parameter(ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [switch]
    $AsJob
)
process {
    $expression = "`"$dockerScript`" -Start"
    if ($AsJob) {
        $expression = @(
            "Start-Job {"
            "pwsh -NoProfile -File"
            $expression
            "}"
        ) | Join-String -Separator " "
    } else {
        $expression = ". $expression"
    }

    Write-Host -ForegroundColor Cyan $expression
    Invoke-Expression $expression

    If ($AsJob) {
    } else {
        $seconds = 10
        $success = $false
        while (! $success) {
            Write-Progress -Activity "Waiting for SQL Server to start up..." -SecondsRemaining $seconds

            Start-Sleep -Seconds 2
            $seconds -= 2

            try {
                Invoke-Sqlcmd -Database master -Query "SELECT name, compatibility_level, state_desc FROM sys.databases ORDER BY name"
                $success = $true
            } catch {}
        }
    }
}
