[cmdletbinding()]
param(
    [Parameter(Mandatory=$true,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [string[]]
    $Text
)
begin {
    $layouts = @{
        'qwerty' = @(
                    '`~ 1! 2@ 3# 4$ 5% 6^ 7& 8* 9( 0) -_ =+'
                    '﵃﵃ qQ wW eE rR tT yY uU iI oO pP [{ ]}'
                    '﵃﵃ aA sS dD fF gG hH jJ kK lL ;: ''" \|'
                    '\| zZ xX cC vV bB nN mM ,< .> /?'
                    #'\| zZ xX cC vV bB nN mM ,< .> /?'
        )
        'colemak-dh' = @(
                    '`~ 1! 2@ 3# 4$ 5% 6^ 7& 8* 9( 0) -_ =+'
                    '﵃﵃ qQ wW fF pP bB jJ lL uU yY ;: [{ ]}'
                    '﵃﵃ aA rR sS tT gG mM nN eE iI oO ''" \|'
                    '﵃﵃ xX cC dD vV zZ kK hH ,< .> /?'
        )
    }
    $template = @(
        '╭──────╮'
        '│  xx  │'
        '│yyyyyy│'
        '╰──────╯'
    )
    $usage = @{
    }
    $colorL = 60,40,40
    $colorH = 0,255,0
    $chars = 0
}
process {
    foreach ($c in $Text.ToCharArray()) {
        if (!$usage.ContainsKey($c)) {
            $usage.Add($c, 0)
        }
        $usage[$c] += 1
        $chars += 1
    }
}
end {
    foreach ($layout in $layouts.GetEnumerator()) {
        @(
            ""
            " ==== $($layout.Key) ===="
        ) | Write-Host

        $keyInfo = @{}
        foreach ($key in $layout.Value -split ' ') {
            $keyInfo[$key] = [pscustomobject]@{
                                legend = $key.PadLeft(2)
                                color  = $colorL
                                usage  = ($key.ToCharArray() |
                                            ForEach-Object {
                                                if ($usage.ContainsKey($_)) { $usage[$_] }
                                            } |
                                            Measure-Object -Sum).Sum
                                usageString = $null
            }
        }

        $stats = $keyInfo.Values.usage |
                    Measure-Object -Minimum -Maximum |
                    ForEach-Object {
                        [pscustomobject]@{
                            Minimum  = [int]($_.Minimum)
                            Maximum  = [int]($_.Maximum)
                            Steps    = 10
                            StepSize = $null
                            Colors   = $null
                        }
                    } |
                    ForEach-Object {
                            $_.StepSize = [int](($_.Maximum - $_.Minimum) / $_.Steps)
                            $_.Colors   = 1..($_.Steps) | ForEach-Object { $null }
                            $_
                    } |
                    ForEach-Object {
                        $vec  = @(
                                    [int](($colorH[0] - $colorL[0]) / ($_.Steps-1))
                                    [int](($colorH[1] - $colorL[1]) / ($_.Steps-1))
                                    [int](($colorH[2] - $colorL[2]) / ($_.Steps-1))
                        )
                        Write-Debug "vec = $($vec | ConvertTo-Json -Compress)"

                        $_.Colors[0] = $colorL
                        foreach ($i in 1..($_.Steps - 1)) {
                            $_.Colors[$i] = @(
                                    [int]($_.Colors[$i-1][0] + $vec[0])
                                    [int]($_.Colors[$i-1][1] + $vec[1])
                                    [int]($_.Colors[$i-1][2] + $vec[2])
                            )
                        }
                        $_.Colors[$_.Steps-1] = $colorH
                        $_
                    }
        Write-Debug "stats = $($stats | ConvertTo-Json -Compress)"

        foreach ($key in $keyInfo.Keys) {
            $colorIndex = ($keyInfo[$key].usage - $stats.Minimum) / $stats.StepSize
            if ($colorIndex -gt ($stats.steps-1)) { $colorIndex = $stats.Steps-1 }
            $colorIndex = try { [int]($colorIndex) } catch { 0 }

            $keyInfo[$key].color = $stats.Colors[$colorIndex]
            $keyInfo[$key].usageString = ($keyInfo[$key].usage * 100 / $chars).ToString('N1').PadLeft(5) + ' '
        }

        foreach ($row in $layout.Value) {
            $keys = $row -split ' '
            $template |
                ForEach-Object {
                    $template_row = $_
                    $keys |
                        ForEach-Object {
                            if ($_ -eq "﵃﵃") {
                                $ret = $template_row -replace '.',' '
                            } else {
                                $key = $keyInfo[$_]
                                $ret = $template_row.Replace('xx', $key.legend)
                                $ret = $ret.Replace('yyyyyy', $key.usageString)
                                $ret = "`e[38;2;$($key.color -join ';')m$ret`e[0m"
                            }
                            $ret
                        } |
                        Join-String -Separator ''
                }
        }
    }

    @(
        ""
        "chars: $chars"
    ) | Write-Host
}
