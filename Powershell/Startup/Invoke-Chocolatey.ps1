[CmdletBinding()]
param (
    [Parameter(Mandatory=$false,
        Position=0,
        ParameterSetName="ActionParameterSet")]
    [string]
    [ValidateSet("find", "list", "search", "help", "info", "install", "pin", "outdated", "upgrade", "uninstall", "pack", "push", "new", "sources", "source", "config", "feature", "features", "setapikey", "apikey", "unpackself", "export", "template", "templates")]
    $Command,

    [Parameter(Mandatory=$false,
        Position=1,
        ParameterSetName="ActionParameterSet",
        ValueFromRemainingArguments=$true)]
    [string[]]
    $Arguments
)
begin {
}
process {    
    $cmd = "& 'C:\ProgramData\chocolatey\bin\choco.exe' $Command $Arguments"
    $i=0
    Write-Debug $cmd
    
    if ($Command -eq "outdated") {
        Invoke-Expression $cmd |
            ForEach-Object {
                if ($i -lt 3) { 
                    $_ 
                }
                elseif ($_ -like "*|*") { 
                    if (($i % 2) -eq 1) {
                        $c = "`e[38;5;8m"
                    } else {
                        $c = ""
                    }

                    $line = $c + ($_ -replace "\|","`e[0m|$c") + "`e[0m"
                    $line | 
                        ConvertFrom-Csv -Delimiter "|" -Header "package name".PadRight(32),"current version","available version","pinned?" |
                        ForEach-Object { 
                            if ($_.'pinned?' -like "*true*") {
                                $_.("package name".PadRight(32)) += "📍"
                            }
                            $_
                        }
                }
                else { 
                    $_ 
                }
                $i++
            }
    } elseif ($Command -eq "list" -and $Arguments -notmatch "(-h|--help|-\?)") {
        $end_found = $false
        Invoke-Expression $cmd |
            ForEach-Object {
                if ($i -lt 1) { 
                    $_ | Write-Host -ForegroundColor Green
                } elseif ($end_found) {
                    $_
                } elseif ($_ -match "\d+ packages \w+" ) {
                    $end_found = $true
                    $_ | Write-Host -ForegroundColor Yellow
                } elseif ($_ -match "[^ ]+ \d+(\.\d+){3}") {
                    $array = $_ -split " "

                    [PSCustomObject]@{
                        "package name"= $array | Select-Object -First 1
                        "version"     = $array | Select-Object -Skip 1 -First 1
                        "description" = $array | Select-Object -Skip 2 | Join-String -Separator " "
                    }
                }
                $i++
            }
    } else {
        Invoke-Expression $cmd
    }
}
end {        
}

