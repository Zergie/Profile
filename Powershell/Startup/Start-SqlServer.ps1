[cmdletbinding()]
param(
    [Parameter(ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [switch]
    $AsJob
)
process {
    if ($AsJob) {
        $expression = @(
            "Start-ThreadJob {"
            "pwsh -NoProfile -Command {`n`t"
            @(
                "`$dockerScript = '$dockerScript'"
                "Set-Alias Invoke-Sqlcmd '$PSScriptRoot\Invoke-Sqlcmd.ps2'"
                ". $PSScriptRoot\$($MyInvocation.MyCommand)"
            ) | Join-String -Separator `n`t
            "`n}}"
        ) | Join-String -Separator ""
    } else {
        $expression = ". `"$dockerScript`" -Start"
    }

    Write-Host -ForegroundColor Cyan $expression
    Invoke-Expression $expression

    if ($AsJob) { exit }

    # docker ps --format json 2> nul |
    #     ConvertFrom-Json |
    #     Where-Object names -Like mssql |
    #     ForEach-Object Status

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
