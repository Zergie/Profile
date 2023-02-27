[CmdletBinding()]
param(
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
    $Year = [datetime]::Now.Year

    $lookup = [pscustomobject]@{
        "Mo" = [pscustomobject]@{start="08:30";end="17:15";var=@(-0,1.5,-0.5,1.5)}
        "Di" = [pscustomobject]@{start="08:30";end="17:15";var=@(-1,1,-0.5,1.5)}
        "Mi" = [pscustomobject]@{start="08:30";end="17:15";var=@(-1,1,-0.5,1.5)}
        "Do" = [pscustomobject]@{start="08:30";end="17:15";var=@(-1,1,-0.5,1.5)}
        "Fr" = [pscustomobject]@{start="08:30";end="16:00";var=@(-1,1,-0.5,1)}
    }

    1..356 |
        ForEach-Object {[datetime]::new($Year,1,1).AddDays($_-1)} |
        Where-Object {$_.ToString("ddd") -notin "Sa","So"} |
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
            
    "data is copied to clipboard" | Write-Host -ForegroundColor Green
}

