#Requires -PSEdition Core
param (
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="ParameterSetName",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [Alias("PSPath")]
    [ValidateScript({ (Get-ChildItem $_).Extension -in @(".ACF",".ACR") })]
    [string[]]
    $Path
)
begin {
}
process {
    $Path = (Resolve-Path $Path).ProviderPath

    $module = @{}
    $continue = $true
    Get-Content $Path |
        ForEach-Object {
            $continue = $continue -and $_ -ne "CodeBehindForm"
            if ($continue) {
                $_
            }
        } |
        ForEach-Object {
            if ($_ -match "^\s*Begin(\s|$)") {
                [pscustomobject]$module
                $module = @{
                    Tag = $_
                }
            } elseif ($_ -match "^\s*[^=]+=\s*`".*`"") {
                $match  = $_ | Select-String "\s*(?<name>[^=]+)\s?=\s*`"(?<value>.*)`""
                $name   = ($match.Matches.Groups | Where-Object Name -eq "name").Value.Trim()
                $value  = ($match.Matches.Groups | Where-Object Name -eq "value").Value.Trim('"')
                $module.$name = $value
            } elseif ($_ -match "^\s*[^=]+=.*") {
                $match  = $_ | Select-String "\s*(?<name>[^=]+)\s?=(?<value>.*)"
                $name   = ($match.Matches.Groups | Where-Object Name -eq "name").Value.Trim()
                $value  = ($match.Matches.Groups | Where-Object Name -eq "value").Value.Trim()
                $module.$name = $value
            }
        }

}
end {
}
