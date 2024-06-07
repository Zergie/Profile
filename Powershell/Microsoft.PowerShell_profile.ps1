$pwsh = Get-Process -PID $PID

if ((Get-ExecutionPolicy) -ne "ByPass") {
    Start-Process $pwsh.Path -Verb RunAs "-NoProfile", "-Command","Set-ExecutionPolicy -ExecutionPolicy Bypass"
}

$firstUse = (Get-Process pwsh | Measure-Object).Count -eq 1 -or
    ((Get-Date)- $pwsh.StartTime).TotalSeconds -gt 10

$profiler = [pscustomobject]@{
    start     = Get-Date
    runtime   = $null
    status    = $null
    variables = [pscustomobject]@{}
    current   = [Hashtable]::new()
    last      = Get-Content $env:TEMP\Profile.json -ErrorAction SilentlyContinue | ConvertFrom-Json
}
function Start-Action {
    param (
        $Status
    )
    Write-Progress -Activity "Loading" -Status $Status
    $Global:profiler.status = $Status
}
function Complete-Action {
    $status = $Global:profiler.status
    $end = Get-Date
    $endtime = ($end - $profiler.start).TotalSeconds
    $Global:profiler.current.Add($Status, $endtime)

    $Global:profiler.runtime = ((Get-Date) - $Global:profiler.start)
    $percent = [Math]::Max(0, [Math]::Min(100, 100 * ($Global:profiler.runtime / $Global:profiler.last.runtime).TotalSeconds))
    Write-Progress -Activity "Loading" -Status $Status -PercentComplete $percent
}
Write-Progress -Activity "Loading" -Status "Starting" -PercentComplete 1

Start-Action "Getting history size"
    $history_size = Get-ChildItem $env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt | ForEach-Object { $_.Length / 1Mb }
    if ($history_size -gt 10) {
        Write-Host -ForegroundColor DarkGray "ConsoleHost_history : $(($_.Length / 1Mb).ToString("0.00")) Mb"
    }
Complete-Action

# initialize environment
Start-Action "Initialize environment "
    $secrets = (Get-Content "$PSScriptRoot/secrets.json" | ConvertFrom-Json)
    $env:OPENAI_API_KEY                      = $secrets.'Invoke-AutoCommit'.token
    $env:POWERSHELL_TELEMETRY_OPTOUT         = 1
    $env:POWERSHELL_UPDATECHECK              = "OFF"
    $env:PSModuleAnalysisCachePath           = 'NUL'
    $env:PSDisableModuleAnalysisCacheCleanup = 1
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Complete-Action

if ($firstUse) {
    # initialize veracrypt
    Start-Action "Initialize veracrypt"
        if (-not (Test-Path D:\)) {
            $veracypt_exe = 'C:\Program Files\VeraCrypt\VeraCrypt.exe'

            if ((Test-Path $veracypt_exe)) {
                $name  = "Encrypted"
                $drive = "D:"
                $pass  = $secrets.VeraCrypt.Password

                & $veracypt_exe /d d /q /s | Out-Null
                & $veracypt_exe /v \Device\Harddisk0\Partition5 /l d /a /q /p $pass

                while (-not (Test-Path $drive)) { Start-Sleep 1 }
                $rename = New-Object -ComObject Shell.Application
                $rename.NameSpace("$drive\").Self.Name = "$name"
            }
        }
    Remove-Variable secrets
    Complete-Action

    # show devops agent status
    Start-Action "Show devops agent status"
        Start-Job {
            param([pscustomobject] $oldProfiler, [pscustomobject] $oldVariables)

            # if (((Get-Date) - $oldProfiler.start).TotalHours -lt 12 `
            #     -and $null -ne $oldProfiler.variables.'DevOps Agents') {
            #     $oldProfiler.variables.'DevOps Agents' | ConvertTo-Json
            # } else {
                . "$using:PSScriptRoot/Startup/Invoke-RestApi.ps1" `
                    -Endpoint "GET https://dev.azure.com/{organization}/_apis/distributedtask/pools/{poolId}/agents?api-version=7.0" `
                    -Variables @{poolid=1} |
                    ForEach-Object value |
                    ForEach-Object {
                        [pscustomobject]@{
                            Type   = 'DevOps Agents'
                            Status = if ($_.Status -eq "offline") {
                                       $false
                                   } elseif ($_.Status -eq "online") {
                                       $true
                                   }
                        }
                    } |
                    ConvertTo-Json
            # }
        } -ArgumentList $profiler.last, $profiler.variables | Out-Null
    Complete-Action
}

# initialize colors
Start-Action "Initialize colors"
    $PSStyle.FileInfo.Directory = $PSStyle.Foreground.BrightBlue
Complete-Action

# initialize prompt
Start-Action "Initialize prompt"
    . "$PSScriptRoot\Install-Prompt.ps1"
Complete-Action

# Creating Enter-* scripts
Start-Action "Creating Enter-* scripts"
    Get-ChildItem $PSScriptRoot -Filter Enter-*.ps1 |
    ForEach-Object {
        Invoke-Expression "function $($_.BaseName) { & `"$($pwsh.Path)`" -noe -NoLogo -File `"$($_.FullName)`" }"
    }
