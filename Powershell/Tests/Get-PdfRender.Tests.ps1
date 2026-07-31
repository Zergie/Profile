#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$renderScript = Join-Path $PSScriptRoot '..\Startup\Get-PdfRender.ps1'

function Assert-Equal {
    param($Expected, $Actual, [string] $Because)
    if ($Expected -cne $Actual) {
        throw "$Because`nExpected: <$Expected>`nActual:   <$Actual>"
    }
}

function Assert-True {
    param([bool] $Condition, [string] $Because)
    if (-not $Condition) { throw $Because }
}

$passed = 0
$failed = 0

function Invoke-Test {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        Write-Host "  PASS  $Name" -ForegroundColor Green
        $script:passed++
    } catch {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $_" -ForegroundColor Red
        $script:failed++
    }
}

# ---------------------------------------------------------------------------
# Fixtures — create minimal multi-page PDFs via Ghostscript at runtime
# ---------------------------------------------------------------------------
$fixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) (
    'Get-PdfRender.Tests.' + [guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $fixtureDir | Out-Null

function New-TestPdf {
    param([string] $Name, [int] $PageCount)
    $pdfPath = Join-Path $fixtureDir "$Name.pdf"
    # Build a PostScript document with $PageCount pages, each showing its number
    $psLines = @('%!PS-Adobe-3.0')
    $psLines += "%%Pages: $PageCount"
    for ($i = 1; $i -le $PageCount; $i++) {
        $psLines += "%%Page: $i $i"
        $psLines += '/Helvetica findfont 24 scalefont setfont'
        $psLines += "100 720 moveto (Page $i) show"
        $psLines += 'showpage'
    }
    $psLines += '%%EOF'
    $psContent = $psLines -join "`n"
    $psFile    = [System.IO.Path]::ChangeExtension($pdfPath, '.ps')
    Set-Content $psFile $psContent -Encoding ASCII

    $gs = Get-ChildItem 'C:\Program Files\gs\*\bin\gswin64.exe' |
        Get-Command |
        Sort-Object Version -Bottom 1
    $gsArgs = @(
        '-dBATCH', '-dNOPROMPT', '-dNOPAUSE', '-dQUIET',
        '-sDEVICE=pdfwrite',
        "-sOutputFile=`"$pdfPath`"",
        "`"$psFile`""
    )
    Start-Process -FilePath $gs.Source -ArgumentList $gsArgs -Wait -WindowStyle Hidden
    Remove-Item $psFile -Force -ErrorAction SilentlyContinue
    return $pdfPath
}

# Create fixtures
$pdf1 = New-TestPdf -Name 'one-page'   -PageCount 1
$pdf3 = New-TestPdf -Name 'three-page' -PageCount 3

Add-Type -AssemblyName System.Drawing

function Get-ImageSize {
    param([string] $Path)
    $img = [System.Drawing.Image]::FromFile($Path)
    $sz  = [pscustomobject]@{ Width = $img.Width; Height = $img.Height }
    $img.Dispose()
    return $sz
}

# ---------------------------------------------------------------------------
# Syntax check
# ---------------------------------------------------------------------------
Invoke-Test 'script file exists' {
    Assert-True (Test-Path $renderScript) "Get-PdfRender.ps1 not found at $renderScript"
}

Invoke-Test 'script parses without errors' {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($renderScript, [ref] $null, [ref] $errors) | Out-Null
    Assert-True ($errors.Count -eq 0) "Parse errors: $($errors -join '; ')"
}

Invoke-Test 'Page and Count parameters declared' {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($renderScript, [ref] $null, [ref] $null)
    $params = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
    Assert-True ($params -contains 'Page')  'Page parameter missing'
    Assert-True ($params -contains 'Count') 'Count parameter missing'
}

# ---------------------------------------------------------------------------
# PNG default — page 1 only
# ---------------------------------------------------------------------------
Invoke-Test 'default PNG renders page 1 and returns Converted path' {
    $outPng = Join-Path $fixtureDir 'default-out.png'
    $result = & $renderScript $pdf3 -OutFile $outPng
    Assert-True (Test-Path $outPng) "output PNG not found: $outPng"
    Assert-True ($result.Converted -eq $outPng) "Converted path mismatch"
}

Invoke-Test 'default PNG produces one image (no multi-page bleed)' {
    $outPng = Join-Path $fixtureDir 'default-size.png'
    & $renderScript $pdf1 -OutFile $outPng | Out-Null
    $szSingle = Get-ImageSize $outPng

    $out3Png = Join-Path $fixtureDir 'default-size-3.png'
    & $renderScript $pdf3 -OutFile $out3Png | Out-Null
    $sz3 = Get-ImageSize $out3Png

    # Default should render only page 1, so both images have similar heights
    # (A 3-page full stitch would be ~3× taller)
    Assert-True ($sz3.Height -lt ($szSingle.Height * 2)) (
        "Default render of 3-page PDF is suspiciously tall ($($sz3.Height)px); expected single page (~$($szSingle.Height)px)")
}

# ---------------------------------------------------------------------------
# Explicit page selection
# ---------------------------------------------------------------------------
Invoke-Test 'explicit Page selects that page only' {
    $out1 = Join-Path $fixtureDir 'explicit-p1.png'
    $out2 = Join-Path $fixtureDir 'explicit-p2.png'
    & $renderScript $pdf3 -Page 1 -OutFile $out1 | Out-Null
    & $renderScript $pdf3 -Page 2 -OutFile $out2 | Out-Null

    $sz1 = Get-ImageSize $out1
    $sz2 = Get-ImageSize $out2
    # Same-dimension pages from the same PDF should have equal height
    Assert-True ($sz1.Height -eq $sz2.Height) "Single-page heights differ ($($sz1.Height) vs $($sz2.Height))"
}

Invoke-Test 'Count without explicit Page starts at page 1' {
    $outCount = Join-Path $fixtureDir 'count-from-1.png'
    & $renderScript $pdf3 -Count 2 -OutFile $outCount | Out-Null
    $sz2 = Get-ImageSize $outCount

    $outPage1 = Join-Path $fixtureDir 'page1-only.png'
    & $renderScript $pdf3 -Page 1 -OutFile $outPage1 | Out-Null
    $szPage1 = Get-ImageSize $outPage1

    # 2-page stitch should be roughly twice the height of 1 page
    Assert-True ($sz2.Height -ge ($szPage1.Height * 2 - 5)) (
        "2-page stitch height ($($sz2.Height)) is not ~2× single page ($($szPage1.Height))")
}

Invoke-Test 'Page and Count select consecutive pages in one stitched image' {
    $out12 = Join-Path $fixtureDir 'pages-1-2.png'
    $out23 = Join-Path $fixtureDir 'pages-2-3.png'
    & $renderScript $pdf3 -Page 1 -Count 2 -OutFile $out12 | Out-Null
    & $renderScript $pdf3 -Page 2 -Count 2 -OutFile $out23 | Out-Null

    $sz12 = Get-ImageSize $out12
    $sz23 = Get-ImageSize $out23
    Assert-True ($sz12.Height -eq $sz23.Height) "Both 2-page stitches should have equal height"
}

# ---------------------------------------------------------------------------
# Boundary cases
# ---------------------------------------------------------------------------
Invoke-Test 'range past final page renders available suffix' {
    $outOver = Join-Path $fixtureDir 'overflow.png'
    # Requesting pages 2..99 on a 3-page doc should render pages 2 and 3
    & $renderScript $pdf3 -Page 2 -Count 98 -OutFile $outOver | Out-Null
    Assert-True (Test-Path $outOver) "overflow PNG not created"

    $szOver = Get-ImageSize $outOver
    $outP2 = Join-Path $fixtureDir 'overflow-p2.png'
    & $renderScript $pdf3 -Page 2 -OutFile $outP2 | Out-Null
    $szP2 = Get-ImageSize $outP2

    # 2-page result should be taller than 1-page reference
    Assert-True ($szOver.Height -gt $szP2.Height) (
        "overflow result ($($szOver.Height)) should be taller than single page ($($szP2.Height))")
}

Invoke-Test 'start page beyond document throws a clear error' {
    $caught = $false
    try {
        & $renderScript $pdf1 -Page 99 -OutFile (Join-Path $fixtureDir 'beyond.png') | Out-Null
    } catch {
        $caught = $true
        $msg = "$($_.Exception.Message)$($_.ToString())"
        Assert-True ($msg -match '99') "Error should mention the requested page number"
    }
    Assert-True $caught 'Expected an error for start page beyond document'
}

Invoke-Test 'non-positive Page value is rejected by parameter binding' {
    $caught = $false
    try {
        & $renderScript $pdf3 -Page 0 | Out-Null
    } catch {
        $caught = $true
    }
    Assert-True $caught 'Page=0 should be rejected'
}

Invoke-Test 'non-positive Count value is rejected by parameter binding' {
    $caught = $false
    try {
        & $renderScript $pdf3 -Count 0 | Out-Null
    } catch {
        $caught = $true
    }
    Assert-True $caught 'Count=0 should be rejected'
}

# ---------------------------------------------------------------------------
# Text mode compatibility
# ---------------------------------------------------------------------------
Invoke-Test 'text output without page args retains existing behavior' {
    $result = & $renderScript $pdf1 -As txt
    Assert-True ($null -ne $result.Converted)   'txt mode should return non-null Converted content'
    Assert-True ($result.FullName -eq $pdf1)    'txt mode FullName should match source PDF path'
}

Invoke-Test 'text output rejects explicit Page argument' {
    $caught = $false
    try {
        & $renderScript $pdf1 -As txt -Page 1 | Out-Null
    } catch {
        $caught = $true
        Assert-True ($_.ToString() -match '[Pp]age') "Error should mention 'Page'"
    }
    Assert-True $caught 'txt mode with explicit Page should throw'
}

Invoke-Test 'text output rejects explicit Count argument' {
    $caught = $false
    try {
        & $renderScript $pdf1 -As txt -Count 1 | Out-Null
    } catch {
        $caught = $true
        Assert-True ($_.ToString() -match '[Cc]ount') "Error should mention 'Count'"
    }
    Assert-True $caught 'txt mode with explicit Count should throw'
}

# ---------------------------------------------------------------------------
# Output location and cleanup
# ---------------------------------------------------------------------------
Invoke-Test 'default output placed beside source PDF' {
    $srcDir  = Join-Path $fixtureDir 'beside-test'
    New-Item -ItemType Directory -Path $srcDir | Out-Null
    $srcPdf  = Join-Path $srcDir 'sample.pdf'
    Copy-Item $pdf1 $srcPdf
    $result  = & $renderScript $srcPdf
    $expected = Join-Path $srcDir 'sample.png'
    Assert-True (Test-Path $expected)           "PNG not found beside source: $expected"
    Assert-Equal $expected $result.Converted    'Converted path should equal beside-source PNG'
    Remove-Item $srcDir -Recurse -Force
}

Invoke-Test 'explicit output path is honoured' {
    $explicit = Join-Path $fixtureDir 'custom-name.png'
    $result   = & $renderScript $pdf1 -OutFile $explicit
    Assert-True (Test-Path $explicit)           "PNG not found at explicit path: $explicit"
    Assert-Equal $explicit $result.Converted    'Converted should equal explicit output path'
}

Invoke-Test 'no render temp files left after PNG render' {
    $before  = @(Get-ChildItem $env:TEMP -Filter 'pg*.png' -ErrorAction SilentlyContinue).Count
    & $renderScript $pdf3 -OutFile (Join-Path $fixtureDir 'cleanup.png') | Out-Null
    $after   = @(Get-ChildItem $env:TEMP -Filter 'pg*.png' -ErrorAction SilentlyContinue).Count
    Assert-Equal $before $after 'Intermediate pg*.png files should not persist in TEMP'
}

# ---------------------------------------------------------------------------
# Stitched image layout (single-page: light-grey canvas, correct dimensions)
# ---------------------------------------------------------------------------
Invoke-Test 'output is a valid PNG file (magic bytes)' {
    $outPng = Join-Path $fixtureDir 'magic-check.png'
    & $renderScript $pdf1 -OutFile $outPng | Out-Null
    $bytes  = [System.IO.File]::ReadAllBytes($outPng)
    # PNG magic: 0x89 0x50 0x4E 0x47
    Assert-True ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50) 'File should start with PNG magic bytes'
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
if ($failed -eq 0) {
    Write-Host "  $passed/$($passed + $failed) tests passed." -ForegroundColor Green
} else {
    Write-Host "  $passed/$($passed + $failed) tests passed, $failed failed." -ForegroundColor Red
}

if ($failed -gt 0) { exit 1 }

# Cleanup fixtures
Remove-Item $fixtureDir -Recurse -Force -ErrorAction SilentlyContinue
