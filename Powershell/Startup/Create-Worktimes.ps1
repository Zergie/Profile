[CmdletBinding()]
param(
    [Parameter()]
    [string]
    $Start,

    [Parameter()]
    [string]
    $End,

    [Parameter()]
    [switch]
    $NoHeader
)
Begin {
    function rnd() {
        param ($min,$max)
            do {
                $s = 1
                    $x = 2 * $s * ((Get-Random -Minimum 0 -Maximum 10000)/10000) - $s
            } while (-not (0.4 * ((Get-Random -Minimum 0 -Maximum 10000)/10000) -lt (1 / [Math]::Sqrt(2 * [Math]::PI) * [Math]::Exp([Math]::Pow($x,2)/2))   ))
        $min+[Math]::Abs($x)*($max-$min)
    }
}
Process {
    $Year   = [datetime]::Now.Year
    $Begin  = if ($Start.Length -gt 0) { [datetime]::Parse($Start) } else { $null }
    $Finish = if ($End.Length   -gt 0) { [datetime]::Parse($End)   } else { $null }

    $lookup = [pscustomobject]@{
        "Mo" = [pscustomobject]@{start="07:30";end="16:30";var=@(-0.5,2.5, -0.2,1.0)}
        "Di" = [pscustomobject]@{start="07:30";end="16:30";var=@(-0.5,2.0, -0.2,1.0)}
        "Mi" = [pscustomobject]@{start="07:30";end="16:30";var=@(-0.5,2.0, -0.2,1.0)}
        "Do" = [pscustomobject]@{start="07:30";end="16:30";var=@(-0.5,2.0, -0.2,1.0)}
        "Fr" = [pscustomobject]@{start="07:30";end="15:00";var=@(-0.5,2.0, -0.2,1.0)}
    }

    1..356 |
        ForEach-Object {[datetime]::new($Year,1,1).AddDays($_-1)} |
        Where-Object {$_.ToString("ddd") -notin "Sa","So"} |
        Where-Object { if ($null -eq $Begin)  { $true } else { $_ -ge $Begin  } } |
        Where-Object { if ($null -eq $Finish) { $true } else { $_ -le $Finish } } |
        ForEach-Object {
            $preset = $lookup.($_.ToString("ddd"))
            [pscustomobject]@{
                date      = $_.ToString("dd.MM.yyyy")
                DayOfWeek = $_.ToString("ddd")
                start     = [System.TimeOnly]::Parse($preset.start).Add([timespan]::FromHours((rnd $preset.var[0] $preset.var[1])))
                end       = [System.TimeOnly]::Parse($preset.end).Add([timespan]::FromHours((rnd $preset.var[2] $preset.var[3])))
            }
        } |
        ConvertTo-Csv -Delimiter `t |
        Set-Clipboard

        if ($NoHeader) {
            Get-Clipboard | Select-Object -Skip 1 | Set-Clipboard
        }
            
    "data is copied to clipboard" | Write-Host -ForegroundColor Green
}