Complete-Action

# load scripts
Start-Action "Load scripts"
    @(
        Get-ChildItem "$PSScriptRoot\Startup\*.ps1"
    ) |
        Where-Object Name -NE "Invoke-RestApi.ps1" |
        ForEach-Object {
            New-Alias -Name $_.BaseName -Value $_.FullName -ErrorAction SilentlyContinue
        }
Complete-Action

# set alias to my programs
Start-Action "Set alias to my programs"
    Set-Alias bcomp   "C:/Program Files/Beyond Compare 4/bcomp.exe"
    Set-Alias vi      "$PSScriptRoot\Startup\Invoke-NeoVim.ps1"
    Set-Alias msbuild "C:/Program Files/Microsoft Visual Studio/2022/Community//MSBuild/Current/Bin/amd64/MSBuild.exe"
    Set-Alias choco   "$PSScriptRoot\Startup\Invoke-Chocolatey.ps1"
    Set-Alias code    "$PSScriptRoot\Startup\Invoke-VsCode.ps1"
    Set-Alias tree    "$PSScriptRoot\Startup\Invoke-Tree.ps1"
    Set-Alias gh      "C:\Program Files\GitHub CLI\gh.exe"
    Set-Alias nf      "$PSScriptRoot\Startup\New-FeatureBranch.ps1"
    Set-Alias np      "$PSScriptRoot\Startup\New-PullRequest.ps1"
    Set-Alias ff      "$PSScriptRoot\Startup\Format-Files.ps1"
    Set-Alias gis     "$PSScriptRoot\Startup\Get-Issues.ps1"
    Set-Alias tshark  "$PSScriptRoot\Startup\Invoke-TShark.ps1"
    Set-Alias az      "C:/Program Files/Microsoft SDKs/Azure/CLI2/wbin/az.cmd"
Complete-Action

