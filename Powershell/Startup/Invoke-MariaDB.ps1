[CmdletBinding(DefaultParameterSetName='ByConnectionParameters')]
param(
    [Parameter(Position=0
              , ValueFromPipeline=$true
              , ValueFromPipelineByPropertyName=$true
              )]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Query},

    [Parameter(Position=1)]
    [ValidateNotNullOrEmpty()]
    [string]
    ${MariaDbDatabase} = "taucloud",

    [string]
    ${Container} = "tauclouddesktop-db-1",

    [string]
    ${MariaDbPassword} = "rocom"
)

begin {
}

process {
    if (!$Query.EndsWith(";")) {
        $Query += ";"
    }

    $PSBoundParameters.GetEnumerator() |
        ForEach-Object { Write-Debug "$($_.Key): $($_.Value)" }

    Write-Host $Query -ForegroundColor Cyan
    $Query |
        docker exec -i "$Container" mariadb "-p$MariaDbPassword" "-D$MariaDbDatabase" |
        ConvertFrom-Csv -Delimiter `t
    # $Query | docker exec -i tauclouddesktop-db-1 mariadb -p${MariaDbPassword} -D${MariaDbDatabase} | ConvertFrom-Csv -Delimiter `t
}

end { }