$pwsh = Get-Process -PID $PID

if ($pwsh.Commandline.EndsWith(".exe`"")) {
    if ($(Get-ExecutionPolicy) -ne "ByPass") {
        Start-Process $pwsh.Path -Verb RunAs "-Command","Set-ExecutionPolicy -ExecutionPolicy Bypass"
    }
    
    $history_size = Get-ChildItem $env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt | ForEach-Object { $_.Length / 1Mb }
    if ($history_size -gt 10) {
        Write-Host -ForegroundColor DarkGray "ConsoleHost_history : $(($_.Length / 1Mb).ToString("0.00")) Mb"
    }

    # initialize kmonad
#    if ($null -eq (Get-Process | Where-Object Name -like kmonad-*)) {
#        Start-Job {
#            Push-Location "C:\GIT\Profile\kmonad"
#
#            $kmonad = Get-ChildItem kmonad-*-win.exe | Select-Object -First 1
#            Start-Process -FilePath $kmonad -ArgumentList config.kbd
#
#            Pop-Location
#        }
#    }

    # initialize veracrypt
    if (-not (Test-Path D:\)) {
        $veracypt_exe = 'C:\Program Files\VeraCrypt\VeraCrypt.exe'

        if ((Test-Path $veracypt_exe)) {
            $name = "Encrypted"
            $drive = "D:"
        
            Write-Host "mounting drive '$name'.." -ForegroundColor Yellow
            $pass = Read-Host 'What is your password?' -AsSecureString
        
            & $veracypt_exe /d d /q /s | Out-Null
            & $veracypt_exe /v \Device\Harddisk0\Partition5 /l d /a /q /p $((New-Object PSCredential "user",$pass).GetNetworkCredential().Password)
        
            while (-not (Test-Path $drive)) { Start-Sleep 1 }
            $rename = New-Object -ComObject Shell.Application
            $rename.NameSpace("$drive\").Self.Name = "$name"
        }
    }

    # initialize colors
    $PSStyle.FileInfo.Directory = $PSStyle.Foreground.BrightBlue

    # initialize prompt
    . "$PSScriptRoot\Install-Prompt.ps1"

    Get-ChildItem $PSScriptRoot -Filter Enter-*.ps1 |
    ForEach-Object {
        Invoke-Expression "function $($_.BaseName) { & `"$($pwsh.Path)`" -noe -NoLogo -File `"$($_.FullName)`" }"
    }

    # load scripts
    @(
        Get-ChildItem "$PSScriptRoot\Startup\*.ps1"
    ) |
        Where-Object Name -NE "Invoke-RestApi.ps1" |
        ForEach-Object {
            New-Alias -Name $_.BaseName -Value $_.FullName
        }

    # set alias to my programs
    Set-Alias bcomp   "C:/Program Files/Beyond Compare 4/bcomp.exe"
    Set-Alias vi      "$PSScriptRoot\Startup\Invoke-NeoVim.ps1"
    Set-Alias msbuild "C:/Program Files/Microsoft Visual Studio/2022/Community//MSBuild/Current/Bin/amd64/MSBuild.exe"
    Set-Alias choco   "$PSScriptRoot\Startup\Invoke-Chocolatey.ps1"
    Set-Alias code    "$PSScriptRoot\Startup\Invoke-VsCode.ps1"
    Set-Alias tree    "$PSScriptRoot\Startup\Invoke-Tree.ps1"

    # set alias to my scripts
    $dockerScript = "D:\Daten\docker.ps1"
    if ((Test-Path $dockerScript)) {
        New-Alias d $dockerScript # todo: remove alias
        New-Alias gt Get-SqlTable
        New-Alias rt Remove-SqlTable
        New-Alias gf Get-SqlField
        New-Alias gd Get-SqlDatabases
        New-Alias sd Set-SqlDatabase
        New-Alias gr Get-Random
        New-Alias ut Update-SqlTable
        New-Alias it Import-SqlTable
        New-Alias s Get-string

        # start mssql container
        Start-Job -ArgumentList $credentials,$dockerScript -ScriptBlock {
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

        # set argument completer
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
            ForEach-Object { Register-ArgumentCompleter -CommandName ("Get-SqlTable,Update-SqlTable,Remove-SqlTable,Read-SqlTableData" -split "," | Get-Alias -ErrorAction SilentlyContinue | ForEach-Object ResolvedCommand) -ParameterName $_ -ScriptBlock {
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
                    if ( $fakeBoundParameter.Contains("DatabaseName")) { $fakeBoundParameter.Database = $fakeBoundParameter.DatabaseName }
                    if ( $fakeBoundParameter.Contains("TableName")   ) { $fakeBoundParameter.Table    = $fakeBoundParameter.TableName }
                    if (-not $fakeBoundParameter.Contains("Database")) { $fakeBoundParameter.Database = $PSDefaultParameterValues["*:Database"] }
                    Invoke-Sqlcmd -Database $fakeBoundParameter.Database -Query "SELECT COLUMN_NAME FROM Information_Schema.columns WHERE TABLE_NAME LIKE '$($fakeBoundParameter.Table)' AND COLUMN_NAME LIKE '$wordToComplete%' ORDER BY COLUMN_NAME" |
                    ForEach-Object COLUMN_NAME |
                    ForEach-Object { New-Object System.Management.Automation.CompletionResult($_,$_,'ParameterValue', $_) }
        }}

        $credentials = Invoke-Expression (Get-Content -raw $dockerScript | Select-String -Pattern "\`$Global:credentials = (@\{[^}]+})").Matches.Groups[1].Value
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
    }

    # set new location
    if ((Get-Location).Path -eq $env:USERPROFILE -and (Test-Path "C:\GIT")) {
        Set-Location C:\GIT
    }
}

Set-PSReadLineOption -ViModeIndicator Script -ViModeChangeHandler $Function:OnViModeChange
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineKeyHandler -Key "Tab" -Function MenuComplete
Set-PSReadLineKeyHandler -Chord "Ctrl+i" -Function MenuComplete
Set-PSReadLineKeyHandler -Chord "Ctrl+f" -Function AcceptSuggestion
Set-PSReadLineKeyHandler -Chord "Ctrl+l" -Function AcceptNextSuggestionWord
Set-PSReadLineKeyHandler -Chord "Ctrl+k" -Function PreviousHistory
Set-PSReadLineKeyHandler -Chord "Ctrl+j" -Function NextHistory
