$pwsh = Get-Process -PID $PID

if ($(Get-ExecutionPolicy) -ne "ByPass") {
    Start-Process $pwsh.Path -Verb RunAs "-Command","Set-ExecutionPolicy -ExecutionPolicy Bypass"
}

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
    $percent = [Math]::Min(100, 100 * ($Global:profiler.runtime / $Global:profiler.last.runtime).TotalSeconds)
    Write-Progress -Activity "Loading" -Status $Status -PercentComplete $percent
}
Write-Progress -Activity "Loading" -Status "Starting" -PercentComplete 1

Start-Action "Getting history size"
    $history_size = Get-ChildItem $env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt | ForEach-Object { $_.Length / 1Mb }
    if ($history_size -gt 10) {
        Write-Host -ForegroundColor DarkGray "ConsoleHost_history : $(($_.Length / 1Mb).ToString("0.00")) Mb"
    }
Complete-Action

# initialize environment variables
Start-Action "Initialize environment variables"
    $secrets = (Get-Content "$PSScriptRoot/secrets.json" | ConvertFrom-Json)
    $env:OPENAI_API_KEY = $secrets.'Invoke-AutoCommit'.token
Complete-Action

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

# show network info
Start-Action "Show network adapter"
    Start-Job {
        $adapter = Get-NetAdapter -Physical

        $name = "WLAN 2"
        if (($adapter | Where-Object Name -EQ "WLAN 3").Status -eq "Disconnected") {
            $name = "WLAN 3"
        }

        if (($adapter | Where-Object Name -EQ $name).Status -eq "Disconnected") {
            netsh wlan disconnect interface="WLAN" | Out-Null
            netsh wlan connect name=wrt-home interface=$name | Out-Null
            Start-Sleep -Seconds 2
            $adapter = Get-NetAdapter -Physical
        }

        $adapter |
            ForEach-Object `
                -Process {
                    [pscustomobject] @{
                        Type  = 'WLAN'
                        Name  = $_.Name
                        Text  = $_.Status
                        Color = if ($_.Status -eq "Disconnected") {
                                    "`e[31m"
                                } elseif ($_.Status -eq "Up") {
                                    "`e[32m"
                                }
                    }
                } `
                -End {
                    [pscustomobject]@{
                        Type  = 'WLAN'
                        Name  = 'WLAN'
                        Text  = 'Not Attached'
                        Color = "`e[90m"
                    }
                    [pscustomobject]@{
                        Type  = 'WLAN'
                        Name  = 'WLAN 2'
                        Text  = 'Not Attached'
                        Color = "`e[90m"
                    }
                    [pscustomobject]@{
                        Type  = 'WLAN'
                        Name  = 'WLAN 3'
                        Text  = 'Not Attached'
                        Color = "`e[90m"
                    }
                } |
            ConvertTo-Json
    } | Out-Null
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
                        Type  = 'DevOps Agents'
                        Text  = $_.Name
                        Color = if ($_.Status -eq "offline") {
                                    "`e[31m"
                                } elseif ($_.Status -eq "online") {
                                    "`e[32m"
                                }
                    }
                } |
                ConvertTo-Json
        # }
    } -ArgumentList $profiler.last, $profiler.variables | Out-Null
Complete-Action

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
Complete-Action

# set alias to my scripts
$dockerScript = "D:\Daten\docker.ps1"
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
        Set-Alias s  "$PSScriptRoot\Startup\Get-Utring.ps1"
    Complete-Action


    # start mssql container
    Start-Action "Start mssql container"
        Start-Job -Name "mssql" -ArgumentList $credentials,$dockerScript -ScriptBlock {
            param ([Hashtable] $credentials, [string] $dockerScript)

            function Test-SqlServerConnection {
                $requestCallback = $state = $null
                $socket = $credentials.ServerInstance -Split ','
                $h = ($socket | Select-Object -First 1).ToString()
                $p = ($socket | Select-Object -Skip 1 -First 1).ToString()
                $client = New-Object System.Net.Sockets.TcpClient
                $client.BeginConnect($h,$p,$requestCallback,$state) | Out-Null
                foreach ($i in 0..99) {
                    if ($client.Connected) {
                        break
                    } else {
                        Start-Sleep -Milliseconds 1
                    }
                }
                $connected = $client.Connected
                $client.Close()

                return $connected
            }

            if (Test-SqlServerConnection) {
                Write-Host "Connected to SQL Server instance '$($credentials.ServerInstance)'." -ForegroundColor Green
            } else {
                Write-Host "Starting SQL Server instance '$($credentials.ServerInstance)'."
                & $dockerScript -Start

                if (Test-SqlServerConnection) {
                    Write-Host "Connected to SQL Server instance '$($credentials.ServerInstance)'." -ForegroundColor Green
                } else {
                    Write-Host "Could not connect to SQL Server instance '$($credentials.ServerInstance)'." -ForegroundColor Red
                }
            }
        } | Out-Null
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
    Set-PSReadLineKeyHandler -Chord "F9" -Function AcceptSuggestion
    Set-PSReadLineKeyHandler -Chord "Ctrl+s" -Function AcceptNextSuggestionWord
    Set-PSReadLineKeyHandler -Chord "F8" -Function AcceptNextSuggestionWord
Complete-Action

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
╔════════════════════════╤══════════════════════════╗
║                        ┃ DevOps Agents :          ║
║ WLAN   : {0}           ┃ {3}                      ║
║ WLAN 2 : {1}           ┃ {4}                      ║
║ WLAN 3 : {2}           ┃ {5}                      ║
╚════════════════════════╧══════════════════════════╝
"

    $index = 0
    @(
        ($variables.'WLAN' | Where-Object Name -EQ 'WLAN')
        ($variables.'WLAN' | Where-Object Name -EQ 'WLAN 2' | Select-Object -First 1)
        ($variables.'WLAN' | Where-Object Name -EQ 'WLAN 3' | Select-Object -First 1)
        ($variables.'DevOps Agents' | Select-Object -First 1)
        ($variables.'DevOps Agents' | Select-Object -Skip 1 -First 1)
        ($variables.'DevOps Agents' | Select-Object -Skip 2 -First 1)
    )| ForEach-Object {
        $text = if ($null -eq $_.Text) { $_ } else { $_.Text }
        $color = $_.Color

        if ($text.Length -lt 3) {
            ($text.Length)..2 | ForEach-Object { $template = $template.Replace("{$index}", "{$index}`e[0m `e[0m") }
        }
        4..($text.Length) | ForEach-Object { $template = $template.Replace("{$index} ", "{$index}") }
        $template = $template.Replace("{$index}", "$color$text`e[0m")
        $index++
    }
    0..9 | ForEach-Object { $template = $template.Replace("{$_}", "   ") }
    $template = $template.Trim()

    Write-Host $template
    Remove-Variable template, index
Complete-Action

if ($profiler.current.Length -gt 0) {
    $profiler.variables = $variables
    $profiler.last = $profiler.current
    $profiler.current = $null
    $profiler.runtime = ((Get-Date) - $profiler.start).TotalSeconds
    $profiler | ConvertTo-Json -Depth 9 | Set-Content $env:TEMP\Profile.json
}
Remove-Variable profiler, variables
