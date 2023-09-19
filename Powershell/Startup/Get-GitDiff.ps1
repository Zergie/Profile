[cmdletbinding()]
param(
    [Parameter(Mandatory=$true,
               Position=0,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path
)
begin {
    $ErrorActionPreference = 'Stop'
    $Pathes = @()
}
process {
    $Pathes += "`"$((Resolve-Path $Path).Path)`""
}
end {
    "git log --follow --pretty=format:'%h - %s%d' --abbrev-commit -- $($Pathes | Join-String)" |
        ForEach-Object {
            Write-Host -ForegroundColor Cyan $_
            Invoke-Expression $_
        } -OutVariable Commits |
        . $PSScriptRoot/Create-Menu.ps1 -OutVariable Index |
        Out-Null

    $Index = [int]$Index[0]
    $commitA = $Commits[$Index + 1].Split(" - ")[0]
    $commitB = $Commits[$Index].Split(" - ")[0]

    # Write-Host
    # Write-Host -ForegroundColor Cyan "left  > $($Commits[$Index + 1])"
    # Write-Host -ForegroundColor Cyan "right > $($Commits[$Index])"
    # Write-Host

    "git difftool $commitA $commitB -- $($Pathes | Join-String)" |
        ForEach-Object {
            Write-Host -ForegroundColor Cyan $_
            Invoke-Expression $_
        }
}
