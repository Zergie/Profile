#Requires -Version 7.0

Set-StrictMode -Version Latest

Describe 'Get-PdfRender command' -Tag 'Command' {
    BeforeAll {
        $pester = Get-Module -ListAvailable Pester |
            Where-Object { $_.Version -ge [version]'5.0.0' } |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($null -eq $pester) {
            throw 'Get-PdfRender tests require Pester 5.0.0 or newer.'
        }

        . (Join-Path $PSScriptRoot 'TestSupport.ps1')

        $renderScript = Join-Path $PSScriptRoot '..\Startup\Get-PdfRender.ps1'
        $ghostscript = Get-ChildItem 'C:\Program Files\gs\*\bin\gswin64.exe' -ErrorAction SilentlyContinue |
            Get-Command |
            Sort-Object Version -Bottom 1
        if ($null -eq $ghostscript) {
            throw 'Get-PdfRender tests require Ghostscript. Install it with: choco install Ghostscript'
        }

        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        } catch {
            throw "Get-PdfRender tests require System.Drawing image decoding: $($_.Exception.Message)"
        }

        $fixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) (
            'Get-PdfRender.Tests.' + [guid]::NewGuid().ToString('N')
        )
        New-Item -ItemType Directory -Path $fixtureDir | Out-Null

        function script:Invoke-Ghostscript {
            param([string[]] $ArgumentList)

            $result = Invoke-BoundedProcess -FilePath $ghostscript.Source -ArgumentList $ArgumentList -TimeoutSeconds 30
            if ($result.ExitCode -ne 0) {
                throw "Ghostscript failed with exit code $($result.ExitCode): $($result.Command)`nstdout:`n$($result.StdOut)`nstderr:`n$($result.StdErr)"
            }
        }

        function script:New-TestPdf {
            param([string] $Name, [int] $PageCount)

            $pdfPath = Join-Path $fixtureDir "$Name.pdf"
            $psPath = [System.IO.Path]::ChangeExtension($pdfPath, '.ps')
            $lines = @('%!PS-Adobe-3.0', "%%Pages: $PageCount")
            for ($page = 1; $page -le $PageCount; $page++) {
                $lines += "%%Page: $page $page"
                $lines += '/Helvetica findfont 24 scalefont setfont'
                $lines += "100 720 moveto (Page $page) show"
                $lines += 'showpage'
            }
            $lines += '%%EOF'
            Set-Content -LiteralPath $psPath -Value ($lines -join "`n") -Encoding Ascii

            try {
                Invoke-Ghostscript -ArgumentList @(
                    '-dBATCH', '-dNOPROMPT', '-dNOPAUSE', '-dQUIET',
                    '-sDEVICE=pdfwrite',
                    "-sOutputFile=$pdfPath",
                    $psPath
                )
            } finally {
                Remove-Item -LiteralPath $psPath -Force -ErrorAction SilentlyContinue
            }

            $pdfPath
        }

        function script:Get-ImageSize {
            param([string] $Path)

            $image = [System.Drawing.Image]::FromFile($Path)
            try {
                [pscustomobject]@{ Width = $image.Width; Height = $image.Height }
            } finally {
                $image.Dispose()
            }
        }

        function script:New-TestOutputPath {
            Join-Path $fixtureDir ([guid]::NewGuid().ToString('N') + '.png')
        }

        $pdf1 = New-TestPdf -Name 'one-page' -PageCount 1
        $pdf3 = New-TestPdf -Name 'three-page' -PageCount 3
    }

    AfterAll {
        Remove-Item -LiteralPath $fixtureDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item function:\script\Invoke-Ghostscript, function:\script\New-TestPdf, function:\script\Get-ImageSize, function:\script\New-TestOutputPath -ErrorAction SilentlyContinue
    }

    It 'exists and parses without errors' {
        Test-Path -LiteralPath $renderScript | Should -BeTrue
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($renderScript, [ref] $null, [ref] $errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'declares Page and Count parameters' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($renderScript, [ref] $null, [ref] $null)
        $parameters = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath

        $parameters | Should -Contain 'Page'
        $parameters | Should -Contain 'Count'
    }

    It 'renders only page one by default and returns its converted path' {
        $singleOutput = New-TestOutputPath
        $threePageOutput = New-TestOutputPath

        $single = & $renderScript $pdf1 -OutFile $singleOutput
        $threePage = & $renderScript $pdf3 -OutFile $threePageOutput

        $single.Converted | Should -Be $singleOutput
        $threePage.Converted | Should -Be $threePageOutput
        Test-Path -LiteralPath $threePageOutput | Should -BeTrue
        (Get-ImageSize $threePageOutput).Height | Should -BeLessThan ((Get-ImageSize $singleOutput).Height * 2)
    }

    It 'selects an explicit page' {
        $firstOutput = New-TestOutputPath
        $secondOutput = New-TestOutputPath

        & $renderScript $pdf3 -Page 1 -OutFile $firstOutput | Out-Null
        & $renderScript $pdf3 -Page 2 -OutFile $secondOutput | Out-Null

        (Get-ImageSize $firstOutput).Height | Should -Be (Get-ImageSize $secondOutput).Height
    }

    It 'starts Count at page one when Page is omitted' {
        $countOutput = New-TestOutputPath
        $singleOutput = New-TestOutputPath

        & $renderScript $pdf3 -Count 2 -OutFile $countOutput | Out-Null
        & $renderScript $pdf3 -Page 1 -OutFile $singleOutput | Out-Null

        (Get-ImageSize $countOutput).Height | Should -BeGreaterOrEqual ((Get-ImageSize $singleOutput).Height * 2 - 5)
    }

    It 'stitches consecutive pages selected by Page and Count' {
        $firstRange = New-TestOutputPath
        $secondRange = New-TestOutputPath

        & $renderScript $pdf3 -Page 1 -Count 2 -OutFile $firstRange | Out-Null
        & $renderScript $pdf3 -Page 2 -Count 2 -OutFile $secondRange | Out-Null

        (Get-ImageSize $firstRange).Height | Should -Be (Get-ImageSize $secondRange).Height
    }

    It 'renders an available suffix when a range exceeds the document' {
        $overflowOutput = New-TestOutputPath
        $singleOutput = New-TestOutputPath

        & $renderScript $pdf3 -Page 2 -Count 98 -OutFile $overflowOutput | Out-Null
        & $renderScript $pdf3 -Page 2 -OutFile $singleOutput | Out-Null

        (Get-ImageSize $overflowOutput).Height | Should -BeGreaterThan (Get-ImageSize $singleOutput).Height
    }

    It 'reports a page beyond the document' {
        { & $renderScript $pdf1 -Page 99 -OutFile (New-TestOutputPath) | Out-Null } |
            Should -Throw '*99*'
    }

    It 'rejects non-positive <Parameter> values' -TestCases @(
        @{ Parameter = 'Page'; Value = 0 }
        @{ Parameter = 'Count'; Value = 0 }
    ) {
        param($Parameter, $Value)

        { & $renderScript $pdf3 "-$Parameter" $Value | Out-Null } | Should -Throw
    }

    It 'converts text and returns the source path' {
        $result = & $renderScript $pdf1 -As txt

        $result.Converted | Should -Not -BeNullOrEmpty
        $result.FullName | Should -Be $pdf1
    }

    It 'rejects <Parameter> in text mode' -TestCases @(
        @{ Parameter = 'Page' }
        @{ Parameter = 'Count' }
    ) {
        param($Parameter)

        { & $renderScript $pdf1 -As txt "-$Parameter" 1 | Out-Null } | Should -Throw "*$Parameter*"
    }

    It 'writes the default PNG beside the source PDF' {
        $sourceDirectory = Join-Path $fixtureDir ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $sourceDirectory | Out-Null
        $sourcePdf = Join-Path $sourceDirectory 'sample.pdf'
        Copy-Item -LiteralPath $pdf1 -Destination $sourcePdf
        $expected = Join-Path $sourceDirectory 'sample.png'

        $result = & $renderScript $sourcePdf

        Test-Path -LiteralPath $expected | Should -BeTrue
        $result.Converted | Should -Be $expected
    }

    It 'honors an explicit PNG output path' {
        $output = New-TestOutputPath

        $result = & $renderScript $pdf1 -OutFile $output

        Test-Path -LiteralPath $output | Should -BeTrue
        $result.Converted | Should -Be $output
    }

    It 'leaves no intermediate page images in TEMP' {
        $before = @(Get-ChildItem $env:TEMP -Filter 'pg*.png' -ErrorAction SilentlyContinue).Count

        & $renderScript $pdf3 -OutFile (New-TestOutputPath) | Out-Null

        @(Get-ChildItem $env:TEMP -Filter 'pg*.png' -ErrorAction SilentlyContinue).Count | Should -Be $before
    }

    It 'creates a decodable PNG with the expected signature' {
        $output = New-TestOutputPath

        & $renderScript $pdf1 -OutFile $output | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes($output)

        $bytes[0..3] | Should -Be @(0x89, 0x50, 0x4e, 0x47)
        (Get-ImageSize $output).Width | Should -BeGreaterThan 0
        (Get-ImageSize $output).Height | Should -BeGreaterThan 0
    }
}
