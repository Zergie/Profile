#Requires -PSEdition Core
param (
    # Specifies a path to one or more locations.
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="ParameterSetName",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to one or more locations.")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Path
)
Begin {
    New-Alias -Name "Invoke-RestApi"  -Value "$PSScriptRoot\Invoke-RestApi.ps1"  -ErrorAction SilentlyContinue
    $Items = @()
}
Process{
    $Items += [pscustomobject]@{
                ID = $null
                Name = $null
                Path = ($Path | Resolve-Path).ProviderPath
              } |
              ForEach-Object {
                  $_.ID = [int]::Parse([System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($_.Path)))
                  $_.Name = [System.IO.Path]::GetFileName($_.Path)
                  $_
              }
}
End{


    Write-Progress -Activity "Downloading workitems"
    $missing_ids = $items.id
    while ($missing_ids.Count -gt 0) {
        while ($missing_ids.Count -gt 0) {
            $downloaded += Invoke-RestApi `
                                -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/workitems?ids={ids}&`$expand=relations&api-version=6.0" `
                                -Variables @{ ids = ($missing_ids | Select-Object -First 200) -join "," } |
                                ForEach-Object value
            $missing_ids = $missing_ids | Select-Object -Skip 200
        }
    }

    $indexes = @()
    $attachments = $downloaded |
                    ForEach-Object {
                        $w=$_
                        
                        $w.relations |
                            Add-Member -Type NoteProperty   -Name WorkItem -Value $w.id -ErrorAction SilentlyContinue -PassThru |
                            Add-Member -Type ScriptProperty -Name Id -Value {$this.url.Split('/') | Select-Object -Last 1} -ErrorAction SilentlyContinue -PassThru |
                            ForEach-Object {
                                $relation = $_

                                $index = $indexes | Where-Object workitem -eq $w.id | Select-Object -First 1
                                if ($null -eq $index) {
                                    $index = [pscustomobject]@{ workitem = $w.id; number = 0 }
                                    $indexes += $index
                                }

                                Add-Member -InputObject $relation -Type NoteProperty -Name Index -Value $index.number -ErrorAction SilentlyContinue -PassThru

                                $index.number += 1
                            }
                    } |
                    Where-Object rel -EQ "AttachedFile"
    Write-Progress -Activity "Downloading workitems" -Completed
    

    Write-Progress -Activity "Droping old attachments"
    $old_attachment = @()
    foreach ($item in $Items) {
        $old_attachment += $attachments |
                            Where-Object workitem -eq $item.id |
                            Where-Object { $_.attributes.name -eq $item.name }
    }
    $old_attachment |
        Sort-Object -Descending Index |
        ForEach-Object {
            try {
                Invoke-RestApi `
                        -Endpoint "PATCH https://dev.azure.com/{organization}/{project}/_apis/wit/workitems/{id}?api-version=6.0" `
                        -PatchBody @([ordered]@{
                            "op" = "remove"
                            "path" = "/relations/$($_.Index)"
                        }) `
                        -Variables @{ id = $_.workitem } |
                        Out-Null
            } catch {
            }
        }
    Write-Progress -Activity "Droping old attachments" -Completed

    Write-Progress -Activity "Uploading new attachments"
    foreach ($item in $Items) {
        $attachment = Invoke-RestApi `
                        -Endpoint "POST https://dev.azure.com/{organization}/{project}/_apis/wit/attachments?fileName={fileName}&api-version=6.0" `
                        -Variables @{ fileName = $item.Name } `
                        -RawBody ([System.IO.File]::ReadAllBytes("$($item.Path)"))

        Invoke-RestApi `
            -Endpoint "PATCH https://dev.azure.com/{organization}/{project}/_apis/wit/workitems/{id}?api-version=6.0" `
            -PatchBody @([ordered]@{
                "op" = "add"
                "path" = "/relations/-"
                "value" = [ordered]@{
                    "rel" = "AttachedFile"
                    "url" = $attachment.url
                    }
                }) `
            -Variables @{ id = $item.id } |
            Out-Null
    }
    Write-Progress -Activity "Uploading new attachments" -Completed
}
