[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$scriptPath = Join-Path $PSScriptRoot "..\Startup\Invoke-ChatGPT.ps1"
$source = Get-Content -Raw $scriptPath
$failures = [System.Collections.Generic.List[string]]::new()

Add-Type -TypeDefinition @'
using System;
using System.Management.Automation.Host;

public sealed class InvokeChatGPTFakeRawUi
{
    private readonly string[] lines;
    private readonly bool unavailable;

    public Coordinates WindowPosition { get; } = new Coordinates(0, 0);
    public Size WindowSize { get; }

    public InvokeChatGPTFakeRawUi(string[] lines, bool unavailable)
    {
        this.lines = lines;
        this.unavailable = unavailable;
        var width = 1;
        foreach (var line in lines)
            width = Math.Max(width, line.Length);
        WindowSize = new Size(width, Math.Max(1, lines.Length));
    }

    public BufferCell[,] GetBufferContents(Rectangle rectangle)
    {
        if (unavailable)
            throw new InvalidOperationException("screen buffer unavailable");

        var cells = new BufferCell[WindowSize.Height, WindowSize.Width];
        for (var row = 0; row < WindowSize.Height; row++)
        for (var column = 0; column < WindowSize.Width; column++)
        {
            var character = row < lines.Length && column < lines[row].Length
                ? lines[row][column]
                : ' ';
            cells[row, column] = new BufferCell(
                character,
                ConsoleColor.White,
                ConsoleColor.Black,
                BufferCellType.Complete
            );
        }
        return cells;
    }
}
'@

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        $failures.Add($Message)
    }
}

function New-FakeRawUi {
    param(
        [string[]] $Lines,
        [switch] $Unavailable
    )

    return [InvokeChatGPTFakeRawUi]::new($Lines, $Unavailable.IsPresent)
}

function Invoke-ChatTestCase {
    param(
        [string[]] $Message,
        [switch] $Pipeline,
        [switch] $Interactive,
        [switch] $IncludeTerminal,
        [switch] $Unavailable
    )

    $testSource = $source.Replace('$Host.UI.RawUI', '$global:InvokeChatGPTTestRawUi')
    $testSource = [regex]::Replace($testSource, '(?m)^(\s*)exit\s*$', '$1return')
    $testScript = Join-Path ([System.IO.Path]::GetTempPath()) "Invoke-ChatGPT-$([guid]::NewGuid()).ps1"
    Set-Content -LiteralPath $testScript -Value $testSource

    $longLine = "x" * 12000
    $global:InvokeChatGPTTestRawUi = New-FakeRawUi -Lines @(
        "PS C:\repo> git status"
        "PS C:\repo> Invoke-ChatGPT -Message 'why' -IncludeTerminal"
        $longLine
    ) -Unavailable:$Unavailable
    $global:InvokeChatGPTTestRequests = [System.Collections.Generic.List[object]]::new()
    function global:Invoke-RestMethod {
        param($Method, $Uri, $Headers, $Body)
        $global:InvokeChatGPTTestRequests.Add(($Body | ConvertFrom-Json))
        return [pscustomobject]@{
            choices = @([pscustomobject]@{
                message = [pscustomobject]@{ content = "test response" }
            })
        }
    }

    try {
        $arguments = @{}
        if ($Interactive) { $arguments.Interactive = $true }
        if ($IncludeTerminal) { $arguments.IncludeTerminal = $true }

        $caught = $null
        try {
            if ($Pipeline) {
                $Message | & $testScript @arguments | Out-Null
            } else {
                & $testScript -Message $Message @arguments | Out-Null
            }
        } catch {
            $caught = $_
        }

        return [pscustomobject]@{
            Requests = @($global:InvokeChatGPTTestRequests)
            Error = $caught
            LongLine = $longLine
        }
    } finally {
        Remove-Item -LiteralPath $testScript -Force -ErrorAction SilentlyContinue
        Remove-Item function:\global:Invoke-RestMethod -ErrorAction SilentlyContinue
        Remove-Variable InvokeChatGPTTestRawUi -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable InvokeChatGPTTestRequests -Scope Global -ErrorAction SilentlyContinue
    }
}

$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref] $null,
    [ref] $parseErrors
)
Assert-True ($parseErrors.Count -eq 0) "Invoke-ChatGPT.ps1 must parse without errors."
$includeParameter = $ast.ParamBlock.Parameters | Where-Object {
    $_.Name.VariablePath.UserPath -eq 'IncludeTerminal'
}
Assert-True ($null -ne $includeParameter) "-IncludeTerminal must be a declared parameter."
Assert-True (
    @($includeParameter.Attributes | ForEach-Object {
        $_.NamedArguments | Where-Object {
            $_.ArgumentName -eq 'ParameterSetName' -and $_.Argument.Extent.Text -eq '"ChatParameterSet"'
        }
    }).Count -eq 1
) "-IncludeTerminal must only be added to ChatParameterSet."

foreach ($case in @(
    @{ Name = "one-shot"; Pipeline = $false; Interactive = $false }
    @{ Name = "pipeline"; Pipeline = $true; Interactive = $false }
    @{ Name = "interactive"; Pipeline = $false; Interactive = $true }
)) {
    $messages = if ($case.Interactive) {
        @("original question", "exit")
    } else {
        @("original question")
    }
    $result = Invoke-ChatTestCase -Message $messages `
        -Pipeline:$case.Pipeline -Interactive:$case.Interactive -IncludeTerminal
    Assert-True ($null -eq $result.Error) "$($case.Name) invocation should succeed. Error: $($result.Error)"
    Assert-True ($result.Requests.Count -eq 1) "$($case.Name) invocation should make one API request."
    if ($result.Requests.Count -eq 1) {
        $content = $result.Requests[0].messages[1].content
        Assert-True ($content.StartsWith("[TERMINAL OUTPUT - VISIBLE SCREEN]")) "$($case.Name) content must start with the terminal label."
        Assert-True ($content.Contains("PS C:\repo> git status")) "$($case.Name) content must preserve prompts."
        Assert-True ($content.Contains("Invoke-ChatGPT -Message 'why' -IncludeTerminal")) "$($case.Name) content must preserve partial input."
        Assert-True ($content.Contains($result.LongLine)) "$($case.Name) content must not feature-truncate terminal text."
        Assert-True ($content.EndsWith("original question")) "$($case.Name) content must preserve the original message after terminal context."
    }
}

$unavailable = Invoke-ChatTestCase -Message @("do not send") -IncludeTerminal -Unavailable
Assert-True ($unavailable.Requests.Count -eq 0) "An unavailable screen buffer must fail before the API request."
Assert-True (
    $null -ne $unavailable.Error -and
    $unavailable.Error.Exception.Message.Contains("omit -IncludeTerminal") -and
    $unavailable.Error.Exception.Message.Contains("No API request was sent")
) "An unavailable screen buffer must produce an actionable error."

$optOut = Invoke-ChatTestCase -Message @("unchanged question") -Unavailable
Assert-True ($null -eq $optOut.Error) "Opt-out invocation must not require a readable screen buffer."
Assert-True ($optOut.Requests.Count -eq 1) "Opt-out invocation should make its normal API request."
if ($optOut.Requests.Count -eq 1) {
    Assert-True ($optOut.Requests[0].messages[1].content -eq "unchanged question") "Opt-out request content must remain unchanged."
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    throw "$($failures.Count) Invoke-ChatGPT test(s) failed."
}

Write-Output "PASS: Invoke-ChatGPT terminal-context tests"
