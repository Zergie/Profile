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
begin {
}
process {
    if ($Path -is [System.Management.Automation.ScriptBlock]) {
        if ($Path -like "* -?") {
            $Path = Invoke-Expression "Get-Command $($Path.ToString() -replace '\s+-\?$','')"
        } else {
            $Path = Invoke-Command $Path
        }
    }
    
    while ($Path -is [System.Management.Automation.AliasInfo]) {
        $Path = $Path.Definition

        if (!(Test-Path $Path)) {
            $Path = Get-Command $Path
        }
    }
    
    if ($PSBoundParameters['Debug'].IsPresent) {
        Write-Host "== PSBoundParameters =="
        $PSBoundParameters | ConvertTo-Json -Depth 1
        
        Write-Host -ForegroundColor Cyan "== Path =="
        $Path | ConvertTo-Json -Depth 1 | Write-Host -ForegroundColor Cyan 
    }
    
    & "C:\Program Files\Microsoft VS Code\bin\code.cmd" $path $RemainingArguments
}
end {        
}