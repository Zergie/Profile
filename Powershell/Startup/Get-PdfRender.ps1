[cmdletbinding()]
param(
    [Parameter(Mandatory, Position=0, ValueFromPipeline)]
    [ValidateScript({ $_.EndsWith(".pdf") })]
    [string]
    $Path,

    [Parameter()]
    [ValidateSet('txt', 'png')]
    [string]
    $As = "png",

    [Parameter()]
    [string]
    $OutFile,

    [Parameter()]
    [ValidateRange(1, [int]::MaxValue)]
    [int]
    $Page = 1,

    [Parameter()]
    [ValidateRange(1, [int]::MaxValue)]
    [int]
    $Count = 1
)
Begin {
    if ($As -eq 'txt' -and (
            $PSBoundParameters.ContainsKey('Page') -or
            $PSBoundParameters.ContainsKey('Count'))) {
        throw "Page and Count parameters are not supported for text output."
    }

    try {
        $gs = Get-ChildItem "C:\Program Files\gs\*\bin\gswin64.exe" |
            Get-Command |
            Sort-Object Version -Bottom 1
        if (-not $gs) { throw "Ghostscript not found" }
    } catch {
        Write-Host -ForegroundColor Red "Ghostscript is not installed! Install it with:"
        Write-Host -ForegroundColor Red ""
        Write-Host -ForegroundColor Red "    choco install Ghostscript"
        exit 1
    }

    if ((Test-Path "$PSScriptRoot\..\secrets.json")) {
        $password = Get-Content "$PSScriptRoot/../secrets.json" |
            ConvertFrom-Json |
            ForEach-Object pdf_documents |
            ForEach-Object Password
    }
}
Process {
    $sourcePath = (Get-Item $Path).FullName
    $temp = "$env:temp\$([System.IO.Path]::GetRandomFileName()).pdf"
    Copy-Item $sourcePath $temp
    $file = Get-Item $temp

    $renderDir = $null
    try {
        if ($As -eq 'png') {
            $outDir = if ($OutFile.Length -gt 0) {
                [System.IO.Path]::GetDirectoryName(
                    [System.IO.Path]::GetFullPath(
                        [System.IO.Path]::Combine((Get-Location).Path, $OutFile)))
            } else {
                (Get-Item $sourcePath).DirectoryName
            }
            $outName = if ($OutFile.Length -gt 0) {
                [System.IO.Path]::GetFileName($OutFile)
            } else {
                [System.IO.Path]::ChangeExtension((Get-Item $sourcePath).Name, 'png')
            }
            $finalPath = [System.IO.Path]::Combine($outDir, $outName)

            $renderDir = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $renderDir | Out-Null

            $lastPage  = $Page + $Count - 1
            $gsArgs    = @(
                "-dBATCH"
                "-dNOPROMPT"
                "-dNOPAUSE"
                "-dQUIET"
                "-sDEVICE=png16m"
                "-dTextAlphaBits=4"
                "-r300"
                "-dFirstPage=$Page"
                "-dLastPage=$lastPage"
                "-sPDFPassword=$password"
                "-o `"pg%d.png`""
                " `"$($file.FullName)`""
            )
            $gsArgsLog = ($gsArgs | Join-String -Separator " ").Replace($password, "*")
            Write-Debug "gs $gsArgsLog"

            Start-Process -FilePath $gs.Source -ArgumentList $gsArgs -WorkingDirectory $renderDir -Wait -WindowStyle Hidden

            $renderedPages = @(Get-ChildItem $renderDir -Filter "pg*.png" |
                Sort-Object { [int]($_.BaseName -replace '^pg', '') })

            if ($renderedPages.Count -eq 0) {
                throw "Page $Page does not exist in '$sourcePath'."
            }

            Add-Type -AssemblyName System.Drawing

            $images      = @($renderedPages | ForEach-Object { [System.Drawing.Image]::FromFile($_.FullName) })
            $totalHeight = [int]($images | Measure-Object -Property Height -Sum).Sum
            $maxWidth    = [int]($images | Measure-Object -Property Width  -Maximum).Maximum

            $bitmap = New-Object System.Drawing.Bitmap($maxWidth, $totalHeight)
            $bitmap.SetResolution(300, 300)
            $g = [System.Drawing.Graphics]::FromImage($bitmap)
            $g.Clear([System.Drawing.Color]::LightGray)

            $y = 0
            foreach ($img in $images) {
                $x        = [int](($maxWidth - $img.Width) / 2)
                $destRect = New-Object System.Drawing.Rectangle($x, $y, $img.Width, $img.Height)
                $srcRect  = New-Object System.Drawing.Rectangle(0, 0, $img.Width, $img.Height)
                $g.DrawImage($img, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
                $y += $img.Height
            }

            $g.Dispose()
            $images | ForEach-Object { $_.Dispose() }
            $bitmap.Save($finalPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $bitmap.Dispose()

            [pscustomobject]@{
                FullName  = $sourcePath
                Converted = $finalPath
            }
        } else {
            # txt mode — existing behavior unchanged
            $fileAs = [pscustomobject]@{
                FullName  = $null
                Name      = $(
                    if ($OutFile.Length -gt 0) {
                        [System.IO.Path]::GetFileName($OutFile)
                    } else {
                        [System.IO.Path]::ChangeExtension($file.Name, $As)
                    })
                Directory = $(
                    if ($OutFile.Length -gt 0) {
                        [System.IO.Path]::GetDirectoryName(
                            [System.IO.Path]::GetFullPath(
                                [System.IO.Path]::Combine((Get-Location).Path, $OutFile)
                            )
                        )
                    } else {
                        ""
                    })
            }
            $fileAs.FullName = [System.IO.Path]::Combine($fileAs.Directory, $fileAs.Name)
            Write-Debug "fileAs: $($fileAs | ConvertTo-Json)"

            [pscustomobject]@{
                FilePath         = $gs.Source
                WorkingDirectory = $file.Directory
                ArgumentList     = @(
                    "-dBATCH"
                    "-dNOPROMPT"
                    "-dNOPAUSE"
                    "-dQUIET"
                    "-sDEVICE=txtwrite"
                    "-dTextAlphaBits=4"
                    "-r300"
                    "-sPDFPassword=$password"
                    "-o `"$($fileAs.Name)`""
                    " `"$($file.Name)`""
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
                    $content = Get-Content $output -Encoding utf8
                    $cmd = "Remove-Item `"$($output.FullName)`" -Force"
                    Write-Debug $cmd
                    Invoke-Expression $cmd

                    [pscustomobject]@{
                        FullName  = $sourcePath
                        Converted = $content
                    }
                }
        }
    }
    finally {
        Remove-Item $temp -ErrorAction SilentlyContinue
        if ($renderDir) {
            Remove-Item $renderDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
