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
    $NoHeader,

    [Parameter()]
    [double]
    $Statement = 0
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
    $Year      = [datetime]::Now.Year
    $Begin     = if ($Start.Length -gt 0) { [datetime]::Parse($Start) } else { $null }
    $Finish    = if ($End.Length   -gt 0) { [datetime]::Parse($End)   } else { $null }

    $holidays  = (Invoke-RestMethod "https://feiertage-api.de/api/?jahr=$((Get-Date).Year)").BY |
        Get-Member -Type NoteProperty |
        ForEach-Object{
            $item = $holidays."$($_.name)"
            if ($item.hinweis -notlike "*Augsburger Friedensfest*") {
                [datetime]::Parse($item.datum).ToString("dd.MM.yyyy")
            }
        }

    $lookup = [pscustomobject]@{
        "more"   = [pscustomobject]@{
            "Mo" = [pscustomobject]@{start="07:30";end="17:15";var=@(-0.5,2.0, -0.2,0.5)}
            "Di" = [pscustomobject]@{start="07:30";end="17:15";var=@(-0.5,1.5, -0.2,0.5)}
            "Mi" = [pscustomobject]@{start="07:30";end="17:15";var=@(-0.5,1.5, -0.2,0.5)}
            "Do" = [pscustomobject]@{start="07:30";end="17:15";var=@(-0.5,1.5, -0.2,0.5)}
            "Fr" = [pscustomobject]@{start="07:30";end="17:00";var=@(-0.5,1.5, -0.2,0.5)}
        }
        "less"   = [pscustomobject]@{
            "Mo" = [pscustomobject]@{start="08:30";end="16:15";var=@(-0.5,2.5, -0.2,1.0)}
            "Di" = [pscustomobject]@{start="08:30";end="16:15";var=@(-0.5,2.0, -0.2,1.0)}
            "Mi" = [pscustomobject]@{start="08:30";end="16:15";var=@(-0.5,2.0, -0.2,1.0)}
            "Do" = [pscustomobject]@{start="08:30";end="16:15";var=@(-0.5,2.0, -0.2,1.0)}
            "Fr" = [pscustomobject]@{start="08:30";end="15:00";var=@(-0.5,2.0, -0.2,1.0)}
        }
        "normal" = [pscustomobject]@{
            "Mo" = [pscustomobject]@{start="08:30";end="17:15";var=@(-0.5,2.0, -0.2,0.8)}
            "Di" = [pscustomobject]@{start="08:30";end="17:15";var=@(-0.5,1.5, -0.2,0.8)}
            "Mi" = [pscustomobject]@{start="08:30";end="17:15";var=@(-0.5,1.5, -0.2,0.8)}
            "Do" = [pscustomobject]@{start="08:30";end="17:15";var=@(-0.5,1.5, -0.2,0.8)}
            "Fr" = [pscustomobject]@{start="08:30";end="15:00";var=@(-0.5,1.5, -0.2,0.8)}
        }
    }

    1..356 |
        ForEach-Object {[datetime]::new($Year,1,1).AddDays($_-1)} |
        Where-Object {$_.ToString("ddd") -notin "Sa","So"} |
        Where-Object { if ($null -eq $Begin)  { $true } else { $_ -ge $Begin  } } |
        Where-Object { if ($null -eq $Finish) { $true } else { $_ -le $Finish } } |
        ForEach-Object {

            if ($Statement -lt 0) {
                $l = $lookup.more
            } elseif ($Statement -gt 8) {
                $l = $lookup.less
            } elseif ($Statement -gt 4) {
                $l = $lookup.normal
            } elseif ($null -eq $l) {
                $l = $lookup.normal
            } else {
                # keep last lookup table
            }

            $preset = $l.($_.ToString("ddd"))
            [pscustomobject]@{
                date      = $_.ToString("dd.MM.yyyy")
                DayOfWeek = $_.ToString("ddd")
                start     = [System.TimeOnly]::Parse($preset.start).Add([timespan]::FromHours((rnd $preset.var[0] $preset.var[1])))
                end       = [System.TimeOnly]::Parse($preset.end).Add([timespan]::FromHours((rnd $preset.var[2] $preset.var[3])))
            }
        } |
        ForEach-Object {
            if ($_.date -notin $holidays) {
                $Statement += ($_.end - $_.start).TotalHours - 8 -0.5
                $_
            }
        } |
        ConvertTo-Csv -Delimiter `t |
        Set-Clipboard

        if ($NoHeader) {
            Get-Clipboard | Select-Object -Skip 1 | Set-Clipboard
        }

    "data is copied to clipboard" | Write-Host -ForegroundColor Green
}
