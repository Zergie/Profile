BeforeAll {
    $script:GetStlBbox = Join-Path $PSScriptRoot '..\Startup\Get-StlBbox.ps1'
    $script:AsciiStl = Join-Path $TestDrive 'offset-cuboid.stl'
    $script:BinaryStl = Join-Path $TestDrive 'triangle.stl'

    @'
solid offset_cuboid
  facet normal 0 0 1
    outer loop
      vertex -2 3 5
      vertex 8 3 5
      vertex -2 13 5
    endloop
  endfacet
  facet normal 0 0 -1
    outer loop
      vertex 8 13 25
      vertex 8 3 25
      vertex -2 13 25
    endloop
  endfacet
endsolid offset_cuboid
'@ | Set-Content -LiteralPath $script:AsciiStl

    $stream = [System.IO.File]::Create($script:BinaryStl)
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([byte[]]::new(80))
        $writer.Write([uint32]1)
        $writer.Write([single]0); $writer.Write([single]0); $writer.Write([single]1)
        foreach ($coordinate in @(
            -4, 2, 7,
             6, 2, 7,
            -4, 12, 17
        )) {
            $writer.Write([single]$coordinate)
        }
        $writer.Write([uint16]0)
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

Describe 'Get-StlBbox' {
    It 'calculates an STL bounding box without an external Python module' {
        $result = & $script:GetStlBbox -Path $script:AsciiStl

        $result.Name | Should -Be 'offset-cuboid.stl'
        $result.X | Should -Be -2
        $result.Y | Should -Be 3
        $result.Z | Should -Be 5
        $result.SizeX | Should -Be 10
        $result.SizeY | Should -Be 10
        $result.SizeZ | Should -Be 20
        $result.Center.X | Should -Be 3
        $result.Center.Y | Should -Be 8
        $result.Center.Z | Should -Be 15
    }

    It 'supports binary STL files' {
        $result = & $script:GetStlBbox -Path $script:BinaryStl

        $result.Location.X | Should -Be -4
        $result.Location.Y | Should -Be 2
        $result.Location.Z | Should -Be 7
        $result.Size.X | Should -Be 10
        $result.Size.Y | Should -Be 10
        $result.Size.Z | Should -Be 10
        $result.Center.X | Should -Be 1
        $result.Center.Y | Should -Be 7
        $result.Center.Z | Should -Be 12
    }
}
