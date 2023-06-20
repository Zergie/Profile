#Requires -PSEdition Core
param (
    [Parameter(Mandatory=$true,
               Position=0,
               ParameterSetName="ParameterSetName",
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Path,

    [Parameter()]
    [ValidateSet("Landscape", "Portrait")]
    [string]
    $Orientation
)
begin {
    $word = New-Object -ComObject Word.Application
    # $word.visible = $true
}
process {
    $Path = (Resolve-Path $Path).ProviderPath
    $path_pdf = "$([System.IO.Path]::GetDirectoryName($Path))\$([System.IO.Path]::GetFileNameWithoutExtension($Path)).pdf"

    switch ([System.IO.Path]::GetExtension($Path))
    {
        ".sql" {
            Get-Content $Path |
             c:/tools/neovim/nvim-win64/bin/nvim.exe - +"set syntax=sql|set number!|set relativenumber!" +"TOhtml" +"w! C:\temp\temp.html" +"qa!"
            $Path = "C:\temp\temp.html"
        }
        ".article" {
            Get-Content $Path |
                c:/tools/neovim/nvim-win64/bin/nvim.exe - +"set syntax=article|set number!|set relativenumber!" +"TOhtml" +"w! C:\temp\temp.html" +"qa!"
            $Path = "C:\temp\temp.html"
        }
    }

    if ([System.IO.Path]::GetExtension($Path) -ne ".pdf") {
        Remove-Item $path_pdf -Force -ErrorAction SilentlyContinue

        $document = $word.Documents.Open("$Path")
        if ($PSBoundParameters.ContainsKey("Orientation")) {
            $document.PageSetup.Orientation = switch ($Orientation) {
                "Portrait"  { 0 }
                "Landscape" { 1 }
            }
        }

        $params = @{
            OutputFileName = $path_pdf
            ExportFormat = 17 ## wdExportFormatPDF
            Item = if ($document.Comments.Count -gt 0) {
                        7 ## wdExportDocumentWithMarkup
                    } else {
                        0 ## wdExportDocumentContent
                    }
        }
        $document.GetType().InvokeMember("ExportAsFixedFormat", [System.Reflection.BindingFlags]::InvokeMethod,
            $null,     ## Binder
            $document, ## Target
            ([Object[]]($params.Values)), ## providedArgs
            $null,  ## Modifiers
            $null,  ## Culture
            ([String[]]($params.Keys))  ## NamedParameters
        ) | Out-Null

        $document.Close($false) | Out-Null

        Get-ChildItem $path_pdf
    }
}
end {
    $word.Quit()
}
