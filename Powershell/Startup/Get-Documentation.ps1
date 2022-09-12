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
    $WorkItem
)
begin {
    New-Alias -Name "Invoke-RestApi" -Value "$PSScriptRoot\Invoke-RestApi.ps1"
}
process {
    $temp_file = "$((Get-Location).Path)\$WorkItem.docx"


    $item = Invoke-RestApi `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/workitems?ids={ids}&`$expand=relations&api-version=6.0" `
                -Variables @{ ids = $WorkItem } |
                ForEach-Object value
    
    $attachment = $item.relations |
                    Where-Object rel -EQ "AttachedFile" |
                    Where-Object { $_.attributes.name -in "Rückmeldung.docx","Aufgabenbeschreibung_Rueckmeldung.docx" } |
                    Add-Member -Type ScriptProperty -Name Id -Value {$this.url.Split('/') | Select-Object -Last 1} -ErrorAction SilentlyContinue -PassThru |
                    Select-Object -First 1
    
    if ($null -eq $attachment) {
        Write-Host "No documentation found."
    } else {
        $bytes = [byte[]][char[]](
                    Invoke-RestApi `
                        -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/attachments/{id}?api-version=6.0" `
                        -Variables @{ id = $attachment.id }
                )
        [System.IO.File]::WriteAllBytes($temp_file, $bytes)
        Invoke-Item $temp_file
    }
}