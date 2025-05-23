[cmdletbinding()]
param(
    [Parameter(Mandatory, Position=0, ValueFromPipeline)]
    [ValidateScript({ (Get-Item $_).Extension -eq ".pdf" })]
    [string]
    $Path,

    [Parameter()]
    [ValidateSet('txt', 'png')]
    [string]
    $As = "png",

    [Parameter()]
    [string]
    $OutFile
)
Begin {
    try {
        $gs = Get-Command "C:\Program Files\gs\*\bin\gswin64.exe" |
            Sort-Object Version -Bottom 1
    } catch {
        Write-Host -ForegroundColor Red "Ghostscript is not installed! Install it with:"
        Write-Host -ForegroundColor Red ""
        Write-Host -ForegroundColor Red "    choco install Ghostscript"
    }

    if ((Test-Path "$PSScriptRoot\..\secrets.json")) {
        $password = Get-Content "$PSScriptRoot/../secrets.json" |
            ConvertFrom-Json |
            ForEach-Object pdf_documents |
            ForEach-Object Password
    }
}
Process {
    # @(
    #     [pscustomobject]@{
    #         Path=$Path
    #         As=$As
    #         OutFile=$OutFile
    #         gs=$gs
    #     }
    # ) |
    # ConvertTo-Json -Depth 2 |
    # Set-Content -Path "$env:TEMP\Get-PdfRender.log"

    $file = Get-Item $Path
    $fileAs = [pscustomobject]@{
        FullName  = $null
        Name      = $(
            if ($OutFile.Length -gt 0) {
                [System.IO.Path]::GetFileName($OutFile)
            } else {
                $file.Name
            })
        Directory = $(
            if ($OutFile.Length -gt 0) {
                [System.IO.Path]::GetDirectoryName(
                    [System.IO.Path]::GetFullPath(
                        [System.IO.Path]::Combine((Get-Location).Path, $OutFile)
                    )
                )
            } elseif ($As -eq "txt") {
                ""
            } else {
                $file.Directory.FullName
            })

    }
    $fileAs.FullName = [System.IO.Path]::Combine($fileAs.Directory, $fileAs.Name)
    [pscustomobject]@{
        FilePath         = $gs.Source
        WorkingDirectory = $file.Directory
        ArgumentList     = @(
            "-dBATCH"
            "-dNOPROMPT"
            "-dNOPAUSE"
            "-dQUIET"
            $(switch ($As){
                "png" { "-sDEVICE=png16m" }
                "txt" { "-sDEVICE=txtwrite" }
            })
            "-dTextAlphaBits=4"
            "-r300"
            "-sPDFPassword=$password"
            "-o $($fileAs.Name)"
            $file.Name
        )
        ArgumentListWithoutPassword = ""
        InFile           = $file
        OutFile          = $fileAs
    } |
        ForEach-Object {
            $_.ArgumentListWithoutPassword = ($_.ArgumentList | Join-String -Separator " ").Replace($password, "*")
            $_
        } |
        ForEach-Object {
            Write-Debug "gs $($_.ArgumentListWithoutPassword)"
            Start-Process -FilePath $_.FilePath -ArgumentList $_.ArgumentList -WorkingDirectory $_.WorkingDirectory -Wait -WindowStyle Hidden

            $output = Get-Item "$([System.IO.Path]::Combine($_.WorkingDirectory, $_.OutFile.Name))"
            if ($_.OutFile.Directory.Length -eq 0) {
                $content = Get-Content $output -Encoding utf8
                $cmd = "Remove-Item `"$($output.FullName)`" -Force"
                Write-Debug $cmd
                Invoke-Expression $cmd

                [pscustomobject]@{
                    FullName  = $_.InFile.FullName
                    Converted = $content
                }
            } else {
                if ($output.FullName -ne $_.OutFile.FullName) {
                    $cmd = "Move-Item `"$($output.FullName)`" `"$($_.OutFile.FullName)`" -Force"
                    Write-Debug $cmd
                    Invoke-Expression $cmd
                }

                [pscustomobject]@{
                    FullName  = $_.InFile.FullName
                    Converted = $_.OutFile.FullName
                }
            }
        }
}
