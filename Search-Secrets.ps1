[CmdletBinding()]
param (
    [Parameter()]
    [switch]
    $NoFilter,

    [Parameter()]
    [switch]
    $Update
)

$pattern = 'pwd|passwor[td]|token|(secret(?!s\\|s\.json))|LICENSE KEY'
if (!$NoFilter -and !$Update) {
    $allowed = '
[
  "\tpath = secrets",
  "\turl = https://github.com/Zergie/secrets.git",
  "                            ForEach-Object Password",
  "                    \"PASSWORT=$text\"",
  "                    pwd.dispatchEvent(new Event(''compositionend'', { bubbles: true }));",
  "                    pwd.dispatchEvent(new Event(''compositionstart'', { bubbles: true }));",
  "                    pwd.value = ''$pwd'';",
  "                    var pwd = document.querySelectorAll(''input[type=password]'')[0];",
  "                $FTPRequest.Credentials = New-Object System.Net.NetworkCredential($ftp.user, $ftp.password)",
  "                $pwd = Get-Content \"$PSScriptRoot\\..\\secrets.json\" | ",
  "                ForEach-Object token",
  "            \"Import-SqlTable.ps1:Password\" = $credentials.Password",
  "            \"Invoke-Sqlcmd:Password\" = $credentials.Password",
  "            \"Password=$Password\"",
  "            \"Password=$Password\"",
  "            \"Read-SqlTableData.ps1:Credential\" = New-Object System.Management.Automation.PSCredential $credentials.Username, (ConvertTo-SecureString $credentials.Password -AsPlainText -Force)",
  "            \"Update-SqlTable.ps1:Password\" = $credentials.Password",
  "            \"Write-SqlTableData.ps1:Credential\" = New-Object System.Management.Automation.PSCredential $credentials.Username, (ConvertTo-SecureString $credentials.Password -AsPlainText -Force)",
  "            & $veracypt_exe /v \\Device\\Harddisk0\\Partition5 /l d /a /q /p $((New-Object PSCredential \"user\",$pass).GetNetworkCredential().Password)",
  "            $pass = Read-Host ''What is your password?'' -AsSecureString",
  "            Microsoft.PowerShell.Archive\\Expand-Archive $zip $pwd -Force",
  "            Password=$Password",
  "        [System.Windows.Forms.SendKeys]::SendWait(\"$($Password -replace \".\",\"{`$0}\"){Enter}\")",
  "        $FTPRequest.Credentials = New-Object System.Net.NetworkCredential($ftp.user, $ftp.password)",
  "        $Password=$json.Password",
  "        Authorization = ''Basic '' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(\":$($token)\"))",
  "        if ($_ -like \"PASSWORT=*\") {",
  "    ${NewPassword},",
  "    ${Password},",
  "    $Password,",
  "    $Password,",
  "    $Password,",
  "    $token = Get-Content \"$PSScriptRoot/../secrets.json\" -Encoding utf8 |",
  "    if ((Test-Path \"$PSScriptRoot\\secrets\")) {",
  "  if len(tokens) != 5",
  "  let [graph, sha, refs, subject, date] = tokens",
  "  let tokens = split(a:line, nr2char(1))",
  "[submodule \"secrets\"]"
]
    ' | ConvertFrom-Json
} else {
    $allowed = @()
}

Push-Location $PSScriptRoot
$p = $PSScriptRoot -replace "\\","\\"

$secrets = Get-ChildItem "$PSScriptRoot" -Recurse -File -Exclude @(
                "*.dict"
                "*.dll"
                "*.exe"
                "*.pdb"
                "*.png"
                "*.psd"
                "*.pyc"
                "*.pyd"
                "*.zip"
            )|
            Select-String -Pattern $pattern
$secrets = $secrets | Where-Object Path -NotMatch "$p\\(\.git)\\"                                # do not include .git
$secrets = $secrets | Where-Object Path -NotMatch "$p\\(\.gitmodule)$"                           # do not include .gitmodule
$secrets = $secrets | Where-Object Path -NotMatch "$p\\(Powershell\\Modules|AutoHotkey\\libs)\\" # do not include external plugins
$secrets = $secrets | Where-Object Path -NotMatch "$p\\neovim\\(plugged|lsp_server)\\"           # do not include my neovim externals
$secrets = $secrets | Where-Object Path -NotMatch "$p\\(secrets)\\"                              # do not include my 'secrets' submodule
$secrets = $secrets | Where-Object Path -NotMatch "$p\\Powershell\\secrets.json"                 # do not include my 'secrets.json'
$secrets = $secrets | Where-Object Path -NotMatch "$p\\Beyond Compare 4\\BC4Key.txt"             # do not include my 'BC4Key.txt'
$secrets = $secrets | Where-Object Path -NotMatch "$p\\CQ-editor"                                # do not include CQ-editor
$secrets = $secrets | Where-Object Path -NotMatch "\\package-lock.json$"                         # do not include npm package-lock
$secrets = $secrets | Where-Object Path -NotMatch "$p\\Search-Secrets.ps1"                       # do not include myself
$secrets = $secrets | Where-Object { $_.Line -notin $allowed }
Pop-Location

if ($Update) {
    $allowed_finished = $false

    (Get-Content -Encoding utf8 $MyInvocation.MyCommand.Path |
        Out-String) -split "`n" |
        ForEach-Object { $_.TrimEnd() } |
        ForEach-Object -PipelineVariable last {
            [pscustomobject]@{
                Match = if ($null -eq $last) {
                           $false
                        } elseif ($last.Match -eq $false) {
                           $last.Line -match "^\s*\`$allowed\s*=\s*'`$"
                        } else {
                           $_ -notmatch "^\s*'\s*|\s* ConvertFrom-Json"
                        }
                Line  = $_
            }
        } |
        ForEach-Object {
            if ($_.Match) {
                if (!$allowed_finished) {
                    ($secrets.Line | Sort-Object | ConvertTo-Json) -replace "'","''"
                    $allowed_finished = $true
                }
            } else {
                $_.Line
            }
        } |
        Out-String |
        ForEach-Object { $_.TrimEnd() } |
        Set-Content -Encoding utf8 $MyInvocation.MyCommand.Path
}

$secrets