# set alias to my scripts
$dockerScript = "C:\Dokumente\Daten\docker.ps1"
if ((Test-Path $dockerScript)) {
    Start-Action "Set alias to my scripts"
        Set-Alias d $dockerScript # todo: remove alias
        Set-Alias gt "$PSScriptRoot\Startup\Get-SqlTable.ps1"
        Set-Alias rt "$PSScriptRoot\Startup\Remove-SqlTable.ps1"
        Set-Alias gf "$PSScriptRoot\Startup\Get-SqlField.ps1"
        Set-Alias gd "$PSScriptRoot\Startup\Get-SqlDatabases.ps1"
        Set-Alias sd "$PSScriptRoot\Startup\Set-SqlDatabase.ps1"
        Set-Alias gr "$PSScriptRoot\Startup\Get-Random.ps1"
        Set-Alias ut "$PSScriptRoot\Startup\Update-SqlTable.ps1"
        Set-Alias it "$PSScriptRoot\Startup\Import-SqlTable.ps1"
        Set-Alias s  "$PSScriptRoot\Startup\Get-String.ps1"
    Complete-Action

    # set argument completer
    Start-Action "Set argument completer"
        "Database","DatabaseName" |
            ForEach-Object { Register-ArgumentCompleter -ParameterName $_ -ScriptBlock {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
                    Invoke-Sqlcmd -Query "SELECT name FROM sys.databases WHERE database_id > 4 AND name LIKE '$wordToComplete%' ORDER BY name" |
                    ForEach-Object name |
                    ForEach-Object { New-Object System.Management.Automation.CompletionResult($_,$_,'ParameterValue', $_) }
        }}

        "Table","TableName" |
            ForEach-Object { Register-ArgumentCompleter -ParameterName $_ -ScriptBlock {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
                    if ( $fakeBoundParameter.Contains("DatabaseName")) { $fakeBoundParameter.Database = $fakeBoundParameter.DatabaseName }
                    if (-not $fakeBoundParameter.Contains("Database")) { $fakeBoundParameter.Database = $PSDefaultParameterValues["*:Database"] }
                    Invoke-Sqlcmd -Database $fakeBoundParameter.Database -Query "SELECT name FROM sys.tables WHERE name LIKE '$wordToComplete%' ORDER BY name" |
                    ForEach-Object { if ($_.name -like '* *') { "'$($_.name)'" } else { $_.name } } |
                    ForEach-Object { New-Object System.Management.Automation.CompletionResult($_,$_,'ParameterValue', $_) }
        }}

        "ColumnName","Fields","Sort","Filter" |
            ForEach-Object { Register-ArgumentCompleter -CommandName @(
                "Get-SqlTable.ps1"
                "Update-SqlTable.ps1"
                "Remove-SqlTable.ps1"
                "Read-SqlTableData.ps1"
            ) -ParameterName $_ -ScriptBlock {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
                    if ( $fakeBoundParameter.Contains("DatabaseName")) { $fakeBoundParameter.Database = $fakeBoundParameter.DatabaseName }
                    if ( $fakeBoundParameter.Contains("TableName")   ) { $fakeBoundParameter.Table    = $fakeBoundParameter.TableName }
                    if (-not $fakeBoundParameter.Contains("Database")) { $fakeBoundParameter.Database = $PSDefaultParameterValues["*:Database"] }
                    Invoke-Sqlcmd -Database $fakeBoundParameter.Database -Query "SELECT COLUMN_NAME FROM Information_Schema.columns WHERE TABLE_NAME LIKE '$($fakeBoundParameter.Table)' AND COLUMN_NAME LIKE '$wordToComplete%' ORDER BY COLUMN_NAME" |
                    ForEach-Object COLUMN_NAME |
                    ForEach-Object { New-Object System.Management.Automation.CompletionResult($_,$_,'ParameterValue', $_) }
        }}

        $credentials =  Get-Content -raw $dockerScript |
                            Select-String -Pattern "\n\s*\`$Global:credentials = (@\{[^}]+})" -AllMatches |
                            ForEach-Object Matches |
                            Select-Object -Last 1 |
                            ForEach-Object { $_.Groups[1].Value } |
                            Invoke-Expression
        $PSDefaultParameterValues = @{
            "*:Encoding" = 1252
            "*:Database" = "master"
            "*:ServerInstance" = $credentials.ServerInstance

            "Invoke-Sqlcmd:Username" = $credentials.Username
            "Invoke-Sqlcmd:Password" = $credentials.Password

            "Update-SqlTable.ps1:Username" = $credentials.Username
            "Update-SqlTable.ps1:Password" = $credentials.Password

            "Import-SqlTable.ps1:Username" = $credentials.Username
            "Import-SqlTable.ps1:Password" = $credentials.Password

            "Delete-SqlTable.ps1:Username" = $credentials.Username
            "Delete-SqlTable.ps1:Password" = $credentials.Password

            "Write-SqlTableData.ps1:Credential" = New-Object System.Management.Automation.PSCredential $credentials.Username, (ConvertTo-SecureString $credentials.Password -AsPlainText -Force)
            "Write-SqlTableData.ps1:SchemaName" = "dbo"
            "Write-SqlTableData.ps1:DatabaseName" = "master"

            "Read-SqlTableData.ps1:Credential" = New-Object System.Management.Automation.PSCredential $credentials.Username, (ConvertTo-SecureString $credentials.Password -AsPlainText -Force)
            "Read-SqlTableData.ps1:SchemaName" = "dbo"
            "Read-SqlTableData.ps1:DatabaseName" = "master"
        }
    Complete-Action
}

