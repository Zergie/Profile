[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]
    $Database,

    [Parameter()]
    [switch]
    $NoUpdate
)

Stop-Process -Name AdminTool.App -ErrorAction SilentlyContinue
$logfile    = "C:\Program Files (x86)\Tau-Office\AdminTool\AdminTool.log"

$department = $Database
$main       = $Database -split '_' | Select-Object -SkipLast 1 | Join-String -Separator _
if ("Mandant" -in (. "$PSScriptRoot\Get-SqlTable.ps1" -Database $department).name) {
    $main = $department
}
$logwatcher = Start-Job {
    $logfile    = "C:\Program Files (x86)\Tau-Office\AdminTool\AdminTool.log"

    Get-ChildItem $logfile | Remove-Item
    Set-Content $logfile ""
    Get-Content -Path $logfile -Encoding utf8 -Wait
}

# Invoke-Sqlcmd -Database $department -Query "INSERT INTO zr_aktion (id) VALUES (358)" -ErrorAction SilentlyContinue
# Invoke-Sqlcmd -Database $department -Query "UPDATE zr_aktion SET aktiv=1 WHERE id=358"

Write-Host -ForegroundColor Cyan "linking schema.xml .."
Write-Host
Push-Location "${env:ProgramFiles(x86)}\Tau-Office\AdminTool\.."
Remove-Item .\schema.xml -Force -ErrorAction SilentlyContinue
New-Item -Type HardLink -Name schema.xml -Value "C:\GIT\TauOffice\DBMS\schema\schema.xml" | Out-Null
Pop-Location


$verb = if ($NoUpdate) { "--repair" } else { "--update" }
Write-Host -ForegroundColor Cyan "AdminTool.App.exe $verb $department --ini `"X:\INI\$($main).ini`" .."
. "C:\Program Files (x86)\Tau-Office\AdminTool\AdminTool.App.exe" $verb $department --ini "X:\INI\$($main).ini"
$process = Get-Process -Name AdminTool.App

while (!$process.HasExited) {
    $logwatcher | Receive-Job | bat --paging never --style=plain --language log
}
Start-Sleep -Seconds 2
$logwatcher | Receive-Job | bat --paging never --style=plain --language log
Stop-Job $logwatcher
