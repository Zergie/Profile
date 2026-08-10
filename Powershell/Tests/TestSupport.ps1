Set-StrictMode -Version Latest

function Invoke-BoundedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter()]
        [string[]] $ArgumentList = @(),

        [Parameter()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string] $WorkingDirectory,

        [Parameter()]
        [ValidateRange(1, 600)]
        [int] $TimeoutSeconds = 30
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    if ($WorkingDirectory) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    foreach ($argument in $ArgumentList) {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $command = "$FilePath $($ArgumentList -join ' ')"

    try {
        if (-not $process.Start()) {
            throw "Unable to start child process: $command"
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
            throw "Child process timed out after $TimeoutSeconds seconds: $command`nstdout:`n$stdout`nstderr:`n$stderr"
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [pscustomobject]@{
            Command  = $command
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    } finally {
        $process.Dispose()
    }
}

function Wait-TestCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Condition,

        [Parameter(Mandatory)]
        [string] $Operation,

        [Parameter()]
        [ValidateRange(1, 600)]
        [int] $TimeoutSeconds = 5,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int] $PollMilliseconds = 50
    )

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError = $null
    do {
        try {
            $result = & $Condition
            if ($result) {
                return $result
            }
        } catch {
            $lastError = $_
        }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ([datetime]::UtcNow -lt $deadline)

    $details = if ($lastError) { $lastError.Exception.Message } else { 'condition was not met' }
    throw "$Operation timed out after $TimeoutSeconds seconds: $details"
}

function Wait-TestProcessExit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process,

        [Parameter(Mandatory)]
        [string] $Operation,

        [Parameter()]
        [ValidateRange(1, 600)]
        [int] $TimeoutSeconds = 5
    )

    if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
        throw "$Operation timed out after $TimeoutSeconds seconds (process id $($Process.Id))."
    }
}