# set new location
Start-Action "Set new location"
    if ((Get-Location).Path -eq $env:USERPROFILE -and (Test-Path "C:\GIT")) {
        Set-Location C:\GIT
    }
Complete-Action

Start-Action "Set GIT_EDITOR"
    if ($pwsh.parent.parent.name -eq 'nvim') {
        $env:GIT_EDITOR='python C:/Python311/Lib/site-packages/nvr/nvr.py -cc "lua require(''FTerm'').close()" --remote-wait'
    }
Complete-Action

Start-Action "Configure PSReadLine"
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineKeyHandler -Key "Tab" -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord "Ctrl+t" -Function AcceptSuggestion
    # Set-PSReadLineKeyHandler -Chord "F9" -Function AcceptSuggestion
    Set-PSReadLineKeyHandler -Chord "Ctrl+s" -Function AcceptNextSuggestionWord
    # Set-PSReadLineKeyHandler -Chord "F8" -Function AcceptNextSuggestionWord

    Set-PSReadLineKeyHandler -Key "Alt+(" `
                             -BriefDescription ParenthesizeSelection `
                             -LongDescription "Put parenthesis around the selection or entire line and move the cursor to after the closing parenthesis" `
                             -ScriptBlock {
        param($key, $arg)

        $selectionStart = $null
        $selectionLength = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        if ($selectionStart -ne -1) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, '(' + $line.SubString($selectionStart, $selectionLength) + ')')
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        } else {
            $newLine = $line.SubString(0, $cursor).Trim()
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $cursor, '(' + $newLine + ')')
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 2)
        }
    }

    Set-PSReadLineKeyHandler -Key "Alt+)" `
                             -BriefDescription ParenthesizeSelection `
                             -LongDescription "Remove parenthesis around the selection or entire line and move the cursor to after the closing parenthesis" `
                             -ScriptBlock {
        param($key, $arg)

        $selectionStart = $null
        $selectionLength = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($selectionStart -ne -1) {
            $newLine = $line.SubString($selectionStart, $selectionLength)
            if ($newLine.StartsWith("(")) {
                $newLine = $newLine.SubString(1)
            }
            if ($newLine.EndsWith(")")) {
                $newLine = $newLine.SubString(0, $newLine.Length - 1)
            }
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $newLine)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $newLine.Length)
        } else {
            $newLine = $line.Trim()
            if ($newLine.StartsWith("(")) {
                $newLine = $newLine.SubString(1)
            }
            if ($newLine.EndsWith(")")) {
                $newLine = $newLine.SubString(0, $newLine.Length - 1)
            }
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $newLine)
            [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
        }
    }

    Set-PSReadLineKeyHandler -Key RightArrow `
                             -BriefDescription ForwardCharAndAcceptNextSuggestionWord `
                             -LongDescription "Move cursor one character to the right in the current editing line and accept the next word in suggestion when it's at the end of current editing line" `
                             -ScriptBlock {
        param($key, $arg)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($cursor -lt $line.Length) {
            [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar($key, $arg)
        } else {
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
        }
    }

    Set-PSReadLineKeyHandler -Key End `
                             -BriefDescription EndOfLineAndAcceptSuggestion `
                             -LongDescription "Move cursor to the end of the current editing line and accept the suggestion when it's at the end of current editing line" `
                             -ScriptBlock {
        param($key, $arg)

        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($cursor -lt $line.Length) {
            [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine($key, $arg)
        } else {
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptSuggestion($key, $arg)
        }
    }

    Set-PSReadLineKeyHandler -Chord F9 `
                             -BriefDescription CompleteWithScreenContent `
                             -LongDescription "Find a completion based on the current screen content" `
                             -ScriptBlock {
        param($key, $arg)
        $delimiter = " `"'([{}]):;,><\"
        $delimiter_regex = "[^ `r`n\:;,\>\<(\[{}\])\\]*"

        $line   = [string] $null
        $cursor = [int] $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        $wordBegin       = (" " + $line).LastIndexOfAny($delimiter.ToCharArray(), $cursor)
        $wordLength      = $cursor - $wordBegin

        if ($wordLength -gt 0) {
            $wordUnderCursor = $line.Substring($wordBegin, $wordLength)

            $size   = $host.UI.RawUI.WindowSize
            $rect   = [System.Management.Automation.Host.Rectangle]::new(0, 0, $size.Width, $size.Height)
            $buffer = $host.UI.RawUI.GetBufferContents($rect)

            $suggestion = $buffer.Character |
                Join-String |
                Select-String "\b$($wordUnderCursor)$delimiter_regex" -AllMatches |
                ForEach-Object { $_.Matches.Value } |
                Select-Object -SkipLast 1 |
                Select-Object -Last 1

            if ($null -ne $suggestion) {
                $newLine = "$($line.Substring(0, $wordBegin))$($suggestion)$($line.Substring($cursor))"
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $newLine)
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($wordBegin + $suggestion.Length)
            }
        }
    }
