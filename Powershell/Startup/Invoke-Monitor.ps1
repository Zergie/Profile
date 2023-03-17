#Requires -PSEdition Core
[CmdletBinding()]
param (
    [Parameter(ParameterSetName="ListMonitorsParameterSet")]
    [switch]
    $ListMonitors,

    [Parameter(ParameterSetName="ListValuesParameterSet")]
    [switch]
    $ListValues,

    [Parameter(ParameterSetName="ListValuesParameterSet")]
    [Parameter(ParameterSetName="ReadParameterSet")]
    [Parameter(ParameterSetName="SetParameterSet")]
    [Parameter(ParameterSetName="ChangeParameterSet")]
    [string]
    $Monitor,

    [Parameter(ParameterSetName="ReadParameterSet")]
    [Parameter(ParameterSetName="SetParameterSet")]
    [switch]
    $Brightness,

    [Parameter(ParameterSetName="ReadParameterSet")]
    [Parameter(ParameterSetName="SetParameterSet")]
    [switch]
    $Contrast,

    [Parameter(Mandatory, Position=1, ParameterSetName="SetParameterSet")]
    [int]
    $Value
)
begin {
    $OldPSDefaultParameterValues = $PSDefaultParameterValues.Clone()
    $PSDefaultParameterValues = @{
        'Write-Error:CategoryActivity' = $MyInvocation.MyCommand.Name
        'Write-Progress:Activity'      = $MyInvocation.MyCommand.Name
    }

    $controlmymonitor = try { Get-Command controlmymonitor.exe -ErrorAction Stop }
                        catch { Get-Command 'C:\ProgramData\chocolatey\lib\controlmymonitor\tools\ControlMyMonitor.exe' }
    if ($controlmymonitor.Version -lt [version]::new(1,36,0,0)) {
        throw "controlmymonitor version 1.36.0.0 or greater needed"
    }
}
process {
    $file = New-TemporaryFile

    if ($ListMonitors) {
        Start-Process -Wait -NoNewWindow -FilePath $controlmymonitor.Source -ArgumentList @(
            "/smonitors $($file.FullName)"
        )
        Get-Content $file.FullName |
            Join-String -Separator `; |
            Select-String -Pattern "(([^:;]+):([^;]+);)+" -AllMatches |
            ForEach-Object Matches |
            Group-Object { $_.Groups[2].Captures.Value | Join-String -Separator `; } |
            ForEach-Object {
                $_.Name
                $_.Group |
                ForEach-Object {
                    $_.Groups[3].Captures.Value |
                    Join-String -Separator `;
                }
            }|
            ConvertFrom-Csv -Delimiter `;
    }

    if ($ListValues) {
        Start-Process -Wait -NoNewWindow -FilePath $controlmymonitor.Source -ArgumentList @(
            "/sjson $($file.FullName) $Monitor"
        )
        Get-Content $file |
            ConvertFrom-Json
    }

    $monitors = if ($Monitor.Length -eq 0) {
        @( "\\.\DISPLAY2\Monitor0", "\\.\DISPLAY3\Monitor0" )
    } else {
        @( $Monitor )
    }

    foreach ($key in $PSBoundParameters.Keys) {
        $vcp = switch($key) {
            "Brightness" { 10 }
            "Contrast"   { 12 }
            default      {  0 }
        }

        if ($vcp -ne 0) {
            $monitors |
            ForEach-Object {
                if ("Value" -notin $PSBoundParameters.Keys) {
                    . "$($controlmymonitor.Source)" /GetValue "$_" $vcp
                    [pscustomobject]@{
                        Monitor = $_
                        $key    = $LASTEXITCODE
                    }
                } else {
                    Start-Process -Wait -NoNewWindow -FilePath $controlmymonitor.Source -ArgumentList @(
                        "/SetValue $_ $vcp $Value"
                    )
                }
            }
        }
    }
}
end {
    foreach ($key in @($PSDefaultParameterValues.Keys)) {
        if ($key -in $OldPSDefaultParameterValues.Keys) {
            $PSDefaultParameterValues[$key] = $OldPSDefaultParameterValues.$key
        } else {
            $PSDefaultParameterValues.Remove($key)
        }
    }
}
