[CmdletBinding()]
param (
    [Parameter(Mandatory=$false,
               Position=1,
               ValueFromRemainingArguments=$true)]
    [object[]]
    $Arguments,

    [Parameter(Mandatory=$false,
               ParameterSetName="InspectParameterSetName")]
    [switch]
    $Inspect
)
DynamicParam {
    $RuntimeParameterDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    # param Procedure
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $false
    # $ParameterAttribute.ParameterSetName = "ProcedureParameterSetName"
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(@(
        Get-ChildItem "C:\GIT\TauOffice\tau-office\source\*.acm" |
            ForEach-Object {
                if (!(Get-Content $_ -TotalCount 1).StartsWith("Attribute VB_GlobalNameSpace =")) {
                    $_
                }
            } |
            Select-String -Pattern "^(|Public )(Sub|Function) ([^(]+)" -Encoding 1252 |
            ForEach-Object { $_.Matches.Groups[3].Value }
        "Eval"
        "Application.Quit"
        # "DynaLoader.Unload"
        # "DynaLoader.Load"
    ))
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Procedure", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    # param GetOptionen
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $false
    # $ParameterAttribute.ParameterSetName = "SetOptionenParameterSetName"
    $AttributeCollection.Add($ParameterAttribute)

    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute(
        rg '^.*[GS]et_Optionen[\( ]"([^"]+)"[\), ].*$' "C:\GIT\TauOffice\tau-office\source\" --replace "`$1" --no-filename |
            Group-Object |
            ForEach-Object name
    )
    $AttributeCollection.Add($ValidateSetAttribute)

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("GetOptionen", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    # param SetOptionen
    $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
    $ParameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
    $ParameterAttribute.Position = 0
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.ParameterSetName = "GetOptionenParameterSetName"
    $AttributeCollection.Add($ParameterAttribute)

    $AttributeCollection.Add($ValidateSetAttribute) # reuse from GetOptionen

    $RuntimeParameter = [System.Management.Automation.RuntimeDefinedParameter]::new("SetOptionen", [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($RuntimeParameter.Name, $RuntimeParameter)

    return $RuntimeParameterDictionary
}
process {
$Procedure = $PSBoundParameters.Procedure
$GetOptionen = $PSBoundParameters.GetOptionen
$SetOptionen = $PSBoundParameters.SetOptionen

function Invoke-VBScript {
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $script
    )
    $path = "$($env:TEMP)\script.vbs"
    Set-Content -Path "$path" -Value $script

    $line = 0
    $script -split "`n" |
        ForEach-Object `
            -Begin   {"== vba script ==" } `
            -Process {
                $line++
                $line.ToString().PadRight(3) + $_.ToString()
             } `
            -End     { "== end vba script ==" } |
        Write-Verbose

    cscript.exe "$path" //nologo
    Remove-Item "$path"
}

if ($Inspect) {
    Select-String C:\GIT\TauOffice\tau-office\source\*.acm -Pattern "^(|Public )(Sub|Function) ([^(]+)" |
        Where-Object { $_.Matches.Groups[3].Value -eq $Procedure } |
        ForEach-Object {
            $match = $_

            $procedure_match = Get-Content $match.Path |
                                    Select-Object -Skip ($match.LineNumber-1) |
                                    Out-String |
                                    Select-String -Pattern "(|Public )(Sub|Function).+\n((?!End (Sub|Function)).*\n)*End (Sub|Function)"
            $start = $match.LineNumber
            $count = ($procedure_match.Matches.Value -split "`r`n").Count
            $end =  $start - 1 + $count

            [pscustomobject]@{path=$match.path;start=$start;count=$count;end=$end} | ConvertTo-Json | Write-Debug

            bat $_.path --paging never --line-range $start`:$end
        }

} else {
     if ($null -ne $GetOptionen) {
        $Procedure = "Get_Optionen"
        $Arguments = $GetOptionen
    } elseif ($null -ne $SetOptionen) {
        $Procedure = "Set_Optionen"
        $Arguments = @($SetOptionen, $Arguments)
    }

    if ($Arguments.Count -gt 0) {
        $Arguments = $Arguments |
            ForEach-Object `
                -Begin { "" } `
                -Process {
                    $text = if ($_ -is [System.Management.Automation.ScriptBlock]) { $_.ToString() }
                    else { $_ }

                    if ($text -is [String]) { "`"$( $text -replace '"','`"`"' )`"" }
                    else { $text.ToString() }
                } |
            Join-String -Separator ","
    }

    $Command = switch -Regex ($Procedure) {
        "Eval" {
            "Application.Eval($( $Arguments.SubString(1) ))"
        }
        "Application.Quit" {
            "Application.Quit()"
        }
        "DynaLoader\.(un)?load" {
            # not working! Object not found: 'DynaLoader'
            "Application.Eval(`"$Procedure $( $Arguments.SubString(1) -replace '"','`"`"' )`")"
        }
        default {
            "Application.Run(`"$Procedure`"$Arguments)"
        }
    }

    $LogFile = "C:\GIT\TauOffice\tau-office\bin\TauError.log"
    $LogEntries = Get-Content $LogFile -Encoding 1252 |
                    Measure-Object |
                    ForEach-Object Count

    $wshell = New-Object -ComObject wscript.shell;
    $wshell.AppActivate(((Get-Process MSACCESS).MainWindowTitle)) | Out-Null

    Invoke-VBScript @"
    dim stdout : set stdout = CreateObject("Scripting.FileSystemObject").GetStandardStream(1)
    dim application: set application = GetObject(, "Access.Application")
    dim db: set db = application.CurrentDb()

    dim result: result = $Command

    stdout.Write "{""database"":"
    stdout.Write """" & replace(db.Name, "\", "\\") & """"
    stdout.Write ",""procedure"":""$Procedure"""
    stdout.Write ",""result"":"""
    If IsNull(result) then
        stdout.Write "<null>"
    Else
        stdout.Write replace(result, "\", "\\")
    End If
    stdout.Write """"
    stdout.Write "}"

    set db = Nothing
    set application = Nothing
    set stdout = Nothing
"@ |
    Out-String |
    ForEach-Object {
        $text = $_
        try {
            $result = ConvertFrom-Json $text
            $result.database = ".\" + [System.IO.Path]::GetRelativePath((Get-Location).path, $result.database)
            $result
        } catch {
            Write-Host -ForegroundColor Red "result: $result"
            Write-Host -ForegroundColor Red $text
            throw
        }
    }
    $wshell.AppActivate((Get-Process WindowsTerminal).MainWindowTitle) | Out-Null

    $LogContent = Get-Content $LogFile -Encoding 1252 |
        Select-Object -Skip $LogEntries |
        Out-String

    if ($LogContent.Length -gt 0) {
        @(
            "`e[38;5;238m───────┬─$([string]::new('─', $host.UI.RawUI.WindowSize.Width-9))`e[0m"
            "`e[38;5;238m       │`e[0m File: TauError.log"
            "`e[38;5;238m───────┼─$([string]::new('─', $host.UI.RawUI.WindowSize.Width-9))`e[0m"
            $LogContent.Trim() -split "`r`n" |
                ForEach-Object {
                    "`e[38;5;238m       │`e[0m $_"
                }
            ""
        ) |
            Write-Host -ForegroundColor Yellow
    }
}
}
