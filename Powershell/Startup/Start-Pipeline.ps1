#Requires -PSEdition Core
param(
    [Parameter(Mandatory=$false)]
    [switch]
    $All,

    [Parameter(Mandatory=$false)]
    [ValidateSet(1,2,3)]
    [int[]]
    $Stage,

    [Parameter(Mandatory=$false)]
    [switch]
    $SetupsOnly
)
DynamicParam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Name
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.ParameterSetName = "SpecificPipelineParameterSet"
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute((
        & "$PSScriptRoot\Invoke-RestApi.ps1" -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/pipelines?api-version=6.0-preview.1" |
                ForEach-Object { $_.value.name }
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Name", [string[]], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    # param Branch
    # $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    # $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    # $ParameterAttribute.Position = 1
    # $AttributeCollection.Add($ParameterAttribute)

    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 1
    $ParameterAttribute.ParameterSetName = "SpecificPipelineParameterSet"
    $AttributeCollection.Add($ParameterAttribute)
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 1
    $ParameterAttribute.ParameterSetName = "AllPipelinesParameterSet"
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute((
        git branch --remote --list |
            ForEach-Object { $_ -split '/' | Select-Object -Skip 1 | Join-String -Separator '/'  }
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Branch", [string[]], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}
begin {
    Set-Alias -Name "Invoke-RestApi" -Value "$PSScriptRoot\Invoke-RestApi.ps1"

    # param Branch
    if ($SetupsOnly) {
        $PSBoundParameters['Name'] = @("TauOffice Setup")

        $Branch = @("master")
        $Branch += git branch --remote --list |
                    ForEach-Object { $_ -split '/' | Select-Object -Skip 1 | Join-String -Separator '/'  } |
                    Where-Object { $_ -like "release/*" } |
                    Sort-Object -Descending |
                    Select-Object -First 1
    } else {
        $Branch = $PsBoundParameters['Branch']
        if ($null -eq $Branch) {
            $Branch = (Get-GitStatus).Branch
        }
    }

    # param Name
    if ($All) {
        $Stage = $(1,2,3)
    }

    if ($All) {
        $Name = @{}

        if (1 -in $Stage) {
            $Name.Add("Stage 1", @(
                [pscustomobject]@{ id= 45; name= "TauOffice Plugins" }
                [pscustomobject]@{ id= 51; name= "TauOffice Controls" }
                [pscustomobject]@{ id= 44; name= "TauOffice Utils" }
            ))
        }
        if (2 -in $Stage) {
            $Name.Add("Stage 2", @(
                [pscustomobject]@{ id= 40; name= "AdminTool" }
                [pscustomobject]@{ id= 35; name= "TauOffice MDE" }
                [pscustomobject]@{ id= 46; name= "TauOffice Basisstatistik" }
            ))
        }
        if (3 -in $Stage) {
            $Name.Add("Stage 3", @(
                [pscustomobject]@{ id= 41; name= "TauOffice Setup" }
            ))
        }

        $Name = [pscustomobject]$Name
    } else  {
        $Name = [pscustomobject]@{
            "Stage 1"= Invoke-RestApi -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/pipelines?api-version=6.0-preview.1" |
                            ForEach-Object { $_.value } |
                            ForEach-Object { [pscustomobject]@{ id= $_.Id; name= $_.name } } |
                            Where-Object { $_.name -in $PSBoundParameters['Name'] } |
                            Where-Object Name -NotLike *setup*
            "Stage 2"= Invoke-RestApi -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/pipelines?api-version=6.0-preview.1" |
                            ForEach-Object { $_.value } |
                            ForEach-Object { [pscustomobject]@{ id= $_.Id; name= $_.name } } |
                            Where-Object { $_.name -in $PSBoundParameters['Name'] } |
                            Where-Object Name -Like *setup*
        }
    }

    # helper functions
    function Start-WaitingForPipelineToFinish {
        param (
            [Parameter(Mandatory=$true, Position=0)]
            [object]
            $running_pipelines
        )

        Write-Host
        Write-Host "waiting for pipelines to finish .."

        while ($running_pipelines.Count -gt 0) {
            Start-Sleep -Seconds 10

            $running_pipelines = $running_pipelines |
                ForEach-Object {
                    try {
                        $run = Invoke-RestApi `
                                    -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/pipelines/{pipelineId}/runs/{runId}?api-version=6.0-preview.1" `
                                    -Variables @{ pipelineId= $_.pipeline.id ; runId= $_.id }
                    } catch {
                        Write-Error $_
                    }

                    switch ($run.state) {
                        "completed"  {
                            $duration = ($run.finishedDate - $run.createdDate)
                            $duration = $duration.Hours, $duration.Minutes, $duration.Seconds | ForEach-Object { $_.ToString("00") } | Join-String -Separator ":"

                            $color = if ($run.result -eq "Succeeded") { "Green" } else { "Red" }
                            Write-Host "$($run.pipeline.name) $($run.result) ($($run.name) / ran $duration)" -ForegroundColor $color
                        }
                        default {
                            $run
                        }
                    }
                }
        }
    }
}
process {
    Write-Host
    Write-Host "getting running pipelines .."
    $running_pipelines = @{result=@()}
    Invoke-RestApi `
        -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/pipelines?api-version=6.0-preview.1" |
        ForEach-Object value |
        ForEach-Object  `
            -Parallel {
                & "$($using:PSScriptRoot)\Invoke-RestApi.ps1" `
                        -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/pipelines/{pipelineId}/runs?api-version=6.0-preview.1" `
                        -Variables @{pipelineId=$_.id} |
                    ForEach-Object value |
                    Where-Object state -EQ "inProgress" |
                    ForEach-Object { ($using:running_pipelines).result += $_ }
            }
    $running_pipelines = $running_pipelines.result

    if ($null -ne $running_pipelines) {
        $running_pipelines |
            ForEach-Object {
                Write-Host "$($_.pipeline.name) $($_.name) [" -NoNewline
                Write-Host "running" -ForegroundColor Blue -NoNewline
                Write-Host "]"
            }
    }
    Start-WaitingForPipelineToFinish $running_pipelines


    $stages = $Name | Get-Member -MemberType NoteProperty | ForEach-Object Name | Sort-Object
    foreach ($item in $stages) {
        Write-Host
        Write-Host "== $item of $($stages.count) =="

        $running_pipelines = @()
        foreach ($pipeline in $Name.$item) {
            foreach ($b in $Branch) {
                Write-Host "queuing $($pipeline.name) for " -NoNewline
                Write-Host $b -ForegroundColor Cyan -NoNewline
                Write-Host " .."

                $running_pipelines += Invoke-RestApi `
                                        -Endpoint "POST https://dev.azure.com/{organization}/{project}/_apis/pipelines/{pipelineId}/runs?api-version=6.0-preview.1" `
                                        -Variables @{ pipelineId= $pipeline.id } `
                                        -Body @{
                                            resources= @{
                                                repositories= @{
                                                    self= @{
                                                        refName= "refs/heads/$b"
                                                    }
                                                }
                                            }
                                        }
            }
        }
        Start-WaitingForPipelineToFinish $running_pipelines
    }
}
end {
    Write-Host "All done."
}
