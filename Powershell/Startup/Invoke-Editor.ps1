param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Editor,

    [Parameter(ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Input,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Arguments,

    [Parameter()]
    [switch]
    $DoNotTransformPaths
)
begin {
}
process {
    $argv = @()

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

        $argv += $path
    }

    if ($PSBoundParameters['Debug']) {
        Write-Host -ForegroundColor Cyan  "== PsBoundParameters =="
        $PSBoundParameters | ConvertTo-Json -Depth 1 | Write-Host -ForegroundColor Cyan

        Write-Host -ForegroundColor Cyan  "== argv =="
        $argv | ConvertTo-Json -Depth 1 | Write-Host -ForegroundColor Cyan
    }

    $argv = $argv |
        ForEach-Object {
            if ($DoNotTransformPaths) {
                $_
            } elseif ($_.Contains("/") -and !$_.StartsWith(".") -and !$_.Contains(":")) {
               ".\$($_.Replace("/", "\"))" # git status style paths
            }
            else {
               $_
            }
        } |
        ForEach-Object {
            if ($_.Length -eq 0) {
            } elseif ($_ -like '*"*') {
                "'$_'"
            } elseif ($_ -like '* *') {
                "`"$_`""
            } else {
                $_
            }
        }

    if ($PSBoundParameters['Debug']) {
        Write-Host -ForegroundColor Cyan ". $Editor $argv"
    } elseif ($Input.Length -gt 0) {
        $Input | . "$Editor" $argv
    } else {
        Invoke-Expression ". `"$Editor`" $argv"
    }
}
end {
}
