[cmdletbinding()]
param(
    [Parameter(Mandatory,
               Position=0,
               ValueFromPipeline)]
    [ValidateScript({ (Get-Item $_).Extension -eq ".pdf" })]
    [string]
    $Path,

    [Parameter()]
    [string]
    $OutFile
)

try {
    $gs = Get-Command "C:\Program Files\gs\gs10.05.0\bin\gswin64.exe"
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

$file = Get-Item $Path
[pscustomobject]@{
    FilePath = $gs.Source
    WorkingDirectory = $file.Directory
    ArgumentList = @(
        "-dBATCH"
        "-dNOPROMPT"
        "-dNOPAUSE"
        "-dQUIET"
        "-sDEVICE=png16m"
        "-dTextAlphaBits=4"
        "-r300"
        "-sPDFPassword=$password"
        "-o $OutFile"
        $file.Name
    )
    ArgumentListWithoutPassword = ""
    OutFile = [System.IO.Path]::ChangeExtension($file.FullName, ".png")
} |
    ForEach-Object {
        $_.ArgumentListWithoutPassword = ($_.ArgumentList | Join-String -Separator " ").Replace($password, "*")
        $_
    } |
    ForEach-Object {
        Write-Host -ForegroundColor Cyan "gs $($_.ArgumentListWithoutPassword)"
        Start-Process -FilePath $_.FilePath -ArgumentList $_.ArgumentList -WorkingDirectory $_.WorkingDirectory -Wait -WindowStyle Hidden
    }

Get-ChildItem $path |
    ForEach-Object {
        [pscustomobject]@{
            FullName  = "." + $_.FullName.Substring($PSScriptRoot.Length)
            Converted = Get-ChildItem ([System.IO.Path]::ChangeExtension($_.FullName, ".png")) -ErrorAction SilentlyContinue |
                ForEach-Object LastWriteTime
        }
    }
