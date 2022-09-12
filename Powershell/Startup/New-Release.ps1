#Requires -PSEdition Core

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to one or more locations.")]
    [ValidateNotNullOrEmpty()]
    [string]
    $Date = (Get-Date).ToString("yyyy-MM-dd")
)
DynamicParam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Name
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Mandatory = $true
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        "$((Get-Date).Year-1)\Q4"
        "$((Get-Date).Year)\Q1"
        "$((Get-Date).Year)\Q2"
        "$((Get-Date).Year)\Q3"
        "$((Get-Date).Year)\Q4"
        "$((Get-Date).Year+1)\Q1"
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Name", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}
begin {
    $Name = $PSBoundParameters['Name']
    
    $dat = [datetime]::Parse($Date)
    $Branch = "release/$($dat.Year.ToString('0000'))-$($dat.Month.ToString('00'))-$($dat.Day.ToString('00'))" 
    Write-Debug "Branch: $Branch"

    $Year = $Name.SubString(0,4)
    Write-Debug "Year: $Year"
    
    $Quartal = $Name.SubString(6,1)
    Write-Debug "Quartal: $Quartal"
}
process {
    if ((Get-GitStatus).Branch -ne $Branch) {
        Write-Debug "Branch is not $Branch"
        git checkout -b $Branch
        git push --set-upstream origin $Branch
    }

    Get-ChildItem -Recurse -Filter *.yml |
        ForEach-Object {
            $file = $_.FullName

            Get-Content $file -Encoding utf8 |
                ForEach-Object {
                    $line=$_
                    if ($line -match "#.* or .*") {
                        if ($PSBoundParameters['Debug'].IsPresent) { Write-Host $line -ForegroundColor Red }

                        $m = $line | 
                                Select-String -Pattern "#(.*) or (.*)" | 
                                Select-Object -First 1 |
                                ForEach-Object { $_.Matches.Groups[1];$_.Matches.Groups[2] }
                        
                        $value_master = $m[0].Value.Trim()
                        $value_release = $m[1].Value.Trim()

                        $replacement = switch ($value_release) {
                            "SetupXXXX_Qx"       { "Setup${Year}_Q${Quartal}" }
                            "release/xxxx-xx-xx" { $Branch }
                            default              { $value_release }
                        }

                        $new_line = $line -replace "(?<!#\s*)${value_master}","${replacement}"
                        if ($PSBoundParameters['Debug'].IsPresent) { Write-Host $new_line -ForegroundColor Green }

                        $new_line
                    } else {
                        $line
                    }
                } | 
                Out-String |
                Set-Content $file -Encoding utf8
        }

    git add *.yml
    git commit -m "release ${Year}/${Quartal}"
}
end {}