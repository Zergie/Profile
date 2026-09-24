[cmdletbinding()]
param(
    [Parameter(Mandatory,
               ValueFromPipeline)]
    [ValidateScript({ (Get-Item $_).Extension -eq '.stl' })]
    [string[]]
    $Path
)

process {
    Get-ChildItem -Path $Path -File | ForEach-Object {
        $file = $_
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $minX = $minY = $minZ = [double]::PositiveInfinity
        $maxX = $maxY = $maxZ = [double]::NegativeInfinity
        $vertexCount = 0

        $isBinary = $false
        if ($bytes.Length -ge 84) {
            $triangleCount = [BitConverter]::ToUInt32($bytes, 80)
            $isBinary = 84L + 50L * $triangleCount -eq $bytes.LongLength
        }

        if ($isBinary) {
            for ($triangle = 0; $triangle -lt $triangleCount; $triangle++) {
                $triangleOffset = 84 + 50 * $triangle
                for ($vertex = 0; $vertex -lt 3; $vertex++) {
                    $vertexOffset = $triangleOffset + 12 + 12 * $vertex
                    $x = [BitConverter]::ToSingle($bytes, $vertexOffset)
                    $y = [BitConverter]::ToSingle($bytes, $vertexOffset + 4)
                    $z = [BitConverter]::ToSingle($bytes, $vertexOffset + 8)
                    $minX = [Math]::Min($minX, $x); $maxX = [Math]::Max($maxX, $x)
                    $minY = [Math]::Min($minY, $y); $maxY = [Math]::Max($maxY, $y)
                    $minZ = [Math]::Min($minZ, $z); $maxZ = [Math]::Max($maxZ, $z)
                    $vertexCount++
                }
            }
        } else {
            $numberStyle = [Globalization.NumberStyles]::Float
            $culture = [Globalization.CultureInfo]::InvariantCulture
            foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
                if ($line -notmatch '^\s*vertex\s+(\S+)\s+(\S+)\s+(\S+)\s*$') { continue }

                $x = [double]::Parse($Matches[1], $numberStyle, $culture)
                $y = [double]::Parse($Matches[2], $numberStyle, $culture)
                $z = [double]::Parse($Matches[3], $numberStyle, $culture)
                $minX = [Math]::Min($minX, $x); $maxX = [Math]::Max($maxX, $x)
                $minY = [Math]::Min($minY, $y); $maxY = [Math]::Max($maxY, $y)
                $minZ = [Math]::Min($minZ, $z); $maxZ = [Math]::Max($maxZ, $z)
                $vertexCount++
            }
        }

        if ($vertexCount -eq 0) {
            throw "'$($file.FullName)' does not contain a valid STL mesh."
        }

        $sizeX = [Math]::Round($maxX - $minX, 3)
        $sizeY = [Math]::Round($maxY - $minY, 3)
        $sizeZ = [Math]::Round($maxZ - $minZ, 3)
        [pscustomobject]@{
            Name     = $file.Name
            X        = [Math]::Round($minX, 3)
            Y        = [Math]::Round($minY, 3)
            Z        = [Math]::Round($minZ, 3)
            SizeX    = $sizeX
            SizeY    = $sizeY
            SizeZ    = $sizeZ
            Center   = [pscustomobject]@{
                X = [Math]::Round($minX + ($maxX - $minX) / 2, 3)
                Y = [Math]::Round($minY + ($maxY - $minY) / 2, 3)
                Z = [Math]::Round($minZ + ($maxZ - $minZ) / 2, 3)
            }
            Location = [pscustomobject]@{
                X = [Math]::Round($minX, 3)
                Y = [Math]::Round($minY, 3)
                Z = [Math]::Round($minZ, 3)
            }
            Size     = [pscustomobject]@{ X = $sizeX; Y = $sizeY; Z = $sizeZ }
        }
    }
}
