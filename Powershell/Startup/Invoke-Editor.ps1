param (
    [Parameter(Mandatory=$true,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Editor,

    [Parameter(Mandatory=$false,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Input,

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

    $args = $args | ForEach-Object {
        if ($_.Length -eq 0) {
        } elseif ($_ -like '*"*') {
            $_
        } elseif ($_ -like '* *') {
            "`"$_`""
        } else {
            $_
        }
    }

    if ($PSBoundParameters['Debug']) {
        Write-Host -ForegroundColor Cyan ". $Editor $args"
    } elseif ($Input.Length -gt 0) {
        $Input | . "$Editor" $args
    } else {
        Invoke-Expression ". `"$Editor`" $args"
    }
}
end {
}
