[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [String] 
    $Path
)

$p = $PSBoundParameters.GetEnumerator() | ForEach-Object -Begin { $r=@{} } -Process { $r.Add($_.Key, $_.Value) } -End{ $r }
$p.Remove("Path")

& $dockerScript -Install $Path @p
    