Complete-Action

if  ($firstUse) {
    # finish jobs
    Start-Action "Finish job"
        $variables = @{}
        Get-Job |
            Where-Object Name -NE "mssql" |
            ForEach-Object {
                Wait-Job $_ | Out-Null
                Receive-Job $_ |
                    ConvertFrom-Json |
                    Group-Object Type |
                    ForEach-Object {
                        $variables.Add($_.Name, $_.Group)
                    }
                Stop-Job $_
                Remove-Job $_
            }
        # ─ ━ │ ┃ ┄ ┅ ┆ ┇ ┈ ┉ ┊ ┋ ┌ ┍ ┎ ┏ ┐ ┑ ┒ ┓ └ ┕ ┖ ┗ ┘ ┙ ┚ ┛ ├ ┝ ┞ ┟
        # ┠ ┡ ┢ ┣ ┤ ┥ ┦ ┧ ┨ ┩ ┪ ┫ ┬ ┭ ┮ ┯ ┰ ┱ ┲ ┳ ┴ ┵ ┶ ┷ ┸ ┹ ┺ ┻ ┼ ┽ ┾ ┿
        # ╀ ╁ ╂ ╃ ╄ ╅ ╆ ╇ ╈ ╉ ╊ ╋ ╌ ╍ ╎ ╏ ═ ║ ╒ ╓ ╔ ╕ ╖ ╗ ╘ ╙ ╚ ╛ ╜ ╝ ╞ ╟
        # ╠ ╡ ╢ ╣ ╤ ╥ ╦ ╧ ╨ ╩ ╪ ╫ ╬ ╭ ╮ ╯ ╰ ╱ ╲ ╳ ╴ ╵ ╶ ╷ ╸ ╹ ╺ ╻ ╼ ╽ ╾ ╿
        $variables = [pscustomobject]$variables
        $template = "
╔═════════════════════════════╗
║ DevOps Agents : {0}         ║
╚═════════════════════════════╝
"
        $placeholder = " # # "
        $template = $template.Replace("{0}".PadRight($placeholder.Length), $placeholder)
        $variables.'DevOps Agents' |
            Sort-Object Name |
            ForEach-Object {
                $index = $template.IndexOf("#")
                $char = if ($_.Status) {'🟩'} else {'🟥'}
                $template =$template.Remove($index, 2)
                $template = $template.Insert($index, $char)
            }
        $template = $template.Replace("#", "🟥")

        Write-Host $template.Trim()
        Remove-Variable template, placeholder
    Complete-Action
}

if ($profiler.current.Length -gt 0) {
    $profiler.variables = $variables
    $profiler.last = $profiler.current
    $profiler.current = $null
    $profiler.runtime = ((Get-Date) - $profiler.start).TotalSeconds
    $profiler | ConvertTo-Json -Depth 9 | Set-Content $env:TEMP\Profile.json
}
Remove-Variable profiler, variables -ErrorAction SilentlyContinue
