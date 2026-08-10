#Requires -Version 7.0

Set-StrictMode -Version Latest

BeforeAll {
    $pester = Get-Module -ListAvailable Pester |
        Where-Object { $_.Version -ge [version]'5.0.0' } |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($null -eq $pester) {
        throw 'Invoke-Item tests require Pester 5.0.0 or newer.'
    }

    . (Join-Path $PSScriptRoot 'TestSupport.ps1')

    $startupScript = Join-Path $PSScriptRoot '..\Startup\Invoke-Item.ps1'
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("invoke-item-tests-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

    $fixture = Join-Path $temporaryDirectory 'literal[fixture].txt'
    Set-Content -LiteralPath $fixture -Value 'safe fixture'

    $childScript = Join-Path $temporaryDirectory 'exercise-proxy.ps1'
    @'
param(
    [Parameter(Mandatory)]
    [string] $StartupScript,
    [Parameter(Mandatory)]
    [string] $Fixture
)

$ErrorActionPreference = 'Stop'
New-Alias -Name Invoke-Item -Value $StartupScript -Scope Local -Force
if ((Get-Alias ii).Definition -cne 'Invoke-Item') {
    throw 'The built-in ii alias was changed.'
}

& $StartupScript -LiteralPath $Fixture -WhatIf
[pscustomobject]@{ Path = $Fixture } | & $StartupScript -WhatIf
ii -LiteralPath $Fixture -WhatIf
Write-Output 'proxy-pass-through-complete'
'@ | Set-Content -LiteralPath $childScript -NoNewline

    $routingScript = Join-Path $temporaryDirectory 'exercise-routing.ps1'
    @'
param(
    [Parameter(Mandatory)]
    [string] $StartupScript,
    [Parameter(Mandatory)]
    [string] $FixtureDirectory
)

$ErrorActionPreference = 'Stop'
$bin = Join-Path $FixtureDirectory 'bin'
$calls = Join-Path $FixtureDirectory 'viewer-calls.txt'
New-Item -ItemType Directory -Path $bin | Out-Null
$env:BAT_CALLS = $calls
$env:PATH = "$bin;$env:PATH"

$batScript = @(
    'param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)',
    'if ($Arguments[0] -eq ''--list-languages'') {',
    '    Add-Content -LiteralPath $env:BAT_CALLS -Value ''list''',
    '    ''Markdown:md,mdown,markdown,markdn,*.mkd''',
    '    ''Plain Text:md,txt''',
    '    ''Plain Text:txt''',
    '    ''PowerShell:ps1''',
    '    ''CSV:csv''',
    '    ''TSV:tsv''',
    '    ''HTML:html''',
    '    ''SVG:svg''',
    '    ''Apache Conf:.htaccess''',
    '    ''Makefile:Makefile''',
    '    ''Authorized Keys:authorized_keys''',
    '    ''Special:*.special''',
    '    exit 0',
    '}',
    'Add-Content -LiteralPath $env:BAT_CALLS -Value (''bat|'' + $Arguments[0] + ''|'' + $Arguments[1])',
    'if ([System.IO.Path]::GetFileName($Arguments[0]) -ieq ''exit.txt'') { exit 7 }'
) -join "`r`n"
$batScript | Set-Content -LiteralPath (Join-Path $bin 'bat.ps1') -NoNewline

$glowScript = @(
    'param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)',
    'Add-Content -LiteralPath $env:BAT_CALLS -Value (''glow|'' + $Arguments[0] + ''|'' + $Arguments[1])',
    'if ([System.IO.Path]::GetFileName($Arguments[0]) -ieq ''exit.mkd'') { exit 8 }'
) -join "`r`n"
$glowScript | Set-Content -LiteralPath (Join-Path $bin 'glow.ps1') -NoNewline

$fixtures = @{}
foreach ($name in 'source.ps1', 'table.csv', 'page.html', 'image.svg', '.htaccess', 'Makefile', 'authorized_keys', 'name.special', 'space & [literal].txt', 'exit.txt', 'guide.md', 'guide.mdown', 'guide.markdown', 'guide.markdn', 'guide.mkd', 'GUIDE.MD', 'exit.mkd', 'unknown.docx') {
    $fixtures[$name] = Join-Path $FixtureDirectory $name
    Set-Content -LiteralPath $fixtures[$name] -Value $name
}
$directory = Join-Path $FixtureDirectory 'directory'
New-Item -ItemType Directory -Path $directory | Out-Null

New-Alias -Name Invoke-Item -Value $StartupScript -Scope Local -Force
@($fixtures['source.ps1'], $fixtures['guide.md'], $fixtures['table.csv'], $fixtures['page.html'], $fixtures['image.svg']) | & $StartupScript
foreach ($name in '.htaccess', 'Makefile', 'authorized_keys', 'name.special', 'space & [literal].txt') {
    & $StartupScript -LiteralPath $fixtures[$name]
}
foreach ($name in 'guide.markdown', 'guide.markdn', 'guide.mkd', 'GUIDE.MD') {
    & $StartupScript -LiteralPath $fixtures[$name]
}
ii -LiteralPath $fixtures['guide.mdown']
& $StartupScript -LiteralPath $fixtures['unknown.docx'] -WhatIf
& $StartupScript -LiteralPath $directory -WhatIf
& $StartupScript -LiteralPath $fixtures['source.ps1'] -WhatIf
& $StartupScript -LiteralPath $fixtures['guide.md'] -WhatIf
ii -LiteralPath $fixtures['exit.txt']
if ($LASTEXITCODE -ne 7) {
    throw "bat exit code was not preserved: $LASTEXITCODE"
}
& $StartupScript -LiteralPath $fixtures['exit.mkd']
if ($LASTEXITCODE -ne 8) {
    throw "glow exit code was not preserved: $LASTEXITCODE"
}

$actual = Get-Content -LiteralPath $calls
$expected = @(
    'list',
    "bat|$($fixtures['source.ps1'])|",
    "glow|$($fixtures['guide.md'])|",
    "bat|$($fixtures['table.csv'])|",
    "bat|$($fixtures['page.html'])|",
    "bat|$($fixtures['image.svg'])|",
    "bat|$($fixtures['.htaccess'])|",
    "bat|$($fixtures['Makefile'])|",
    "bat|$($fixtures['authorized_keys'])|",
    "bat|$($fixtures['name.special'])|",
    "bat|$($fixtures['space & [literal].txt'])|",
    "glow|$($fixtures['guide.markdown'])|",
    "glow|$($fixtures['guide.markdn'])|",
    "glow|$($fixtures['guide.mkd'])|",
    "glow|$($fixtures['GUIDE.MD'])|",
    "glow|$($fixtures['guide.mdown'])|",
    "bat|$($fixtures['exit.txt'])|",
    "glow|$($fixtures['exit.mkd'])|"
)
if (($actual -join "`n") -cne ($expected -join "`n")) {
    throw "Unexpected viewer calls:`n$($actual -join "`n")"
}

$fakeGlow = Join-Path $bin 'glow.ps1'
Remove-Item -LiteralPath $fakeGlow
$env:PATH = $bin
try {
    & $StartupScript -LiteralPath $fixtures['guide.md']
    throw 'Missing glow did not fail.'
} catch {
    if ($_.Exception.Message -notmatch "required 'glow' command was not found") {
        throw
    }
}

$global:InvokeItemBatLanguageMappings = $null
$fakeBat = Join-Path $bin 'bat.ps1'
Remove-Item -LiteralPath $fakeBat
$env:PATH = $bin
try {
    & $StartupScript -LiteralPath $fixtures['source.ps1']
    throw 'Missing bat did not fail.'
} catch {
    if ($_.Exception.Message -notmatch "required 'bat' command was not found") {
        throw
    }
}

Write-Output 'routing-complete'
'@ | Set-Content -LiteralPath $routingScript -NoNewline

    $structuredParsingScript = Join-Path $temporaryDirectory 'exercise-structured-parsing.ps1'
    @'
param(
    [Parameter(Mandatory)]
    [string] $StartupScript,
    [Parameter(Mandatory)]
    [string] $FixtureDirectory
)

$ErrorActionPreference = 'Stop'
$jsonObjectPath = Join-Path $FixtureDirectory 'record.JSON'
$jsonArrayPath = Join-Path $FixtureDirectory 'records.json'
$xmlPath = Join-Path $FixtureDirectory 'document.Xml'
$yamlPath = Join-Path $FixtureDirectory 'settings.YAML'
$ymlPath = Join-Path $FixtureDirectory 'settings.yml'
Set-Content -LiteralPath $jsonObjectPath -Value '{"name":"Ada","count":2}' -NoNewline
Set-Content -LiteralPath $jsonArrayPath -Value '[{"name":"Grace"},{"name":"Linus"}]' -NoNewline
Set-Content -LiteralPath $xmlPath -Value '<catalog version="1"><entry id="first">value</entry></catalog>' -NoNewline
Set-Content -LiteralPath $yamlPath -Value 'name: Ada' -NoNewline
Set-Content -LiteralPath $ymlPath -Value 'name: Grace' -NoNewline

function ConvertFrom-Yaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $InputObject
    )

    process {
        [ordered]@{
            Parser = 'fake'
            Content = $InputObject
        }
    }
}

$jsonObject = & $StartupScript -Path $jsonObjectPath
if ($jsonObject.name -cne 'Ada' -or $jsonObject.count -ne 2) {
    throw 'JSON object properties were not preserved.'
}

$jsonArray = @(& $StartupScript -LiteralPath $jsonArrayPath)
if ($jsonArray.Count -ne 2 -or $jsonArray[0].name -cne 'Grace' -or $jsonArray[1].name -cne 'Linus') {
    throw 'JSON array semantics were not preserved.'
}

$xml = & $StartupScript -LiteralPath $xmlPath
if ($xml -isnot [xml] -or $xml.catalog.version -cne '1' -or $xml.catalog.entry.id -cne 'first' -or $xml.catalog.entry.InnerText -cne 'value') {
    throw 'XML document navigation was not preserved.'
}

$yaml = & $StartupScript -LiteralPath $yamlPath
if ($yaml -isnot [System.Collections.IDictionary] -or $yaml.Parser -cne 'fake' -or $yaml.Content -cne 'name: Ada') {
    throw 'YAML parser output was not preserved.'
}

$yml = & $StartupScript -LiteralPath $ymlPath
if ($yml -isnot [System.Collections.IDictionary] -or $yml.Parser -cne 'fake' -or $yml.Content -cne 'name: Grace') {
    throw 'YML parser output was not preserved.'
}

$wildcardResults = @(& $StartupScript -Path (Join-Path $FixtureDirectory 'record.*'))
if ($wildcardResults.Count -ne 1 -or $wildcardResults[0].name -cne 'Ada') {
    throw 'Wildcard JSON resolution did not preserve parsed output.'
}

$pipelineResult = [pscustomobject]@{ Path = $jsonObjectPath } | & $StartupScript
if ($pipelineResult.name -cne 'Ada') {
    throw 'Pipeline JSON resolution did not preserve parsed output.'
}

Write-Output 'structured-parsing-complete'
'@ | Set-Content -LiteralPath $structuredParsingScript -NoNewline

    $missingYamlParserScript = Join-Path $temporaryDirectory 'exercise-missing-yaml-parser.ps1'
    @'
param(
    [Parameter(Mandatory)]
    [string] $StartupScript,
    [Parameter(Mandatory)]
    [string] $FixtureDirectory
)

$ErrorActionPreference = 'Stop'
$yamlPath = Join-Path $FixtureDirectory 'missing-parser.yaml'
Set-Content -LiteralPath $yamlPath -Value 'name: Ada' -NoNewline

function Get-Command {
    param(
        [Parameter(Position = 0)]
        [string] $Name
    )

    if ($Name -eq 'ConvertFrom-Yaml') {
        return $null
    }

    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
}

try {
    & $StartupScript -LiteralPath $yamlPath
    throw 'Missing YAML parser did not fail.'
} catch {
    if ($_.Exception.Message -notmatch "required 'ConvertFrom-Yaml' command was not found") {
        throw
    }
}

Write-Output 'missing-yaml-parser-complete'
'@ | Set-Content -LiteralPath $missingYamlParserScript -NoNewline

    $structuredSafetyScript = Join-Path $temporaryDirectory 'exercise-structured-safety.ps1'
    @'
param(
    [Parameter(Mandatory)]
    [string] $StartupScript,
    [Parameter(Mandatory)]
    [string] $FixtureDirectory
)

$ErrorActionPreference = 'Stop'
$jsonPath = Join-Path $FixtureDirectory 'invalid.json'
$xmlPath = Join-Path $FixtureDirectory 'invalid.xml'
$yamlPath = Join-Path $FixtureDirectory 'invalid.yaml'
Set-Content -LiteralPath $jsonPath -Value '{invalid' -NoNewline
Set-Content -LiteralPath $xmlPath -Value '<catalog>' -NoNewline
Set-Content -LiteralPath $yamlPath -Value 'invalid: [' -NoNewline

function ConvertFrom-Yaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $InputObject
    )

    process {
        throw 'fake YAML parser failure'
    }
}

foreach ($fixture in @(
    [pscustomobject]@{ Path = $jsonPath; Format = 'Json'; Error = 'Conversion from JSON failed' },
    [pscustomobject]@{ Path = $xmlPath; Format = 'Xml'; Error = 'Unexpected end of file' },
    [pscustomobject]@{ Path = $yamlPath; Format = 'Yaml'; Error = 'fake YAML parser failure' }
)) {
    try {
        & $StartupScript -LiteralPath $fixture.Path
        throw "Malformed $($fixture.Format) did not fail."
    } catch {
        if ($_.Exception.Message -notmatch [regex]::Escape($fixture.Path) -or
            $_.Exception.Message -notmatch [regex]::Escape($fixture.Error) -or
            $null -eq $_.Exception.InnerException) {
            throw
        }
    }
}

$whatIfOutput = @(& $StartupScript -LiteralPath $jsonPath -WhatIf)
if ($whatIfOutput.Count -ne 0) {
    throw 'WhatIf emitted parsed output.'
}

Write-Output 'structured-safety-complete'
'@ | Set-Content -LiteralPath $structuredSafetyScript -NoNewline
}

AfterAll {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}

Describe 'Invoke-Item startup proxy' -Tag Command {
    It 'requires PowerShell 7 and Pester 5 or newer' {
        $PSVersionTable.PSVersion | Should -BeGreaterOrEqual ([version]'7.0.0')
        (Get-Module Pester).Version | Should -BeGreaterOrEqual ([version]'5.0.0')
    }

    It 'exists and parses' {
        Test-Path -LiteralPath $startupScript -PathType Leaf | Should -BeTrue
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($startupScript, [ref] $null, [ref] $errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'retains the native parameter contract' {
        $native = Get-Command Microsoft.PowerShell.Management\Invoke-Item -CommandType Cmdlet
        $proxy = Get-Command $startupScript -CommandType ExternalScript

        ($proxy.ParameterSets.Name -join ',') | Should -Be ($native.ParameterSets.Name -join ',')
        foreach ($name in 'Path', 'LiteralPath', 'Filter', 'Include', 'Exclude', 'Credential') {
            $proxy.Parameters.ContainsKey($name) | Should -BeTrue -Because "the proxy must include -$name"
            $proxy.Parameters[$name].ParameterType | Should -Be $native.Parameters[$name].ParameterType
        }

        $proxy.Parameters['LiteralPath'].Aliases | Should -Contain 'PSPath'
        $proxy.Parameters['LiteralPath'].Aliases | Should -Contain 'LP'
        $proxy.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        $proxy.Parameters.ContainsKey('Confirm') | Should -BeTrue
    }

    It 'delegates direct, pipeline, and ii calls in a fresh process' {
        $result = Invoke-BoundedProcess -FilePath $pwsh -ArgumentList @(
            '-NoProfile', '-File', $childScript, '-StartupScript', $startupScript, '-Fixture', $fixture
        )

        $result.ExitCode | Should -Be 0 -Because "$($result.Command)`n$($result.StdOut)`n$($result.StdErr)"
        $result.StdOut | Should -Match 'proxy-pass-through-complete'
        $result.StdOut | Should -Match 'What if:'
    }

    It 'reports bounded child-process timeout diagnostics' {
        {
            Invoke-BoundedProcess -FilePath $pwsh -ArgumentList @(
                '-NoProfile', '-Command', '[Console]::Out.Write("standard output"); [Console]::Error.Write("standard error"); Start-Sleep -Seconds 5'
            ) -TimeoutSeconds 1
        } | Should -Throw '*timed out after 1 seconds*standard output*standard error*'
    }

    It 'keeps glow in the Chocolatey tool declaration' {
        $installer = Join-Path $PSScriptRoot '..\..\Install-Tools.ps1'
        (Get-Content -LiteralPath $installer -Raw) | Should -Match '\[pscustomobject\]@\{name="glow"\}'
    }

    It 'routes text and Markdown files with native fallback in a fresh process' {
        $result = Invoke-BoundedProcess -FilePath $pwsh -ArgumentList @(
            '-NoProfile', '-File', $routingScript, '-StartupScript', $startupScript, '-FixtureDirectory', $temporaryDirectory
        )

        $result.ExitCode | Should -Be 0 -Because "$($result.Command)`n$($result.StdOut)`n$($result.StdErr)"
        $result.StdOut | Should -Match 'routing-complete'
    }

    It 'parses JSON and XML files before terminal viewers in a fresh process' {
        $result = Invoke-BoundedProcess -FilePath $pwsh -ArgumentList @(
            '-NoProfile', '-File', $structuredParsingScript, '-StartupScript', $startupScript, '-FixtureDirectory', $temporaryDirectory
        )

        $result.ExitCode | Should -Be 0 -Because "$($result.Command)`n$($result.StdOut)`n$($result.StdErr)"
        $result.StdOut | Should -Match 'structured-parsing-complete'
    }

    It 'reports a missing YAML parser in a fresh process' {
        $result = Invoke-BoundedProcess -FilePath $pwsh -ArgumentList @(
            '-NoProfile', '-File', $missingYamlParserScript, '-StartupScript', $startupScript, '-FixtureDirectory', $temporaryDirectory
        )

        $result.ExitCode | Should -Be 0 -Because "$($result.Command)`n$($result.StdOut)`n$($result.StdErr)"
        $result.StdOut | Should -Match 'missing-yaml-parser-complete'
    }

    It 'reports contextual structured parser failures and honors WhatIf in a fresh process' {
        $result = Invoke-BoundedProcess -FilePath $pwsh -ArgumentList @(
            '-NoProfile', '-File', $structuredSafetyScript, '-StartupScript', $startupScript, '-FixtureDirectory', $temporaryDirectory
        )

        $result.ExitCode | Should -Be 0 -Because "$($result.Command)`n$($result.StdOut)`n$($result.StdErr)"
        $result.StdOut | Should -Match 'structured-safety-complete'
    }
}
