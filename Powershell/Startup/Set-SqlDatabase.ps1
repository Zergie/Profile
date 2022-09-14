[CmdletBinding()]
param(
    [Parameter(Mandatory=$false,
               Position=0,
               ParameterSetName="ParameterSetName")]
    [string] 
    $Database
)
begin {
}
process {
    if ($PSDefaultParameterValues["*:Database"] -eq $Database) {
        Write-Host "Already on $Database"
    }

    if ($Database -eq "..") {
        $Database = "master"
    }
    
    if ($Database -in (Invoke-Sqlcmd -Database master -Query "SELECT name FROM sys.databases ORDER BY name" | ForEach-Object Name)) {
        $PSDefaultParameterValues["*:Database"] = $Database    
        $PSDefaultParameterValues["Write-SqlTableData:DatabaseName"] = $Database
        $PSDefaultParameterValues["Read-SqlTableData:DatabaseName"] = $Database
        Write-Host "Switched database to $Database"
    }
    else {
        Write-Error "Database $Database not found"
    }
}
end {}