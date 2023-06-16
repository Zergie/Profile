[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true,
               Position = 0,
               ParameterSetName="TypeParameterSet")]
    [ValidateSet("AdminTool.log", "TauError.log")]
    [string]
    $Type,

    [Parameter(Mandatory = $false,
               ParameterSetName="TypeParameterSet")]
    [switch]
    $Exit,

    [Parameter(Mandatory = $true,
               Position = 1,
               ParameterSetName="PathParameterSet")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path
)

if ($Type.Length -gt 0) {
    $Path = @{
        "AdminTool.log" = "C:\Program Files (x86)\Tau-Office\AdminTool\AdminTool.log"
        "TauError.log"  = "C:\GIT\TauOffice\tau-office\bin\TauError.log"
    }[$Type]

    if ($Exit) {
        $ProcessName = @{
            "AdminTool.log" = "AdminTool.App"
            "TauError.log"  = "MSACCESS"
        }[$Type]
    }
}

Write-Host "Watching file: $path"
Get-ChildItem $path | Remove-Item
Set-Content $path ""

$watcher = Start-Job {
    param($Path)
    if ("TauError" -in $Path) {
        Get-Content -Path $path -Encoding 1252 -Wait
    } else {
        Get-Content -Path $path -Encoding utf8 -Wait
    }
} -ArgumentList $Path


If ($null -eq $ProcessName) {
    while ($true) {
        $watcher | Receive-Job | bat --paging never --style=plain --language log
        Start-Sleep -Seconds 1
    }
} else {
    $process = Get-Process -Name $ProcessName
    while (!$process.HasExited) {
        $watcher | Receive-Job | bat --paging never --style=plain --language log
    }
    Start-Sleep -Seconds 1
    $watcher | Receive-Job | bat --paging never --style=plain --language log
    Stop-Job $watcher

    Write-Host
    Write-Host "exit code: $($process.ExitCode)"
}
