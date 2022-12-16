[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]
    $Database,

    [Parameter()]
    [switch]
    $Update
)

$department = $Database
$main       = $Database -split '_' | Select-Object -SkipLast 1 | Join-String -Separator _
$logwatcher = Start-Job {
    $logfile    = "C:\Program Files (x86)\Tau-Office\AdminTool\AdminTool.log"

    Get-ChildItem $logfile | Remove-Item
    Set-Content $logfile ""
    Get-Content -Path $logfile -Encoding utf8 -Wait
}

Invoke-Sqlcmd -Database $department -Query "INSERT INTO zr_aktion (id) VALUES (358)" -ErrorAction SilentlyContinue
Invoke-Sqlcmd -Database $department -Query "UPDATE zr_aktion SET aktiv=1 WHERE id=358"

$verb = if ($Update) { "--update" } else { "--repair" }
. "C:\Program Files (x86)\Tau-Office\AdminTool\AdminTool.App.exe" $verb $department --ini "X:\INI\$($main).ini"
$process = Get-Process -Name "AdminTool.App"

while (!$process.HasExited) {
    $logwatcher | Receive-Job | bat --paging never --style=plain --language log
}
Start-Sleep -Seconds 1
$logwatcher | Receive-Job | bat --paging never --style=plain --language log
Stop-Job $logwatcher
