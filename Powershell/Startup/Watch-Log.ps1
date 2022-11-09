[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true,
               Position = 0,
               ParameterSetName="TypeParameterSet")]
    [ValidateSet("AdminTool.log", "TauError.log")]
    [string]
    $Type,

    [Parameter(Mandatory = $true,
               Position = 1,
               ParameterSetName="PathParameterSet")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path
)

if ($Type.Length -gt 0) {
    $Path = @{
        "AdminTool.log" = "C:\Program Files (x86)\Tau-Office\AdminTool\AdminTool.log"
        "TauError.log"  = "C:\GIT\TauOffice\tau-office\bin\TauError.log"
    }[$Type]
}

Write-Host "Watching file: $path"
Get-ChildItem $path | Remove-Item
Set-Content $path ""

if ("TauError" -in $Path) {
    Get-Content -Path $path -Encoding 1252 -Wait | bat --paging never --style=plain --language log
} else {
    Get-Content -Path $path -Encoding utf8 -Wait | bat --paging never --style=plain --language log
}


