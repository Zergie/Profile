#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [string[]] $Tag,

    [Parameter()]
    [ValidateRange(1, 3600)]
    [int] $TimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testDirectory = (Get-Item -LiteralPath $PSScriptRoot).FullName
$pesterCommand = Get-Command pwsh -ErrorAction Stop
$testDirectoryLiteral = "'" + $testDirectory.Replace("'", "''") + "'"
$tagLiterals = @(
    foreach ($selectedTag in @($Tag)) {
        if ($null -ne $selectedTag) {
            "'" + $selectedTag.Replace("'", "''") + "'"
        }
    }
) -join ', '
$childScript = "`$TestDirectory = $testDirectoryLiteral`n`$Tag = @($tagLiterals)`n" + @'
$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

$configuration = New-PesterConfiguration
$configuration.Run.Path = $TestDirectory
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
if ($Tag.Count -gt 0) {
    $configuration.Filter.Tag = $Tag
}

$result = Invoke-Pester -Configuration $configuration
if ($result.Result -ne 'Passed') {
    exit 1
}
'@
$encodedChildScript = [Convert]::ToBase64String(
    [System.Text.Encoding]::Unicode.GetBytes($childScript)
)

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $pesterCommand.Source
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
[void] $startInfo.ArgumentList.Add('-NoProfile')
[void] $startInfo.ArgumentList.Add('-NonInteractive')
[void] $startInfo.ArgumentList.Add('-EncodedCommand')
[void] $startInfo.ArgumentList.Add($encodedChildScript)

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo

try {
    if (-not $process.Start()) {
        throw 'Unable to start the Pester child process.'
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        if (-not $process.HasExited) {
            $process.Kill($true)
        }
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($stdout) {
            [Console]::Out.Write($stdout)
        }
        if ($stderr) {
            [Console]::Error.Write($stderr)
        }
        throw "Pester timed out after $TimeoutSeconds seconds."
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($stdout) {
        [Console]::Out.Write($stdout)
    }
    if ($stderr) {
        [Console]::Error.Write($stderr)
    }
    exit $process.ExitCode
} finally {
    $process.Dispose()
}
