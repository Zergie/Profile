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
    $word = $null
    $powerpoint = $null
}
process {
    $Path = (Resolve-Path $Path).ProviderPath
    $path_pdf = "$([System.IO.Path]::GetDirectoryName($Path))\$([System.IO.Path]::GetFileNameWithoutExtension($Path)).pdf"

    switch ([System.IO.Path]::GetExtension($Path))
    {
        ".sql" {
            Get-Content $Path |
                c:/tools/neovim/nvim-win64/bin/nvim.exe - +"set syntax=sql|set number!|set relativenumber!|set background=light" +"TOhtml" +"w! C:\temp\temp.html" +"qa!"
            Clear-Host
            $Path = "C:\temp\temp.html"
        }
        ".article" {
            Get-Content $Path |
                c:/tools/neovim/nvim-win64/bin/nvim.exe - +"set syntax=article|set number!|set relativenumber!|set background=light" +"TOhtml" +"w! C:\temp\temp.html" +"qa!"
            Clear-Host
            $Path = "C:\temp\temp.html"
        }
    }

    if ([System.IO.Path]::GetExtension($Path) -ne ".pdf") {
        Remove-Item $path_pdf -Force -ErrorAction SilentlyContinue

        switch -Regex ([System.IO.Path]::GetExtension($Path))
        {
            "\.(doc|docx|html)$"  {
                if (-not $word) { $word = New-Object -ComObject Word.Application }

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
                try {
                    $document.GetType().InvokeMember("ExportAsFixedFormat", [System.Reflection.BindingFlags]::InvokeMethod,
                        $null,     ## Binder
                        $document, ## Target
                        ([Object[]]($params.Values)), ## providedArgs
                        $null,  ## Modifiers
                        $null,  ## Culture
                        ([String[]]($params.Keys))  ## NamedParameters
                    ) | Out-Null
                } catch {
                }

                $document.Close($false) | Out-Null

            }
            "\.(ppt|pptx)$" {
                if (-not $powerpoint) { $powerpoint = New-Object -ComObject PowerPoint.Application }
                $presentation = $powerpoint.Presentations.Open("$Path", $false, $false, $false)
                if ($PSBoundParameters.ContainsKey("Orientation")) {
                    $presentation.PageSetup.SlideOrientation = switch ($Orientation) {
                        "Portrait"  { 2 } ## ppSlideOrientationPortrait
                        "Landscape" { 1 } ## ppSlideOrientationLandscape
                    }
                }
                $presentation.SaveAs($path_pdf, 32) ## ppSaveAsPDF
                $presentation.Close()
            }
            default {
                Write-Warning "Unsupported file type: $Path"
                return
            }
        }

        Get-ChildItem $path_pdf -ErrorAction SilentlyContinue
    }
}
end {
    if ($word) { $word.Quit() }
    if ($powerpoint) { $powerpoint.Quit() }
}
