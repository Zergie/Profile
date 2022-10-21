[CmdletBinding()]
param
(
    [Parameter(Position=0)]
    [string]
    $Path = $null,

    [Parameter()]
    [int]
    $Depth=3,

    #List of wildcard matches. If a directoryname matches one of these, it will be skipped.
    [Parameter()]
    [string[]]
    $Exclude = $null,

    #List of wildcard matches. If a directoryname matches one of these, it will be shown.
    [Parameter()]
    [string[]]
    $Include = $null
)
begin {
    function Write-Folder {
        param
        (
            [int]    $depth,
            [string] $indent,
            [string] $path
        ) 
        Write-Verbose "Write-Folder $indent $Path"

        if ($depth -ge $Global:Depth) { return }
        $depth += 1

        $folders = Get-ChildItem $path |
            Where-Object Attributes -Contains "Directory" |
            ForEach-Object -PipelineVariable previous {
                if ($null -ne $previous) { $previous.IsLast = $false }

                [pscustomobject]@{
                    Name     = $_.Name
                    FullName = $_.FullName
                    IsLast   = $true
                }
            }
        $folders = $folders | ForEach-Object {
                [pscustomobject]@{
                    Name       = $_.Name
                    FullName   = $_.FullName
                    Icon       = '📁'
                    Char       = if ($_.IsLast) { ' └' } else { ' ├' }
                    IndentChar = if ($_.IsLast) { '  ' } else { ' │' }
                }
            }

        $files = Get-ChildItem $path -Recurse -Depth 0 -Include $Global:Include -Exclude $Global:Exclude |
            Where-Object Attributes -NotContains "Directory" |
            ForEach-Object -PipelineVariable previous {
                if ($null -ne $previous) { $previous.IsLast = $false }

                [pscustomobject]@{
                    Name     = $_.Name
                    FullName = $_.FullName
                    IsLast   = $true
                }
            }
        $files = $files | ForEach-Object {
                [pscustomobject]@{
                    Name       = $_.Name
                    FullName   = $_.FullName
                    Icon       = ' '
                    Char       = if ($null -eq $folders) { '  ' } else { ' │' }
                    IndentChar = if ($_.IsLast) { '  ' } else { '  ' }
                }
            }


        if ($files.Count -gt 10) {
            Write-Host "$indent$(' ') $(' ')($($files.Count) files)"
        } else {
            foreach ($item in $files ) {
                Write-Host "$indent$($item.Char) $($item.Icon)$($item.Name)"
            }
        }
        foreach ($item in $folders) {
            Write-Host "$indent$($item.Char) $($item.Icon)$($item.Name)"
            Write-Folder $depth "$indent$($item.IndentChar)" $item.FullName
        }
    }
}
process {
    $Global:Depth = $Depth
    $Global:Include = $Include
    $Global:Exclude = $Exclude

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Folder 0 '' (Get-Location)
    } else {
        Write-Host
        Write-Host (Resolve-Path $Path).Path
        Write-Folder 0 '' $Path
    }

    Write-Host
}
