[CmdletBinding()]
param
(
    [Parameter(Position=0)]
    [string]
    $Path = $null,

    [Parameter()]
    [int]
    $Depth = 1,

    #List of wildcard matches. If a directoryname matches one of these, it will be skipped.
    [Parameter()]
    [string[]]
    $Exclude = $null,

    #List of wildcard matches. If a directoryname matches one of these, it will be shown.
    [Parameter()]
    [string[]]
    $Include = $null,

    [Parameter()]
    [string[]]
    $Filter = $null
)
begin {
    function c {
        param ( [string] $color)
        $Delimiter = [CultureInfo]::CurrentCulture.TextInfo.ListSeparator
        $c = ([int]"0x$($color -replace '#','')")
        "`e[38${Delimiter}2${Delimiter}$($c -shr 16 -band 255)${Delimiter}$($c -shr 8 -band 255)${Delimiter}$($c -band 255)m"
    }

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

        $folders = Get-ChildItem $path -Directory |
            Where-Object {
                if (($Global:Include | Measure-Object).Count -eq 0) {
                    $true
                } elseif ($Global:Depth -eq $depth) {
                    $false
                } else {
                    ($_ | Get-ChildItem -Include $Global:Include -Recurse -Depth ($Global:Depth - $depth - 1) | Measure-Object).Count -gt 0
                }
            } |
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
                    Icon       = "$(c ffd679)$([char]0xf07b)`e[0m"
                    Char       = if ($_.IsLast) { ' └' } else { ' ├' }
                    IndentChar = if ($_.IsLast) { '  ' } else { ' │' }
                }
            }

        $files = Get-ChildItem $path -Recurse -Depth 0 -Include $Global:Include -Exclude $Global:Exclude |
            Where-Object Attributes -NotContains "Directory" |
            ForEach-Object -PipelineVariable previous {
                if ($null -ne $previous) { $previous.IsLast = $false }

                [pscustomobject]@{
                    Name      = $_.Name
                    FullName  = $_.FullName
                    Extension = $_.Extension
                    IsLast    = $true
                }
            }
        $files = $files | ForEach-Object {
                [pscustomobject]@{
                    Name       = $_.Name
                    FullName   = $_.FullName
                    Directory  = $_.Directory.FullName
                    Icon       = switch -Regex ($_.Extension) {
                                    "^\.(ps1)$"            { "$(c 236fbd)$([char]0xebc7)`e[0m" }
                                    "^\.(msg)$"            { "$(c 006dc3)$([char]0xf6ed)`e[0m" }
                                    "^\.(md|bmpr|mmd)$"    { "$(c ff2000)$([char]0xe73e)`e[0m" }
                                    "^\.(html|xml)$"       { "$(c 28afea)$([char]0xf6e8)`e[0m" }
                                    "^\.(png|bmp|gif)$"    { "$(c 28afea)$([char]0xf7e8)`e[0m" }
                                    "^\.pd(f|x)$"          { "$(c b30b00)$([char]0xf725)`e[0m" }
                                    "^\.xl(s|t|sx|sm|tx)$" { "$(c 207647)$([char]0xf71b)`e[0m" }
                                    "^\.do(c|t|cx|cm|tx)$" { "$(c 2b589c)$([char]0xf72c)`e[0m" }
                                    default                { ' ' }
                                }
                    Char       = if ($null -eq $folders) { '  ' } else { ' │' }
                    IndentChar = if ($_.IsLast) { '  ' } else { '  ' }
                }
            }


        if ($files.Count -gt 20) {
            Write-Host "$indent$(' ') $(' ')($($files.Count) files)"
        } else {
            foreach ($item in $files) {
                Write-Host "$indent$($item.Char) $($item.Icon) $($item.Name)"
            }
        }
        foreach ($item in $folders) {
            Write-Host "$indent$($item.Char) $($item.Icon) $($item.Name)"
            Write-Folder $depth "$indent$($item.IndentChar)" $item.FullName
        }
    }
}
process {
    $Global:Depth = $Depth + 1
    $Global:Include = $Include + $Filter
    $Global:Exclude = $Exclude

    Write-Host
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Folder 0 '' (Get-Location)
    } else {
        Write-Folder 0 '' $Path
    }

    Write-Host
}
