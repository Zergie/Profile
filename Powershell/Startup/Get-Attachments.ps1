#Requires -PSEdition Core
[cmdletbinding(SupportsShouldProcess=$true)]
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
    ${Invoke-RestApi}  = "$PSScriptRoot\Invoke-RestApi.ps1"
}
process {
    $folder = "$((Get-Location).Path)\$WorkItem"
    Remove-Item "$folder" -Recurse -Force -ErrorAction SilentlyContinue

    $item = . ${Invoke-RestApi} `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/workitems?ids={ids}&`$expand=relations&api-version=6.0" `
                -Variables @{ ids = $WorkItem } |
                ForEach-Object value

    $attachments = $item.relations |
                    Where-Object rel -EQ "AttachedFile" |
                    Where-Object { $_.attributes.name -match $Filter } |
                    Add-Member -Type ScriptProperty -Name Id -Value {$this.url.Split('/') | Select-Object -Last 1} -ErrorAction SilentlyContinue -PassThru

    foreach ($attachment in $attachments) {
        New-Item "$folder" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

        $temp_file = "$folder\$($attachment.attributes.Name)"
        if ($PSCmdlet.ShouldProcess($attachment.id, "Invoke-RestApi")) {
            . ${Invoke-RestApi} `
                -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/attachments/{id}?api-version=6.0" `
                -Variables @{ id = $attachment.id } `
                -OutFile $temp_file
            Get-ChildItem $temp_file
        }
    }
}
