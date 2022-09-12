#Requires -PSEdition Core

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="ParameterSetName",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [Alias("Id")]
    [ValidateNotNullOrEmpty()]
    [int]
    $WorkItem,

    [Parameter(Mandatory=$false,
               ParameterSetName="ParameterSetName",
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [string]
    $Filter = "^(?!(#\d+_)?Rückmeldung).+\.(docx|pdf)$"
)
begin {
    New-Alias -Name "Invoke-RestApi" -Value "$PSScriptRoot\Invoke-RestApi.ps1"
}
process {
    $folder = "$((Get-Location).Path)\$WorkItem"
    Remove-Item "$folder" -Recurse -Force -ErrorAction SilentlyContinue

    $item = Invoke-RestApi `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/workitems?ids={ids}&`$expand=relations&api-version=6.0" `
                -Variables @{ ids = $WorkItem } |
                ForEach-Object value
    
    $attachments = $item.relations |
                    Where-Object rel -EQ "AttachedFile" |
                    Where-Object { $_.attributes.name -match $Filter } |
                    Add-Member -Type ScriptProperty -Name Id -Value {$this.url.Split('/') | Select-Object -Last 1} -ErrorAction SilentlyContinue -PassThru
    
    foreach ($attachment in $attachments) {
        New-Item "$folder" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        
        $bytes = [byte[]][char[]](
                    Invoke-RestApi `
                        -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/attachments/{id}?api-version=6.0" `
                        -Variables @{ id = $attachment.id }
                )
        
        $temp_file = "$folder\$($attachment.attributes.Name)"
        [System.IO.File]::WriteAllBytes($temp_file, $bytes)

        Get-ChildItem $temp_file
    }
}