[cmdletbinding()]
param(
    [Parameter(Mandatory,
               ValueFromPipeline)]
    [ValidateScript({ (Get-Item $_).Extension -eq ".stl" })]
    [string[]]
    $Path
)
Process {
# needs: pip install numpy-stl
python -c '
import stl
from stl import mesh

min_x = max_x = min_y = max_y = min_z = max_z = None

for p in mesh.Mesh.from_file("$1").points:
    if min_x is None:
        min_x = p[stl.Dimension.X]
        max_x = p[stl.Dimension.X]
        min_y = p[stl.Dimension.Y]
        max_y = p[stl.Dimension.Y]
        min_z = p[stl.Dimension.Z]
        max_z = p[stl.Dimension.Z]
    else:
        max_x = max(p[stl.Dimension.X], max_x)
        min_x = min(p[stl.Dimension.X], min_x)
        max_y = max(p[stl.Dimension.Y], max_y)
        min_y = min(p[stl.Dimension.Y], min_y)
        max_z = max(p[stl.Dimension.Z], max_z)
        min_z = min(p[stl.Dimension.Z], min_z)

print("{")
print("min_x :", min_x, ",")
print("max_x :", max_x, ",")
print("min_y :", min_y, ",")
print("max_y :", max_y, ",")
print("min_z :", min_z, ",")
print("max_z :", max_z)
print("}")
'.Replace('$1', (Get-ChildItem $Path).FullName.Replace("\","\\")) |
    ConvertFrom-Json |
    ForEach-Object {
        [pscustomobject]@{
            Name     = (Get-ChildItem $Path).Name
            X        = [Math]::Round($_.min_x, 3)
            Y        = [Math]::Round($_.min_y, 3)
            Z        = [Math]::Round($_.min_z, 3)
            SizeX    = [Math]::Round($_.max_x - $_.min_x, 3)
            SizeY    = [Math]::Round($_.max_y - $_.min_y, 3)
            SizeZ    = [Math]::Round($_.max_z - $_.min_z, 3)
            Center   = [pscustomobject]@{
                X=[Math]::Round($_.min_x + ($_.max_x - $_.min_x) / 2, 3)
                Y=[Math]::Round($_.min_y + ($_.max_y - $_.min_y) / 2, 3)
                Z=[Math]::Round($_.min_z + ($_.max_z - $_.min_z) / 2, 3)
            }
            Location = [pscustomobject]@{ X=0; Y=0; Z=0; }
            Size     = [pscustomobject]@{ X=0; Y=0; Z=0; }
        }
    } |
    ForEach-Object {
        $_.Location.X = $_.X
        $_.Location.Y = $_.Y
        $_.Location.Z = $_.Z
        $_.Size.X = $_.SizeX
        $_.Size.Y = $_.SizeY
        $_.Size.Z = $_.SizeZ
        $_
    }
}
