[cmdletbinding()]
param(
    [Parameter(Mandatory,
               Position=0,
               ValueFromPipeline)]
    [ValidateScript({ (Get-Item $_).Extension -eq ".stl" })]
    [string]
    $Path,

    [Parameter()]
    [string]
    $Color,

    [Parameter()]
    [string]
    $OutFile
)

$images = 4
$size   = 300

$Path   = (Get-Item $Path).FullName.Replace("\", "/")
if ($OutFile.Length -eq 0) { $OutFile = "$env:TEMP\output.png" }

$openscad = Get-ChildItem "$env:ProgramFiles\OpenSCAD*" -Directory |
               Get-ChildItem -File -Filter "openscad.exe" |
               Sort-Object -Descending { $_.VersionInfo.FileVersion } |
               Select-Object -First 1 |
               ForEach-Object FullName

Write-Host -ForegroundColor Cyan "Getting bbox of stl..."
$bbox = . "$PSScriptRoot/Get-StlBbox.ps1" -Path $Path

Write-Host -ForegroundColor Cyan "Removing `$env:TEMP\output*.png ..."
Remove-Item "$env:TEMP\output*.png" -ErrorAction SilentlyContinue

Write-Host -ForegroundColor Cyan "Running openscad..."
# @{X=17,607; Y=17,417; Z=74,147} -> 200
# @{X=43,67; Y=19,85; Z=6,9} -> 120
# @{X=143,121; Y=179,777; Z=8,328} -> 540
# @{X=16,417; Y=17,607; Z=74,147} -> 200
#
$r = [Math]::Sqrt([Math]::Pow($bbox.SizeX / 2, 2) + [Math]::Pow($bbox.SizeY / 2, 2))
$t = $r / [Math]::Tan(60 / 180 * [Math]::PI)
$zoom = [Math]::Max(200/88 * ($bbox.SizeZ + $t * 2), 120/24 * $r)

$script = @(
    if ($Color.Length -gt 0) { "color(`"$Color`")" }
    "import(`"$Path`")"
) | Join-String -Separator " "

Push-Location $env:TEMP
. $openscad nul `
    -o "output.png" `
    -D "`$vpt = [0, 0, $($bbox.center.z)]; `$vpd = $zoom; `$vpr = [60, 0, 360 * `$t];" `
    -D  $script `
    "--imgsize=$size,$size" `
    --animate $($images * $images) `
    --projection ortho `
    --colorscheme BeforeDawn `
    2>nul
Pop-Location

$p = Get-Process openscad
$p.WaitForExit()

Write-Host -ForegroundColor Cyan "Stiching image ..."
$bitmap = [System.Drawing.Bitmap]::new($images*$size, $images*$size)
$canvas = [System.Drawing.Graphics]::FromImage($bitmap)
$canvas.InterpolationMode ='HighQualityBicubic'
$canvas.FillRectangle([System.Drawing.Brushes]::Magenta, 0, 0, $bitmap.Width, $bitmap.Height)

$i = 0
Get-ChildItem "$env:TEMP\output0*.png" |
    ForEach-Object {
        [pscustomobject]@{
            Name  = $_.FullName
            X     = ($i % $images) * $size
            Y     = [int][System.Math]::Floor($i / $images) * $size
            Image = [System.Drawing.Image]::FromFile($_.FullName)
        }
        $i++
    } |
    ForEach-Object {
        $_ | Write-Debug
        $canvas.DrawImage($_.Image, $_.X, $_.Y)
        $_.Image.Dispose()
    }
$canvas.Save() | Out-Null
$canvas.Dispose() | Out-Null
$bitmap.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose() | Out-Null

if ($OutFile -eq "$env:TEMP\output.png" ) {
    Invoke-Item $OutFile
}
