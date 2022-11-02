[CmdletBinding()]
param(
)

# Import modules
Import-Module -SkipEditionCheck posh-git
Import-Module -SkipEditionCheck 'C:\ProgramData\chocolatey\lib\git-status-cache-posh-client\tools\git-status-cache-posh-client-1.0.0\GitStatusCachePoshClient.psm1'
$GitPromptSettings.EnableFileStatusFromCache = $true

# colors
$GitPromptSettings.BeforeStatus.ForegroundColor                     = [System.ConsoleColor]::Black
$GitPromptSettings.BeforeStatus.BackgroundColor                     = [System.Console]::Black
$GitPromptSettings.DefaultColor.BackgroundColor                     = [System.ConsoleColor]::Black
$GitPromptSettings.BranchColor.BackgroundColor                      = [System.ConsoleColor]::Black
$GitPromptSettings.BranchGoneStatusSymbol.BackgroundColor           = [System.ConsoleColor]::Black
$GitPromptSettings.BranchIdenticalStatusSymbol.BackgroundColor      = [System.ConsoleColor]::Black
$GitPromptSettings.BranchAheadStatusSymbol.BackgroundColor          = [System.ConsoleColor]::Black
$GitPromptSettings.BranchBehindStatusSymbol.BackgroundColor         = [System.ConsoleColor]::Black
$GitPromptSettings.DelimStatus.BackgroundColor                      = [System.ConsoleColor]::Black
$GitPromptSettings.LocalStagedStatusSymbol.BackgroundColor          = [System.ConsoleColor]::Black
$GitPromptSettings.BranchBehindAndAheadStatusSymbol.BackgroundColor = [System.ConsoleColor]::Black
$GitPromptSettings.LocalWorkingStatusSymbol.BackgroundColor         = [System.ConsoleColor]::Black
$GitPromptSettings.AfterStatus.ForegroundColor                      = [System.ConsoleColor]::Black
$GitPromptSettings.AfterStatus.BackgroundColor                      = [System.Console]::Black

$bg0 = '0m'    # [System.ConsoleColor]::Black
$fg1 = '255m'
$bg1 = '33m'
$fg2 = '255m'
$bg2 = '17m'
$fg3 = '255m'
$bg3 = '242m'

# Texts
$GitPromptSettings.PathStatusSeparator.Text = ""
$GitPromptSettings.DefaultPromptPrefix.Text = ""
$GitPromptSettings.DefaultPromptPath.Text   = ("`n┌ a" `
                                                    -replace ' ', "`e[38;5;$bg1" `
                                                    -replace '(a)', "`e[38;5;$fg1`e[48;5;$bg1 `$1 `e[38;5;$bg1`e[48;5;0m" `
                                                ).Replace('a' , {$(Get-PromptPath)}
                                                )

$GitPromptSettings.BeforeStatus.Text        = "█"
$GitPromptSettings.AfterStatus.Text         = "█"
$GitPromptSettings.DefaultPromptSuffix.Text = (".ab`nx└ " `
                                                    -replace '\.' , "`e[38;5;$bg0`e[48;5;$bg2" `
                                                    -replace '(a)', "`e[38;5;$fg2`e[48;5;$bg2 `$1 `e[38;5;$bg2`e[48;5;$bg3" `
                                                    -replace '(b)', "`e[38;5;$fg3`e[48;5;$bg3`$1`e[0m`e[38;5;$bg3" `
                                                    -replace 'x'  , "`e[0m"
                                                ).Replace('a', { $((Get-Date).ToString("HH:mm")) }
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
