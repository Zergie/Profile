[CmdletBinding()]
param (
)

$pattern = 'pwd|passwor[td]|token|(secret(?!s\\|s\.json))|LICENSE KEY'
$allowed = '
[
  "if ((Test-Path \"$PSScriptRoot\\secrets\")) {",
  "let tokens = split(a:line, nr2char(1))",
  "if len(tokens) != 5",
  "let [graph, sha, refs, subject, date] = tokens",
  "$pass = Read-Host ''What is your password?'' -AsSecureString",
  "& $veracypt_exe /v \\Device\\Harddisk0\\Partition5 /l d /a /q /p $((New-Object PSCredential \"user\",$pass).GetNetworkCredential().Password)",
  "$FTPRequest.Credentials = New-Object System.Net.NetworkCredential($ftp.user, $ftp.password)",
  "$FTPRequest.Credentials = New-Object System.Net.NetworkCredential($ftp.user, $ftp.password)",
  "\"Invoke-SqlCmd:Password\" = $credentials.Password",
  "\"Write-SqlTableData:Credential\" = New-Object System.Management.Automation.PSCredential $credentials.Username, (ConvertTo-SecureString $credentials.Password -AsPlainText -Force)",
  "\"Read-SqlTableData:Credential\" = New-Object System.Management.Automation.PSCredential $credentials.Username, (ConvertTo-SecureString $credentials.Password -AsPlainText -Force)",
  "$Password,",
  "$Password=$json.Password",
  "Password=$Password",
  "[System.Windows.Forms.SendKeys]::SendWait(\"$Password{Enter}\")",
  "$connection_string = \"Server=$($credentials.ServerInstance);Database=$Database;User Id=$($credentials.Username);Password=$($credentials.Password);\"",
  "$token = Get-Content \"$PSScriptRoot/../secrets.json\" -Encoding utf8 |",
  "ForEach-Object token",
  "Authorization = ''Basic '' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(\":$($token)\"))",
  "${Password},",
  "${NewPassword},",
  "if ($_ -like \"PASSWORT=*\") {",
  "\"PASSWORT=$text\"",
  "$connection_string = \"Server=$($credentials.ServerInstance);Database=$Database;User Id=$($credentials.Username);Password=$($credentials.Password);\""
]
' | ConvertFrom-Json 

$p = $PSScriptRoot -replace "\\","\\"

$secrets = Get-ChildItem "$PSScriptRoot" -Recurse -File | Select-String -Pattern $pattern
$secrets = $secrets | Where-Object Path -NotMatch "$p\\(neovim\\plugged|Powershell\\Modules|AutoHotkey\\libs)\\" # do not include external plugins
$secrets = $secrets | Where-Object Path -NotMatch "$p\\(secrets)\\"                  # do not include my 'secrets' submodule
$secrets = $secrets | Where-Object Path -NotMatch "$p\\Powershell\\secrets.json"     # do not include my 'secrets.json'
$secrets = $secrets | Where-Object Path -NotMatch "$p\\Beyond Compare 4\\BC4Key.txt" # do not include my 'BC4Key.txt'
$secrets = $secrets | Where-Object Path -NotMatch "$p\\Search-Secrets.ps1" # do not include myself
$secrets = $secrets | Where-Object { $_.Line.Trim() -notin $allowed }

$secrets 