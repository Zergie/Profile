[CmdletBinding()]
param(
)
$ErrorActionPreference = 'Stop'

function Get-RGB {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [string] $hex,
        [string] $Delimiter = ";",
        [string] $Terminator = "m"
    )
    $c = ([int]"0x$($hex -replace '#','')")
    "$($c -shr 16 -band 255)$Delimiter$($c -shr 8 -band 255)$Delimiter$($c -band 255)$Terminator"
}

# Import modules
try {
    Import-Module -SkipEditionCheck posh-git
    Import-Module -SkipEditionCheck 'C:\ProgramData\chocolatey\lib\git-status-cache-posh-client\tools\git-status-cache-posh-client-1.0.0\GitStatusCachePoshClient.psm1'
} catch {
    exit
}
$GitPromptSettings.EnableFileStatusFromCache = $true

# colors
$palette = "395B64,2C3333,404258,474E68,50577A,6B728E" -split ","
$GitPromptSettings.BeforeStatus.BackgroundColor                     = [System.Console]::Black
$GitPromptSettings.AfterStatus.BackgroundColor                      = [System.Console]::Black
$GitPromptSettings.BeforeStatus.ForegroundColor                     = $palette[1] | Get-RGB -Delimiter ([CultureInfo]::CurrentCulture.TextInfo.ListSeparator) -Terminator ""
$GitPromptSettings.DefaultColor.BackgroundColor                     = $GitPromptSettings.BeforeStatus.ForegroundColor
$GitPromptSettings.BranchColor.BackgroundColor                      = $GitPromptSettings.BeforeStatus.ForegroundColor
$GitPromptSettings.BranchGoneStatusSymbol.BackgroundColor           = $GitPromptSettings.BeforeStatus.ForegroundColor
$GitPromptSettings.BranchIdenticalStatusSymbol.BackgroundColor      = $GitPromptSettings.BeforeStatus.ForegroundColor
$GitPromptSettings.BranchAheadStatusSymbol.BackgroundColor          = $GitPromptSettings.BeforeStatus.ForegroundColor
$GitPromptSettings.BranchBehindStatusSymbol.BackgroundColor         = $GitPromptSettings.BeforeStatus.ForegroundColor
$GitPromptSettings.DelimStatus.BackgroundColor                      = $GitPromptSettings.BeforeStatus.ForegroundColor
$GitPromptSettings.LocalStagedStatusSymbol.BackgroundColor          = $GitPromptSettings.BeforeStatus.ForegroundColor
$GitPromptSettings.BranchBehindAndAheadStatusSymbol.BackgroundColor = $GitPromptSettings.BeforeStatus.ForegroundColor
$GitPromptSettings.LocalWorkingStatusSymbol.BackgroundColor         = $GitPromptSettings.BeforeStatus.ForegroundColor
$GitPromptSettings.AfterStatus.ForegroundColor                      = $GitPromptSettings.BeforeStatus.ForegroundColor


if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    $fg1 = 'ffffff'    | Get-RGB
    $bg1 = 'dd0000'    | Get-RGB
} else {
    $fg1 = 'ffffff'    | Get-RGB
    $bg1 = $palette[0] | Get-RGB
}
# $fg2 = 'xxxxxx'
$bg2 = $palette[1] | Get-RGB
$fg3 = 'ffffff'    | Get-RGB
$bg3 = $palette[2] | Get-RGB
$fg4 = 'ffffff'    | Get-RGB
$bg4 = $palette[3] | Get-RGB

# Texts
$GitPromptSettings.PathStatusSeparator.Text = ""
$GitPromptSettings.DefaultPromptPrefix.Text = ""
$GitPromptSettings.DefaultPromptPath.Text   = ("`n┌ a" `
                                                    -replace ' ',   "`e[38;2;$bg1" `
                                                    -replace '(a)', "`e[38;2;$fg1`e[48;2;$bg1 `$1 `e[38;2;$bg1`e[48;2;$bg2" `
                                                ).Replace('a' , {$(Get-PromptPath)}
                                                )

$GitPromptSettings.BeforeStatus.Text        = "█"
$GitPromptSettings.AfterStatus.Text         = "█"
$GitPromptSettings.DefaultPromptSuffix.Text = (".ab`nx└ " `
                                                    -replace '\.' , "`e[38;2;$bg2`e[48;2;$bg3" `
                                                    -replace '(a)', "`e[38;2;$fg3`e[48;2;$bg3 `$1 `e[38;2;$bg3`e[48;2;$bg4" `
                                                    -replace '(b)', "`e[38;2;$fg4`e[48;2;$bg4`$1`e[0m`e[38;2;$bg4" `
                                                    -replace 'x'  , "`e[0m"
                                                ).Replace('a', { $((Get-Date).ToString("ddd HH:mm")) }
                                                ).Replace('b', { $(
                                                        try {
                                                            (Get-History)[-1].Duration |
                                                                ForEach-Object {
                                                                    if ($_.TotalSeconds -gt 1) {
                                                                        '  ' + $_.ToString('s\.f') + ' s '
                                                                    } else {
                                                                        '  ' + $_.TotalMilliseconds.ToString('0') + ' ms '
                                                                    }
                                                                }
                                                        } catch {
                                                        }
                                                    )}
                                                )

# Symbols
$GitPromptSettings.BranchBehindAndAheadStatusSymbol.Text = "李"
$GitPromptSettings.BranchAheadStatusSymbol.Text          = ""
$GitPromptSettings.BranchBehindStatusSymbol.Text         = ""
$GitPromptSettings.BranchIdenticalStatusSymbol.Text      = ""
$GitPromptSettings.BranchGoneStatusSymbol.Text           = ""

# ContinuationPrompt
Set-PSReadLineOption -ContinuationPrompt "  "
