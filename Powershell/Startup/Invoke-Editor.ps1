[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Editor,

    [Parameter(Mandatory=$false,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Arguments
)
begin {
}
process {
    $args = @()

    foreach ($path in $Arguments) {
        if ($path -eq "-Verbose") {
            $PSBoundParameters['Verbose'] = $true
            $VerbosePreference = 'Continue'
            $path = ""
        } elseif ($path -eq "-Debug") {
            $PSBoundParameters['Debug'] = $true
            $DebugPreference = 'Continue'
            $path = ""
        } elseif ($path.EndsWith("-?")) {
            $path = Get-Command $path.SubString(0, $path.Length-3)
        }

        while ($path -is [System.Management.Automation.AliasInfo]) {
            $path = $path.Definition

            if (!(Test-Path $path)) {
                $path = Get-Command $path
            }
        }

        $args += $path
    }
     
    if ($PSBoundParameters['Debug']) {
        Write-Host -ForegroundColor Cyan  "== PsBoundParameters =="
        $PSBoundParameters | ConvertTo-Json -Depth 1 | Write-Host -ForegroundColor Cyan 

        Write-Host -ForegroundColor Cyan  "== args =="
        $args | ConvertTo-Json -Depth 1 | Write-Host -ForegroundColor Cyan 
    }

    if ($PSBoundParameters['Debug']) {
        Write-Host -ForegroundColor Cyan ". $Editor $args"
    } else {
        . $Editor $args
    }
}
end {        
}
