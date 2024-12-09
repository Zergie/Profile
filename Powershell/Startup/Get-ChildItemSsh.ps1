[cmdletbinding()]
param(
    [Parameter()]
    [switch]
    $l
)
dynamicparam {
    $file = "$env:TEMP\Get-ChildItemSsh.Json"
    $shouldUpdateJson = try { ((Get-Date) - (Get-ChildItem $env:TEMP -Filter Get-ChildItemSsh.json).LastWriteTime).TotalDays -gt 15 } catch { $true }
    if ($shouldUpdateJson) {
        ssh u266601-sub2@u266601-sub2.your-storagebox.de -p23 tree -d -f -i -L 4 |
            Where-Object { $_.StartsWith("./") } |
            ForEach-Object { $_.Substring(2) } |
            ConvertTo-Json |
            Set-Content $file
    }
    $values = Get-Content $file |
        ConvertFrom-Json

    Set-Alias "New-DynamicParameter" "$PSScriptRoot\New-DynamicParameter.ps1"
    @(
        [pscustomobject]@{
            Position = 0
            Type = [string]
            Name = "Path"
            ValidateSet = $values
        }
    ) | New-DynamicParameter
}
process {
    ssh u266601-sub2@u266601-sub2.your-storagebox.de -p23 ls $(if ($L) { "-l -h" }) $PSBoundParameters.Path
}
