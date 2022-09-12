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
    if ($Path.GetType().FullName -eq 'System.Management.Automation.ScriptBlock') {
        $Path = Invoke-Command $Path
    }

    if ($Path.GetType().FullName -eq 'System.Management.Automation.AliasInfo') {
        $Path = $Path.Definition
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