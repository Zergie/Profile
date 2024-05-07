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
                    )
                    | Where-Object { $null -ne $_ }
                    | ForEach-Object { [System.IO.Path]::Combine($InputObject.GitDir, "..", $_) }
                    | Where-Object { Test-Path $_ -PathType Leaf }
                    | Get-ChildItem
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
            ForEach-Object { $_ -replace "('.*)","`e[38;2;89;139;78m`$1`e[0m" } |
            ForEach-Object { $_ -replace "(`"[^`"]+`")","`e[38;2;200;132;88m`$1`e[0m" } |
            ForEach-Object { $_ -replace "\b($KeywordRegex)\b","`e[38;2;86;160;223m`$1`e[0m" } |
            ForEach-Object { $_ -replace "($ErrorRegex)(.*)","`e[48;5;1m`$1`e[0m`$2 `e[38;5;1m<- $ErrorMessage`e[0m" } |
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
        Push-Location "$(Get-GitDirectory)/.."
        git difftool --tool=patch

        foreach ($item in $pathes) {
            Write-Progress -Status $item.Name -PercentComplete (1 + 99 * $index / $count)

            switch -regex ($item.Name) {
                "\.(old)$" {
                    Remove-Item $item.FullName
                    Write-Host "$($item.Name) removed."
                }
                "^schema\.xml$" {
                    $content = Get-Content $item.FullName -Encoding utf8 |
                        ForEach-Object { $_ -replace '="([^"]+)"','=''$1''' } |
                        Out-String
                    $content.Trim() |
                        Set-Content $item.FullName -Encoding utf8
                    break
                }
                "\.(ACT|xml)$" {
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

                "\.(ACF|ACR|ACM)$" {
                    git restore "$item"
                    Start-Job -ArgumentList $item.FullName {
                        param( [string] $item )
                        & "C:\Program Files\Git\usr\bin\patch.exe" "$item" "$item.patch" | Out-Null
                        & "C:\Program Files\Git\usr\bin\unix2dos.exe" "$item" | Out-Null
                    } | Wait-Job | Remove-Job

                    $lineno = 0
                    $content = Get-Content $item -Encoding 1250 |
                                ForEach-Object { $lineno++; [pscustomobject]@{ number= $lineno; content= $_ } }

                    $countNoSaveCTIWhenDisabled = 0
                    $content |
                    ForEach-Object {
                        $keywords = "If|Then|Else|ElseIf|Not|Do|Loop|While|Wend|For|To|Next|With|New|End|Set|Sub|Dim|Private|Public|As|On Error (Resume|Goto 0|Goto)|Stop|CStr|Is|Nothing|True|False|String|Long|Integer|Byte|Variant|Boolean|Select|Case"
                        $line = $_

                        if ($line.content -match "#TO_BUILD FAIL") {
                            Write-CodeError `
                                -File $item `
                                -Content $content `
                                -LineNumber $line.number `
                                -ErrorRegex "'?\s*#TO_BUILD FAIL" `
                                -ErrorMessage "FAIL marker should not be commited to production!" `
                                -KeywordRegex $keywords
                        } elseif ($line.content -match "\btodo\b") {
                            Write-CodeError `
                                -File $item `
                                -Content $content `
                                -LineNumber $line.number `
                                -ErrorRegex "todo" `
                                -ErrorMessage "todos should not be commited to production!" `
                                -KeywordRegex $keywords
                        }

                        $_.content
                    } |
                    ForEach-Object {
                        $line = $_

                        if ($line -match "^\s*Next\s[^ ]+") {
                            $line -replace "Next\s[^ ]+", "Next"
                        } elseif ($line -match "^\s*Checksum\s*=") {
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
                    Set-Content $item -Encoding 1250
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
                }
            }

            $index += 1
        }

        Write-Progress -Status "Removing patches" -PercentComplete 99
        Get-ChildItem -Recurse -Filter *.patch | Remove-Item

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
        Push-Location "$(Get-GitDirectory)/.."
        git add -p .
        Pop-Location
    }
}
