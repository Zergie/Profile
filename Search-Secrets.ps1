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
  "[submodule \"secrets\"]",
  "\tpath = secrets",
  "\turl = https://github.com/Zergie/secrets.git",
  "    Microsoft.PowerShell.Archive\\Expand-Archive $zip $pwd -Force",
  "if ((Test-Path \"$PSScriptRoot\\secrets\")) {",
  "  let tokens = split(a:line, nr2char(1))",
  "  if len(tokens) != 5",
  "  let [graph, sha, refs, subject, date] = tokens",
  "            $pass = Read-Host ''What is your password?'' -AsSecureString",
  "            & $veracypt_exe /v \\Device\\Harddisk0\\Partition5 /l d /a /q /p $((New-Object PSCredential \"user\",$pass).GetNetworkCredential().Password)",
  "            \"Invoke-Sqlcmd:Password\" = $credentials.Password",
  "            \"Update-SqlTable:Password\" = $credentials.Password",
  "            \"Import-SqlTable:Password\" = $credentials.Password",
  "            \"Write-SqlTableData:Credential\" = New-Object System.Management.Automation.PSCredential $credentials.Username, (ConvertTo-SecureString $credentials.Password -AsPlainText -Force)",
  "            \"Read-SqlTableData:Credential\" = New-Object System.Management.Automation.PSCredential $credentials.Username, (ConvertTo-SecureString $credentials.Password -AsPlainText -Force)",
  "    $Password,",
  "        $Password=$json.Password",
  "            Password=$Password",
  "        [System.Windows.Forms.SendKeys]::SendWait(\"$Password{Enter}\")",
  "                $pwd = Get-Content \"$PSScriptRoot\\..\\secrets.json\" | ",
  "                            ForEach-Object Password",
  "                    var pwd = document.querySelectorAll(''input[type=password]'')[0];",
  "                    pwd.dispatchEvent(new Event(''compositionstart'', { bubbles: true }));",
  "                    pwd.value = ''$pwd'';",
  "                    pwd.dispatchEvent(new Event(''compositionend'', { bubbles: true }));",
  "    $Password,",
  "            \"Password=$Password\"",
  "        $FTPRequest.Credentials = New-Object System.Net.NetworkCredential($ftp.user, $ftp.password)",
  "                $FTPRequest.Credentials = New-Object System.Net.NetworkCredential($ftp.user, $ftp.password)",
  "$token = Get-Content \"$PSScriptRoot/../secrets.json\" -Encoding utf8 |",
  "            ForEach-Object token",
  "    Authorization = ''Basic '' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(\":$($token)\")) ",
  "    ${Password},",
  "    ${NewPassword},",
  "        if ($_ -like \"PASSWORT=*\") {",
  "                    \"PASSWORT=$text\"",
  "    $Password,",
  "            \"Password=$Password\""
]
    ' | ConvertFrom-Json 
} else {
    $allowed = @()
}

Push-Location $PSScriptRoot
$p = $PSScriptRoot -replace "\\","\\"

$secrets = Get-ChildItem "$PSScriptRoot" -Recurse -File | Select-String -Pattern $pattern
$secrets = $secrets | Where-Object Path -NotMatch "$p\\(Powershell\\Modules|AutoHotkey\\libs)\\" # do not include external plugins
$secrets = $secrets | Where-Object Path -NotMatch "$p\\neovim\\(plugged|lsp_server)\\" # do not include my neovim externals
$secrets = $secrets | Where-Object Path -NotMatch "$p\\(secrets)\\"                    # do not include my 'secrets' submodule
$secrets = $secrets | Where-Object Path -NotMatch "$p\\Powershell\\secrets.json"       # do not include my 'secrets.json'
$secrets = $secrets | Where-Object Path -NotMatch "$p\\Beyond Compare 4\\BC4Key.txt"   # do not include my 'BC4Key.txt'
$secrets = $secrets | Where-Object Path -NotMatch "$p\\Search-Secrets.ps1"             # do not include myself
$secrets = $secrets | Where-Object { $_.Line.Trim() -notin $allowed }
Pop-Location

if ($Update) {
    $allowed_finished = $false

    Get-Content -Encoding utf8 $MyInvocation.MyCommand.Path |
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
                    ($secrets.Line | ConvertTo-Json) -replace "'","''"
                    $allowed_finished = $true
                }
            } else {
                $_.Line
            }
        } |
        Set-Content -Encoding utf8 $MyInvocation.MyCommand.Path
}

$secrets 
