[cmdletbinding()]
param(
    [Parameter(Position=0)]
    [System.Management.Automation.InvocationInfo]
    $InvocationInfo,

    [string[]]
    $Exclude = "Progress"
)
$p = [hashtable]$InvocationInfo.BoundParameters
$activity = $InvocationInfo.Statement
$Exclude |
    Where-Object { $_ -in $p.Keys } |
    ForEach-Object {
        $activity = $activity -replace "[ ]*-$([Regex]::Escape($_))",""
        $p.Remove($_)
    }
$activity = $activity.Trim()

Write-Progress -Activity $activity -PercentComplete 1
$data = . $InvocationInfo.MyCommand @p
$i = 0
$count = ($data | Measure-Object).Count
$data |
    ForEach-Object {
        $p = 1 + (99 * $i/$count)
        Write-Progress `
            -Activity $activity `
            -Status "$i / $count" `
            -PercentComplete $p
        $_
        $i += 1
    }
Write-Progress -Activity $activity -Completed
