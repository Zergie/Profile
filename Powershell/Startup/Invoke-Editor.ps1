[CmdletBinding()]
param (
    [Parameter(Mandatory=$false,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Editor,

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
    $RemainingArguments
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
        Write-Host -ForegroundColor Cyan  "== PSBoundParameters =="
        $PSBoundParameters | ConvertTo-Json -Depth 1 | Write-Host -ForegroundColor Cyan 
        
        Write-Host -ForegroundColor Cyan "== Path =="
        $Path | ConvertTo-Json -Depth 1 | Write-Host -ForegroundColor Cyan 
    }
    
    if ($RemainingArguments.Length -gt 0) {
        $RemainingArguments = $RemainingArguments.Substring("-RemainingArguments".Length)
    }

    . $Editor $path $RemainingArguments
}
end {        
}
