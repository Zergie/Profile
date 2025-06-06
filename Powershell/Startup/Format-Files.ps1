#Requires -PSEdition Core
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="PathParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to one or more locations.")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Path,

    [Parameter(Mandatory=$false,
               Position=0,
               ParameterSetName="ObjectParameterSet",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to one or more locations.")]
    [ValidateNotNullOrEmpty()]
    [PSCustomObject[]]
    $InputObject,

    [switch]
    $NoTests,

    [switch]
    $NoGitAdd
)
begin {
    $OldPSDefaultParameterValues = $PSDefaultParameterValues.Clone()
    $PSDefaultParameterValues = @{
        'Write-Error:CategoryActivity' = $MyInvocation.MyCommand.Name
        'Write-Progress:Activity'      = $MyInvocation.MyCommand.Name
    }

    $pathes = @()
}
process {
    if (($null -eq $Path) -and ($null -eq $InputObject)) {
        $InputObject = Get-GitStatus
    }

    if ($null -ne $Path) {
        $pathes += $Path | Get-ChildItem
    } elseif ($null -ne $InputObject) {
        $pathes += @(
                        $InputObject.Working
                        $InputObject.Index
                    ) |
                    Where-Object { $null -ne $_ } |
                    ForEach-Object { [System.IO.Path]::Combine($InputObject.GitDir, "..", $_) } |
                    ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
                    Where-Object { Test-Path $_ -PathType Leaf } |
                    Get-ChildItem
    }

    function Write-CodeError {
        param (
            [System.IO.FileInfo] $File,
            [object[]] $Content,
            [int]    $LineNumber,
            [string] $KeywordRegex,
            [string] $ErrorRegex,
            [string] $ErrorMessage
        )
        Write-Host "`e[38;5;238m───────┬─$([string]::new('─', $host.UI.RawUI.WindowSize.Width-9))`e[0m"
        Write-Host "`e[38;5;238m       │`e[0m File: .\$([System.IO.Path]::GetRelativePath((Get-Location).Path, $File.FullName))"
        Write-Host "`e[38;5;238m───────┼─$([string]::new('─', $host.UI.RawUI.WindowSize.Width-9))`e[0m"
        $Content |
            Select-Object -Skip ($LineNumber-5) |
            Select-Object -First 10 |
            ForEach-Object { "$($_.number.ToString().PadRight(6)) `e[38;5;238m│`e[0m $($_.content)" } |
            ForEach-Object { $_ -replace "^(|[^`"\n]+|([^`"\n]+`"[^`"\n]+`"[^`"\n]*)+)('.*)","`$1`e[38;2;89;139;78m`$3`e[0m" } |
            ForEach-Object { $_ -replace "(`"[^`"]+`")","`e[38;2;200;132;88m`$1`e[0m" } |
            ForEach-Object { $_ -replace "^([^']*)\b($KeywordRegex)\b","`$1`e[38;2;86;160;223m`$2`e[0m" } |
            ForEach-Object { $_ -replace "($ErrorRegex)(.*)","`e[48;5;1m`$1`e[40m`$2 `e[38;5;1m<- $ErrorMessage`e[0m" } |
            Out-String |
            Write-Host -NoNewline
        Write-Host "`e[38;5;238m───────┴─$([string]::new('─', $host.UI.RawUI.WindowSize.Width-9))`e[0m"
    }
}
end {
    $index = 0
    $pathes = $pathes |
                Where-Object Extension -NE ".patch" |
                Group-Object FullName |
                ForEach-Object { $_.Group[0] }
    $count = ($pathes | Measure-Object).Count

    if ($count -eq 0) {
        Write-Error "No path specified."
    } else {
        if ((Get-Process nvim -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
            nvr -c "silent wa"
        }

        Write-Progress -Status "Generating patches" -PercentComplete 1
        Write-Debug "Push-Location $((Get-GitStatusFromCache).Path)"
        Push-Location "$((Get-GitStatusFromCache).Path)"
        Write-Host -ForegroundColor Cyan "git difftool --tool=patch"
        git difftool --tool=patch

        foreach ($item in $pathes) {
            Write-Progress -Status $item.Name -PercentComplete (1 + 99 * $index / $count)
            Write-Verbose "Formatting $item."

            switch -Regex ($item.Name) {
                "\.(old)$" {
                    Remove-Item $item.FullName
                    Write-Host "$($item.Name) removed."
                    break
                }
                "^schema\.xml$" {
                    $cmd = $([System.IO.Path]::GetFullPath(
                        [System.IO.Path]::Combine($item.DirectoryName, "..", "scripts", "Update-XmlSchema.ps1")
                    ))
                    Write-Host -ForegroundColor Cyan $cmd
                    Invoke-Expression ". `"$cmd`""

                    $content = Get-Content $item.FullName -Encoding utf8 |
                        ForEach-Object { $_ -replace '="([^"]+)"','=''$1''' } |
                        Out-String
                    $content.Trim() |
                        Set-Content $item.FullName -Encoding utf8
                    break
                }
                "\.(xml)$" {
                    $xml = ([xml](Get-Content $item -Encoding utf8))

                    $settings = [System.Xml.XmlWriterSettings]::new()
                    $settings.Encoding = [System.Text.Encoding]::UTF8
                    $settings.Indent = $true

                    $writer = [System.Xml.XmlWriter]::Create($item.FullName, $settings)
                    $xml.Save($writer)
                    $writer.Close()
                    $writer.Dispose()
                    break
                }
                "\.(ACT)$" {
                    $xml = ([xml](Get-Content $item -Encoding utf8))
                    $max_id = ($xml.root.dataroot.ChildNodes.id | Measure-Object -Maximum).Maximum

                    if ($null -ne $max_id) {
                        $xml.root.dataroot.ChildNodes |
                            Where-Object id -eq "" |
                            ForEach-Object {
                                $max_id += 1
                                $_.id = $max_id
                                Write-Host -ForegroundColor Yellow "Generated ID $($_.id)."
                            }
                    }
                    $xml.root.dataroot.ChildNodes.id |
                        Group-Object |
                        Where-Object count -GT 1 |
                        ForEach-Object {
                            Write-Host -ForegroundColor Yellow "ID $($_.Name) is used $($_.Count) times! IDs should be unique."
                        }

                    $settings = [System.Xml.XmlWriterSettings]::new()
                    $settings.Encoding = [System.Text.Encoding]::UTF8
                    $settings.Indent = $true

                    $writer = [System.Xml.XmlWriter]::Create($item.FullName, $settings)
                    $xml.Save($writer)
                    $writer.Close()
                    $writer.Dispose()
                    break
                }
                "\.(ACF|ACR|ACM)$" {
                    Write-Host -ForegroundColor Cyan "git restore $item"
                    git restore "$item"
                    Start-Job -ArgumentList $item.FullName {
                        param( [string] $item )
                        & "C:\Program Files\Git\usr\bin\patch.exe" "$item" "$item.patch" | Out-Null
                        & "C:\Program Files\Git\usr\bin\unix2dos.exe" "$item" | Out-Null
                    } | Wait-Job | Remove-Job # Start-ThreadJob messes with ascii colors

                    $lineno = 0
                    $content = Get-Content $item -Encoding 1250 |
                                ForEach-Object { $lineno++; [pscustomobject]@{ number= $lineno; content= $_ } }

                    $countNoSaveCTIWhenDisabled = 0
                    $content |
                    ForEach-Object {
                        $keywords = "If|Then|Else|ElseIf|Not|Do( While| Until|)|Loop|While|Wend|For|To|Next|With|New|End|Set|Sub|Dim|Private|Public|As|On Error (Resume|Goto 0|Goto)|Stop|CStr|Is|Nothing|True|False|String|Long|Integer|Byte|Variant|Boolean| Select|Case|Exit( Sub| Function)"
                        $line = $_

                        if ($line.content -match "#TO_BUILD FAIL") {
                            Write-CodeError `
                                -File $item `
                                -Content $content `
                                -LineNumber $line.number `
                                -ErrorRegex "'?\s*#TO_BUILD FAIL" `
                                -ErrorMessage "FAIL marker should not be commited to production!" `
                                -KeywordRegex $keywords
                        } elseif ($line.content -match "\b$($regex="todo"; $regex)\b") {
                            Write-CodeError `
                                -File $item `
                                -Content $content `
                                -LineNumber $line.number `
                                -ErrorRegex $regex `
                                -ErrorMessage "todos should not be commited to production!" `
                                -KeywordRegex $keywords
                        } elseif ($line.content -match "$($regex="Bezeichung"; $regex)") {
                            Write-CodeError `
                                -File $item `
                                -Content $content `
                                -LineNumber $line.number `
                                -ErrorRegex $regex `
                                -ErrorMessage "typo? Should this be 'Bezeichnung'?" `
                                -KeywordRegex $keywords
                        }

                        $_.content
                    } |
                    ForEach-Object {
                        $line = $_

                        if ($line -match "^\s*Next\s[^ ]+") {
                            $line -replace "Next\s[^ ]+", "Next"
                        } elseif ($line -match "^\s*Checksum\s*=-?\d+") {
                            "Checksum =-240186"
                        } elseif ($line -match "Version =\d+") {
                            "Version =20"
                        } elseif ($line -match "^\s*NoSaveCTIWhenDisabled\s*=1") {
                            $countNoSaveCTIWhenDisabled += 1
                            if ($countNoSaveCTIWhenDisabled -le 1) {
                                $line
                            }
                        } else {
                            $line
                        }
                    } |
                    Out-String |
                    ForEach-Object { $_.Trim() + "`r`n" } |
                    Set-Content "$item.new" -Encoding 1250
                    Move-Item "$item.new" $item -Force
                    break
                }

                "\.(cs)$" {
                    $keywords = "namespace|using|public|private|protected|class|static|const|readonly|for|foreach|if|uint|null|ref|out|&&|\|\|return|var|int|string|new|double"
                    $lineno = 0
                    $content = Get-Content $item -Encoding utf8 |
                                ForEach-Object { $lineno++; [pscustomobject]@{ number= $lineno; content= $_ } }

                    $content |
                    ForEach-Object {
                        $line = $_

                        if ($line.content -match "\bDebugger\.Launch\b") {
                            Write-CodeError `
                                -File $item `
                                -Content $content `
                                -LineNumber $line.number `
                                -ErrorRegex "\bDebugger\.Launch[^;]*;?" `
                                -ErrorMessage "'Debugger.Launch' should not be commited to production!" `
                                -KeywordRegex $keywords
                        }

                        $_.content
                    } |
                    ForEach-Object { $_.TrimEnd() } |
                    Out-String |
                    ForEach-Object { $_.TrimEnd() } |
                    Set-Content $item -Encoding utf8NoBOM
                    break
                }

                "\.(ps1)$" {
                    Get-Content $item |
                    ForEach-Object { $_.TrimEnd() } |
                    Out-String |
                    ForEach-Object { $_.TrimEnd() } |
                    Set-Content $item
                    break
                }

                "\.(yml)$" {
                    $ignoreKeys = @(
                        "task"
                        "branch"
                    ) |
                        ForEach-Object { "(?<!${_}: )" } |
                        Join-String -Separator ''
                    $ignoreValues = @(
                        "true"
                        "none"
                        "\d"
                        "\d\d"
                        "\d\d\d"
                        "[>]"
                        "[|]"
                    ) |
                        ForEach-Object { "(?!${_})" } |
                        Join-String -Separator ''

                    Get-Content $item |
                    ForEach-Object { $_.TrimEnd() } |
                    ForEach-Object { $_ -replace "^(\s*)([^:]+:\s*)'([^']+)'$",'$1$2$3' } |
                    ForEach-Object { $_ -replace '^(\s*)([^:]+:\s*)"([^"]+)"$','$1$2$3' } |
                    ForEach-Object { $_ -replace "^(\s*)([^#: []+:\s*)${ignoreKeys}${ignoreValues}((?:[^#'' ]+\s+)*[^#'' ]+)(\s*#|`$)",'$1$2''$3''$4'} |
                    Out-String |
                    ForEach-Object { $_.TrimEnd() } |
                    Set-Content $item
                    break
                }

                default {
                    break
                }
            }

            $index += 1
        }

        Write-Progress -Status "Removing patches" -PercentComplete 80
        Get-ChildItem (Get-GitStatusFromCache).WorkingDir -Recurse -Filter *.patch | Remove-Item

        if (!$NoTests) {
            Write-Progress -Status "Running tests" -PercentComplete 80
            Write-Verbose "Searching tests.."
            foreach ($item in $pathes |
                        Get-ChildItem |
                        ForEach-Object {
                            [System.IO.Path]::Combine($_.DirectoryName, "..", "tests", "Run-Tests.ps1")
                            [System.IO.Path]::Combine($_.DirectoryName, ".", "tests", "Run-Tests.ps1")
                        } |
                        Where-Object { [System.IO.File]::Exists($_) } |
                        ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
                        Sort-Object -Unique |
                        Where-Object { !$_.EndsWith("tau-office\tests\Run-Tests.ps1") }
                    ) {

                Write-Host -ForegroundColor Cyan $item
                Start-ThreadJob { Set-Location $using:pwd; . $using:item } |
                    Receive-Job -AutoRemoveJob -Wait
            }
        }

        Write-Progress -Completed
        Write-Host "$count files formatted"
        Pop-Location
    }

    foreach ($key in @($PSDefaultParameterValues.Keys)) {
        if ($key -in $OldPSDefaultParameterValues.Keys) {
            $PSDefaultParameterValues[$key] = $OldPSDefaultParameterValues.$key
        } else {
            $PSDefaultParameterValues.Remove($key)
        }
    }

    if (!$NoGitAdd) {
        Write-Host -ForegroundColor Cyan "git add -p"
        git add -p
    }
}
