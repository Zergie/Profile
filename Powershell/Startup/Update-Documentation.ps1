#Requires -PSEdition Core

[CmdletBinding()]
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
    New-Alias -Name "Invoke-RestApi" -Value "$PSScriptRoot\Invoke-RestApi.ps1"
    $Items = @()
}
Process{
    $Items += [PSCustomObject]@{
        ID = [int]::Parse([System.IO.Path]::GetFileNameWithoutExtension($Path))
        Path = ($Path | Resolve-Path).ProviderPath
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
    Write-Progress -Activity "Downloading workitems" -Completed



    Write-Progress -Activity "Downloading attachments"
    $attachments = $downloaded | 
                        ForEach-Object { 
                            $w=$_
                            $w.relations |
                                Add-Member -Type NoteProperty   -Name WorkItem -Value $w.Id -ErrorAction SilentlyContinue -PassThru |
                                Add-Member -Type ScriptProperty -Name Id -Value {$this.url.Split('/') | Select-Object -Last 1} -ErrorAction SilentlyContinue -PassThru
                        } |
                        Where-Object rel -EQ "AttachedFile" |
                        Where-Object { $_.attributes.name -EQ "Aufgabenbeschreibung_Rueckmeldung.docx" }
    $index = 0
    $count = $attachments.Count

    foreach ($item in $attachments) {
        Write-Progress -Activity "Downloading attachments" -PercentComplete (100 * $index / $count)

        $stream = [IO.MemoryStream]::new([byte[]][char[]](
                    Invoke-RestApi `
                        -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/attachments/{id}?api-version=6.0" `
                        -Variables @{ id = $item.id }
                ))
        $hash =  Get-FileHash -InputStream $stream | ForEach-Object Hash
        
        Add-Member -InputObject $item -MemberType NoteProperty -Name "Hash" -Value $hash
        
        $index += 1
    }
    Write-Progress -Activity "Downloading attachments" -Completed


    
    Write-Progress -Activity "Updateing workitems"
    $index = 0
    $count = $Items.Count
    foreach ($item in $Items) {
        Write-Progress -Activity "Updateing workitems" -CurrentOperation "workitem $($item.id)" -PercentComplete (100 * $index / $count)

        $upload = $false
        $old_attachment = $attachments | Where-Object { $_.WorkItem -EQ $item.id }
        $hash_remote = $old_attachment.Hash
        if ($null -eq $hash_remote) {
            $hash_local = $null
        } else {
            $hash_local = Get-FileHash -Path ($item.Path) | ForEach-Object Hash
        }

        if ($null -eq $hash_remote) {
            $upload = $true
        } elseif ($hash_remote -eq $hash_local) {
            $upload = $false
        } else {
            $upload = $true
        }
        
        if ($upload) {
            Write-Host "Updating workitem $($item.id)"            
            if ($null -ne $old_attachment) {
                $index = 0
                $relations = $downloaded | 
                                Where-Object Id -EQ $item.id | 
                                Select-Object -First 1 |
                                ForEach-Object relations
                foreach ($rel in $relations) {
                    if ($rel.url -eq $old_attachment.url) {
                        break
                    }
                    $index++
                }
                
                Invoke-RestApi `
                    -Endpoint "PATCH https://dev.azure.com/{organization}/{project}/_apis/wit/workitems/{id}?api-version=6.0" `
                    -PatchBody @([ordered]@{
                        "op" = "remove"
                        "path" = "/relations/$index"
                    }) `
                    -Variables @{ id = $item.id } | 
                    Out-Null
            }

            $attachment = Invoke-RestApi `
                            -Endpoint "POST https://dev.azure.com/{organization}/{project}/_apis/wit/attachments?fileName={fileName}&api-version=6.0" `
                            -Variables @{ fileName = "Aufgabenbeschreibung_Rueckmeldung.docx" } `
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

        } else {
            Write-Host "Skipped workitem $($item.id)"
        }
        $index++
        Remove-Item $item.Path
    }
    Write-Progress -Activity "Updateing workitems" -Completed
}