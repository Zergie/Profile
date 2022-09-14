[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [String] 
    $Path
)

if ($PSDefaultParameterValues["*:Database"] -ne "master") {
    $old = $PSDefaultParameterValues["*:Database"]
    Set-SqlDatabase master
}

$result = @{}
$p = $PSBoundParameters.GetEnumerator() | ForEach-Object -Process { $result.Add($_.Key, $_.Value) } -End{ $result }
$p.Remove("Path")

& $dockerScript -Install $Path @p
    
if ($null -ne $old) {
    Set-SqlDatabase $old
}