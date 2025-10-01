[cmdletbinding()]
Param(
    [Parameter()]
    [switch]
    $Refresh,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $Url = "trident.local"
)
dynamicparam {
    $shouldUpdateJson = try { ((Get-Date) - (Get-ChildItem $env:TEMP -Filter klipper-objects.json).LastWriteTime).TotalDays -gt 15 } catch { $true }

    if ($shouldUpdateJson) {
        (Invoke-RestMethod "http://trident.local/printer/objects/list").result.objects |
            ConvertTo-Json |
            Out-File -Encoding UTF8 "$env:TEMP/klipper-objects.json"
    }

    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Object
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $false
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        Get-ChildItem $env:TEMP -Filter klipper-objects.json |
        Get-Content -Encoding utf8 |
        ConvertFrom-Json
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Object", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}
process {
    $Object = $PSBoundParameters['Object']

    if ($Refresh) {
        (Invoke-RestMethod "http://$url/printer/objects/list").result.objects |
            ConvertTo-Json |
            Out-File -Encoding UTF8 "$env:TEMP/klipper-objects.json"
    } else {
        (Invoke-RestMethod "http://$url/printer/objects/query?$object").result.status |
        ForEach-Object $Object
    }
}
