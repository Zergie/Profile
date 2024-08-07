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
    if ($null -eq (Get-FormatData -TypeName 'User.ChocoOutdated')) {
        Update-FormatData -PrependPath "$PSScriptRoot\..\Format\User.ChocoOutdated.ps1xml"
    }
}
process {
    $cmd = ". 'C:\ProgramData\chocolatey\bin\choco.exe' $Command $Arguments"
    $i=0
    Write-Debug $cmd

    if ($Command -eq "outdated") {
        $found_begin = $false
        Invoke-Expression $cmd |
            ForEach-Object {
                if (!$found_begin) {
                    $_
                } elseif ($_ -like "*|*") {
                    $_ |
                        ConvertFrom-Csv -Delimiter "|" -Header "name","current version","available version","pinned" |
                        ForEach-Object {
                            $_.'current version' = [System.Version]::Parse($_.'current Version')
                            $_.'available version' = [System.Version]::Parse($_.'available version')
                            $_.pinned = ($_.pinned -like "*true*")
                            $_.PSObject.TypeNames.Insert(0,'User.ChocoOutdated')
                            $_
                        }
                }
                else {
                    $_
                }

                if ($_.StartsWith(' Output is package name')) {
                    $found_begin = $true
                }
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
                } elseif ($_ -match "[^ ]+ \d+(\.\d+){1,3}") {
                    $array = $_ -split " "

                    [pscustomobject]@{
                        "package name" = $array | Select-Object -First 1
                        "version"      = [Version]::new(($array | Select-Object -Skip 1 -First 1))
                    }
                }
                $i++
            }
    } elseif ($Command -eq "pin" -and $Arguments.Length -eq 0) {
        Invoke-Expression $cmd |
            ForEach-Object {
                if ($i -lt 1) {
                    $_ | Write-Host -ForegroundColor Green
                } else {
                    $_ | ConvertFrom-Csv -Delimiter "|" -Header "package name".PadRight(32),"version"
                }
                $i++
            }
    } elseif ($Command -eq "" -and $Arguments.Length -eq 0) {
        Invoke-Expression "$cmd -?"
    } elseif ($Command -in "upgrade","install","uninstall") {
        $cmd = "sudo $($cmd.Substring(2))"
        Invoke-Expression $cmd
    } else {
        Invoke-Expression $cmd
    }
}
end {
}
