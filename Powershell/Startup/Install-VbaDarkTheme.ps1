[cmdletbinding()]
param(
    [Parameter()]
    [switch]
    $ReInstall
)

# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    $p = @{
        FilePath = (Get-Process -PID $PID).Path 
        Verb = "Runas"
        ArgumentList = @(
                            if ($PSBoundParameters.Debug.IsPresent) { "-NoExit" }
                            "-File"
                            "`"$($MyInvocation.MyCommand.Path)`""
                            $MyInvocation.BoundParameters.GetEnumerator() | 
                                ForEach-Object { "-$($_.Key)" }
            ) | Join-String -Separator " "
    }
    $p | ConvertTo-Json | Write-Debug
    Start-Process @p
    exit
}

Get-Process | Where-Object { $_.Name -in "MsAccess","Excel","Outlook","VB6","WinWord" } | ForEach-Object { $_.CloseMainWindow(); Start-Sleep -Seconds 1 }
Get-Process | Where-Object { $_.Name -in "MsAccess","Excel","Outlook","VB6","WinWord" } | Stop-Process -Force | ForEach-Object { Start-Sleep -Seconds 1 }

if ($Reinstall) {
    Get-ChildItem $env:TEMP -Filter VBEThemeColorEditor | Remove-Item -Force -Recurse
}

$vbeThemeColorEditor = Get-ChildItem $env:TEMP -Filter VBEThemeColorEditor | Get-ChildItem -Recurse -Filter VBEThemeColorEditorCli.exe | Select-Object -First 1
if ($null -eq $vbeThemeColorEditor) {
    $msbuild = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\" -Recurse -Filter msbuild.exe | Select-Object -First 1
    $nuget = Get-ChildItem "C:\ProgramData\chocolatey\bin\" -Recurse -Filter nuget.exe | Select-Object -First 1

    $old = Get-Location
    Set-Location $env:TEMP
    git clone https://github.com/rocom-service/VBEThemeColorEditor.git

    Set-Location ./VBEThemeColorEditor/VBEThemeColorEditor
    & $nuget.FullName restore
    & $msbuild.FullName VBEThemeColorEditor.sln
    Set-Location $old
}
$vbeThemeColorEditor = Get-ChildItem $env:TEMP/VBEThemeColorEditor -Recurse -Filter VBEThemeColorEditorCli.exe | Select-Object -First 1

$root = Get-ChildItem \ -Recurse -Filter "AccessAddIn.Test" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $root) {
    $old = Get-Location
    Set-Location $env:TEMP
    git clone https://rocom-service@dev.azure.com/rocom-service/AccessAddin/_git/AccessAddin

    $root = Get-ChildItem -Recurse -Filter "AccessAddIn.Test" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
}
$root = "$($root.FullName)\VbeTheme"

if (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\VB98") {
    Copy-Item "$root\VBA6.DLL" "C:\Program Files (x86)\Microsoft Visual Studio\VB98\VBA6.DLL"
    Copy-Item "$root\VBA6.DLL.BAK" "C:\Program Files (x86)\Microsoft Visual Studio\VB98\VBA6.DLL.BAK"
    Write-Host "VB98 patched" -ForegroundColor Green
} else {
    Write-Host "VB98 not found" -ForegroundColor Red
}

@(
    "C:\Program Files (x86)\Common Files\Microsoft Shared\VBA\VBA7"
    "C:\Program Files (x86)\Common Files\Microsoft Shared\VBA\VBA7.1"
    "C:\Program Files\Microsoft Office 15\root\vfs\ProgramFilesCommonX86\Microsoft Shared\VBA\VBA7.1"
) | ForEach-Object {
    if (Test-Path "$_\VBE7.DLL") {
        & $vbeThemeColorEditor.FullName `
            --Theme "$root\VBE7.DLL" `
            --VBE "$_\VBE7.DLL"
        Write-Host "$_\VBE7.DLL patched" -ForegroundColor Green
    }
}


[pscustomobject]@{
    CodeForeColors = "5 5 12 2 5 15 9 5 5 5 0 0 0 0 0 0"
    CodeBackColors = "2 7 2 16 12 2 2 2 10 2 0 0 0 0 0 0"
    FontFace       = "Consolas"
    FontHeight     = 10
} | 
    ForEach-Object {
        $item = $_

        Get-Member -InputObject $item -MemberType NoteProperty |
            ForEach-Object {
                [pscustomobject]@{Name=$_.Name; Value=$item."$($_.Name)" }
            }
    } |
    ForEach-Object {
        Write-Host -ForegroundColor Green "Writing to registry: $($_.Name) = $($_.Value)"
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\VBA\7.0\Common\" -Name $_.Name -Value $_.Value
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\VBA\7.1\Common\" -Name $_.Name -Value $_.Value
    } 
