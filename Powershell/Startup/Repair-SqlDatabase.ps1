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

    Get-Content -Path $logfile -Encoding utf8 -Wait -Tail 15 #|
}


Write-Host -ForegroundColor Cyan "linking schema.xml .."
Write-Host
Push-Location "${env:ProgramFiles(x86)}\Tau-Office\AdminTool\.."
Remove-Item .\schema.xml -Force -ErrorAction SilentlyContinue
New-Item -Type SymbolicLink -Name schema.xml -Value "C:\GIT\TauOffice\DBMS\schema\schema.xml" | Out-Null
Pop-Location


$verb = if ($NoUpdate) { "--repair" } else { "--update" }
Write-Host -ForegroundColor Cyan "AdminTool.App.exe $verb $department --ini `"X:\INI\$($main).ini`" .."
. "C:\Program Files (x86)\Tau-Office\AdminTool\AdminTool.App.exe" $verb $department --ini "X:\INI\$($main).ini"
$process = Get-Process -Name AdminTool.App

$foundStart = $false
$startOfLog = [datetime]::Now.AddSeconds(-1)
while (!$process.HasExited) {
    if (! $foundStart) {
        $lines = $logwatcher | Receive-Job
        foreach ($line in $lines) {
            if ($null -ne $lines) {
                try {
                    $foundStart = $foundStart -or [datetime]::Parse($line.SubString(0, 23)) -ge $startOfLog
                } catch {
                }
            }
        }

        if ($foundStart) {
            $lines | bat --paging never --style=plain --language log
        }
    } else {
        $logwatcher | Receive-Job | bat --paging never --style=plain --language log
    }
}
Start-Sleep -Seconds 2
$logwatcher | Receive-Job | bat --paging never --style=plain --language log

switch -Regex (Get-Content $logfile -Tail 1) {
    "\(Success\)" { Write-Host -ForegroundColor Green "Success" }
    "Error"       { Write-Host -ForegroundColor Red "Error" }
}
Stop-Job $logwatcher
