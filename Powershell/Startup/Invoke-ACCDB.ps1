[cmdletbinding()]
param(
    [Parameter(ParameterSetName="InstallDependenciesParameterSet")]
    [ValidateNotNullOrEmpty()]
    [switch]
    $InstallDependencies,

    [Parameter(Mandatory, ParameterSetName="CreateParameterSet")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Table,

    [Parameter(Mandatory, ParameterSetName="CreateParameterSet")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Fields,

    [Parameter(ParameterSetName="CreateParameterSet")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Data,

    [Parameter(Mandatory, ParameterSetName="CreateParameterSet")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Create
)
switch ($PSCmdlet.ParameterSetName) {
    "InstallDependencies" {
        choco install made2010 -y
    }
    "CreateParameterSet" {
        $Path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Resolve-Path .).Path, $Create))
        if (! $Path.EndsWith(".accdb")) {
            $Path += ".accdb"
        }

        $emptyAccdb = @'
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
'@
        $compressedBytes = [Convert]::FromBase64String($emptyAccdb)
        $msIn = [System.IO.MemoryStream]::new($compressedBytes)
        $gzStream = [System.IO.Compression.GzipStream]::new($msIn, [IO.Compression.CompressionMode]::Decompress)
        $msOut = [System.IO.MemoryStream]::new()
        $gzStream.CopyTo($msOut)
        $gzStream.Close()
        [IO.File]::WriteAllBytes($Path, $msOut.ToArray())
        Write-Host -ForegroundColor Cyan "Created empty database at $Path"

        $f = $Fields | ForEach-Object {
            [PSCustomObject]@{
                Name = $_
                Type = "MEMO"
            }
        }

        Write-Host -ForegroundColor Cyan "Connecting to 'Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$Path;Persist Security Info=False;'"
        $cn = New-Object -ComObject ADODB.Connection
        $cn.Open("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$Path;Persist Security Info=False;")

        try {
            @(
                "CREATE TABLE [$Table] ($($f | ForEach-Object { "$($_.Name) $($_.Type)" } | Join-String -Separator ', '))"
                $Data |
                    Where-Object { $null -ne $_ } |
                    ForEach-Object {
                        "INSERT INTO [$Table] ($($f | ForEach-Object { $_.Name } | Join-String -Separator ', ')) VALUES ($($_ -split "," | ForEach-Object { "'$($_)'" } | Join-String -Separator ', '))"
                    }
            ) |
                ForEach-Object {
                    Write-Host -ForegroundColor Cyan "Execute: '$_'"
                    $cn.Execute($_) | Out-Null
                }
            Write-Host -ForegroundColor Green "All done."
        } finally {
            $cn.Close() | Out-Null
        }

    }
    default {}
}
