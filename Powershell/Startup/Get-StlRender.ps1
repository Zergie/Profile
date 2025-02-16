[cmdletbinding()]
param(
    [Parameter(Mandatory,
               ValueFromPipeline)]
    [ValidateScript({ (Get-Item $_).Extension -eq ".stl" })]
    [string]
    $Path,

    [Parameter()]
    [string]
    $OutFile
)

$Path = (Get-Item $Path).FullName.Replace("\", "/")
if ($OutFile.Length -eq 0) { $OutFile = "$env:TEMP\output" }

$openscad = Get-ChildItem "$env:ProgramFiles\OpenSCAD*" -Directory |
               Get-ChildItem -File -Filter "openscad.exe" |
               Sort-Object -Descending { $_.VersionInfo.FileVersion } |
               Select-Object -First 1 |
               ForEach-Object FullName

$images = 4
$size   = 300

Remove-Item "env:TEMP\output*.png" -ErrorAction SilentlyContinue
Push-Location $env:TEMP
. $openscad nul -o "output.png" -D '$vpd=400; $vpr = [60, 0, 360 * $t];' -D "import(`"$Path`")" "--imgsize=$size,$size" --animate $($images * $images) --viewall --autocenter
Pop-Location

$p = Get-Process openscad
$p.WaitForExit()

$bitmap = [System.Drawing.Bitmap]::new($images*$size, $images*$size)
$canvas = [System.Drawing.Graphics]::FromImage($bitmap)
$canvas.InterpolationMode ='HighQualityBicubic'

$i = 0
Get-ChildItem "$env:TEMP\output*.png" |
    ForEach-Object {
        [pscustomobject]@{
            X     = ($i % $images) * $size
            Y     = [int][System.Math]::Floor($i / $images) * $size
            Image = [System.Drawing.Image]::FromFile($_.FullName)
        }
        $i++
    } |
    ForEach-Object {
        $canvas.DrawImage($_.Image, $_.X, $_.Y)
        $_.Image.Dispose()
    }
$canvas.Save() | Out-Null
$canvas.Dispose() | Out-Null
$bitmap.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose() | Out-Null
