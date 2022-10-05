[CmdletBinding()]
param (
    [Parameter(Mandatory=$false,
               Position=0,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [object]
    $Path,

    [Parameter(Mandatory=$false,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false,
               ValueFromRemainingArguments=$true
               )]
    [string]
    $RemaingArguments
)
$PsBoundParameters["Editor"] = "C:/tools/neovim/nvim-win64/bin/nvim.exe"
. "$PsScriptRoot\Invoke-Editor.ps1" @PsBoundParameters
