[CmdletBinding()]
param(
    [Parameter(Position=0, ParameterSetName="FetchParameterSetName")]
    [Parameter(Position=0, ParameterSetName="CompareParameterSetName")]
    [Parameter(Position=0, ParameterSetName="CountParameterSetName")]
    [string]
    $Database,

    [Parameter(ParameterSetName="CountParameterSetName")]
    [switch]
    $Count,

    [Parameter(ParameterSetName="FetchParameterSetName")]
    [string]
    $Fetch,

    [Parameter(ParameterSetName="CompareParameterSetName")]
    [object]
    $CompareTo
)
Set-Alias Invoke-Sqlcmd "$PSScriptRoot\Invoke-Sqlcmd.ps1"
Set-Alias hash "$PSScriptRoot\hash.ps1"

$tables = Invoke-Sqlcmd -Database $Database -Query "SELECT name FROM sys.tables" |
              Add-Member -PassThru -Type ScriptProperty -Name "hash" -Value {$this.data|hash} |
              Add-Member -PassThru -NotePropertyName "data" -NotePropertyValue @() |
              ForEach-Object { $_.data += Invoke-Sqlcmd "SELECT * FROM [$($_.name)]" -As Array; $_} |
              Select-Object name, hash, data

if ($PSBoundParameters.ContainsKey('Fetch')) {
    Set-Variable -Name $Fetch -Value $tables -Scope Global
    $tables
} elseif ($Count) {
    $tables |
        Add-Member -PassThru ScriptProperty Count { ($this.data | Measure-Object).Count } |
        Where-Object Count -GT 0 |
        Sort-Object -Descending Count |
        Select-Object name, Count
} else {
    $Old = $CompareTo

    $primaryKeys = @{}
    Invoke-Sqlcmd "
    SELECT tc.Table_NAME, ccu.COLUMN_NAME FROM
        INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
        INNER JOIN INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE ccu ON tc.CONSTRAINT_NAME = ccu.Constraint_name
    WHERE
        tc.CONSTRAINT_TYPE = 'Primary Key'" |
            ForEach-Object { $primaryKeys[$_.TABLE_NAME] = $_.COLUMN_NAME }

    $tables |
        Where-Object { $n=$_; ($Old | Where-Object name -eq $n.name).hash -ne $n.hash} |
        ForEach-Object -Parallel {
            Set-Alias hash C:\git\Profile\Powershell\Startup\hash.ps1
            $n=$_
            $o=$using:Old | Where-Object name -eq $n.name | Select-Object -First 1
            $pk = ($using:primaryKeys)[$n.name]
            [pscustomobject]@{
              name    = $n.name
              hash    = $o.hash.Substring(0,7) + " -> " + $n.hash.Substring(0,7)
              added   = $n.data | Where-Object $pk -NotIn $o.data.($pk)
              deleted = $o.data | Where-Object $pk -NotIn $n.data.($pk)
              changed = $n.data |
                Where-Object $pk -In $o.data.($pk) |
                Where-Object {
                    $od=$o.data | hash
                    $nd=$n.data | Where-Object $pk -eq $_.($pk) | hash
                    $nd -ne $od
                }
            }
        }
}
