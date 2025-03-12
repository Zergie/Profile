[cmdletbinding()]
Param(
    [Parameter(Mandatory=$false,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [switch]
    $AsJob
)
dynamicparam {
    Set-Alias "Invoke-Ssh" "$PSScriptRoot\Invoke-Ssh.ps1"
    $config = [pscustomobject]@{
        local_folder = 'C:\Dokumente\Daten'
    }
    $shouldUpdateJson = try { ((Get-Date) - (Get-ChildItem $env:TEMP -Filter databases.json).LastWriteTime).TotalDays -gt 15 } catch { $true }

    if ($shouldUpdateJson) {
        @(
            Invoke-Ssh tree -if --noreport -L 2 Testdatenbanken |
                Where-Object { $_ -like '*.zip' } |
                ForEach-Object { "ssh://$($_.SubString("Testdatenbanken/".Length))" }

            Invoke-Ssh ls Installationsdatenbanken |
                ForEach-Object {
                        "ssh://Installationsdatenbanken/$_"
                } |
                Where-Object { $_ -notlike '*.*' }

        ) |
            ConvertTo-Json |
            Out-File -Encoding UTF8 "$env:TEMP/databases.json"
    }

    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Path
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $true
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        @(
            Get-ChildItem -Directory "$($config.local_folder)" | Where-Object (Test-Path ("$_\*.bak"))
            Get-ChildItem -File "$($config.local_folder)\*.zip"
            Get-ChildItem -File "$($config.local_folder)\*.7z"
        ) | ForEach-Object {
            ".\" + $_.FullName.Substring("$($config.local_folder)\".Length)
            "./" + $_.FullName.Substring("$($config.local_folder)\".Length)
        }

        Get-Content "$env:TEMP/databases.json" -Encoding UTF8 | ConvertFrom-Json
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Path", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}
process {
    $Path = $PSBoundParameters['Path']

    if ($Path.StartsWith(".")) {
        $Path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine("C:\Dokumente\Daten", $Path))
    }

    if ($PSDefaultParameterValues["*:Database"] -ne "master") {
        $old = $PSDefaultParameterValues["*:Database"]
        Set-SqlDatabase master
    }

    $result = @{}
    $p = $PSBoundParameters.GetEnumerator() | ForEach-Object -Process { $result.Add($_.Key, $_.Value) } -End{ $result }
    $p.Remove("Path")

    if (!$Path.StartsWith(".")) {
        $p["SshUser"] = $config.user
        $p["SshHost"] = $config.host
        $p["SshPort"] = $config.port
    }

    if ($AsJob) {
        $p.Remove('AsJob')
        Start-ThreadJob {
            param($dockerScript, $Path, $p)
            & $dockerScript -Install $Path @p
        } -ArgumentList $dockerScript, $Path, $p
    } else {
        & $dockerScript -Install $Path @p

        if ($null -ne $old) {
            Set-SqlDatabase $old
        }
    }
}
