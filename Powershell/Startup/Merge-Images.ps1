#Requires -PSEdition Core
[cmdletbinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory=$true,
               Position=0,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Path,

    [Parameter(Mandatory=$true,
               Position=1,
               ValueFromPipeline=$false,
               ValueFromPipelineByPropertyName=$false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $OutFile,

    [Parameter()]
    [switch]
    $SetAsWallpaper
)
DynamicParam {
}
begin {
    $ErrorActionPreference = 'SilentlyContinue'
    Add-Type -AssemblyName 'System.Drawing'

    $ErrorActionPreference = 'Stop'
    $images = @()
}
process {
    foreach ($item in $Path) {
        $images += [System.Drawing.Bitmap]::FromFile((Resolve-Path $item).Path)
    }
}
end {
    $h = [int]($images.Height | Measure-Object -Maximum).Maximum
    $w = [int]($images.Width | Measure-Object -Sum).Sum

    Write-Host "Creating blank canvas (${w}x${h}).."
    $canvas = [System.Drawing.Bitmap]::new($w, $h)
    $g = [System.drawing.graphics]::FromImage($canvas)

    Write-Host "Filling with black.."
    $g.Clear([System.Drawing.Color]::Black)

    $x = [int]0
    $y = [int]0
    foreach ($image in $images) {
        Write-Host "Drawing image to ($x, $y)"
        $g.DrawImage($image, $x, $y)

        $x += $image.Width
        $y = 0

        $image.Dispose()
    }

    Write-Host "Saving to $OutFile.."
    Set-Content -Path $OutFile -Value ""
    $canvas.Save((Resolve-Path $OutFile).Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()

    if ($SetAsWallpaper) {
        Write-Host "Setting Wallpaper.."
        Start-ThreadJob -ArgumentList (Resolve-Path $OutFile).Path, "Span" {
            param(
                [parameter(Mandatory=$True)]
                [string]$Image,

                [parameter(Mandatory=$False)]
                [ValidateSet('Fill', 'Fit', 'Stretch', 'Tile', 'Center', 'Span')]
                [string]$Style
            )

            $WallpaperStyle = Switch ($Style) {
                "Fill"    {"10"}
                "Fit"     {"6"}
                "Stretch" {"2"}
                "Tile"    {"0"}
                "Center"  {"0"}
                "Span"    {"22"}
            }

            If($Style -eq "Tile") {
                New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -PropertyType String -Value $WallpaperStyle -Force
                New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -PropertyType String -Value 1 -Force
            } else {
                New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -PropertyType String -Value $WallpaperStyle -Force
                New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -PropertyType String -Value 0 -Force
            }

            Add-Type -TypeDefinition @"
            using System;
            using System.Runtime.InteropServices;

            public class Params
            {
                [DllImport("User32.dll",CharSet=CharSet.Unicode)]
                public static extern int SystemParametersInfo (Int32 uAction, Int32 uParam, String lpvParam, Int32 fuWinIni);
            }
"@

            $SPI_SETDESKWALLPAPER = 0x0014
            $UpdateIniFile = 0x01
            $SendChangeEvent = 0x02

            $fWinIni = $UpdateIniFile -bor $SendChangeEvent

            [Params]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $Image, $fWinIni)
        } | Wait-Job | Remove-Job
    }
}
