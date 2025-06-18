[cmdletbinding(DefaultParameterSetName="InvokeParameterSet")]
param(
    [Parameter(Mandatory, Position=0, ParameterSetName="TemplateParameterSet")]
    [string]
    $Template,

    [Parameter(Position=1, ParameterSetName="TemplateParameterSet")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $TemplateArguments,

    [Parameter(Mandatory, ParameterSetName='PrepareParameterSet')]
    [Parameter(Mandatory, ParameterSetName='ExportParameterSet')]
    [Parameter(Mandatory, ParameterSetName='BackupParameterSet')]
    [Parameter(Mandatory, ParameterSetName='InvokeParameterSet')]
    [ValidateNotNullOrEmpty()]
    [string]
    $Database,

    [Parameter(Mandatory, ParameterSetName='PrepareParameterSet')]
    [Parameter(Mandatory, ParameterSetName='ExportParameterSet')]
    [Parameter(Mandatory, ParameterSetName='BackupParameterSet')]
    [Parameter(Mandatory, ParameterSetName='InvokeParameterSet')]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Clients,

    [Parameter(Mandatory, ParameterSetName='PrepareParameterSet', ValueFromPipeline)]
    [Parameter(Mandatory, ParameterSetName='ExportParameterSet', ValueFromPipeline)]
    [Parameter(Mandatory, ParameterSetName='BackupParameterSet', ValueFromPipeline)]
    [Parameter(Mandatory, ParameterSetName='InvokeParameterSet', ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [pscustomobject[]]
    $Articles,

    [Parameter(Mandatory, ParameterSetName='BackupParameterSet')]
    [switch]
    $Backup,

    [Parameter(Mandatory, ParameterSetName='PrepareParameterSet')]
    [switch]
    $Prepare,

    [Parameter(Mandatory, ParameterSetName='ExportParameterSet')]
    [switch]
    $ExportXml,

    [Parameter(ParameterSetName='BillingParameterSet')]
    [switch]
    $Bill
)
dynamicparam {
    Register-ArgumentCompleter -CommandName "Invoke-Article.ps1" -ParameterName "Template" -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
            Select-String -Path $PSCommandPath -Pattern "^#region template|#endregion$" |
                ForEach-Object LineNumber |
                Measure-Object -Minimum -Maximum |
                ForEach-Object {
                    Get-Content $PSCommandPath |
                        Select-Object -Skip ($_.Minimum - 1) -First ($_.Maximum - $_.Minimum - 1)
                } |
                Select-String '^\s*"(?<name>[^"]+)"\s*\{'|
                ForEach-Object Matches |
                ForEach-Object Groups |
                Where-Object Name -eq name |
                ForEach-Object value |
                ForEach-Object { New-Object System.Management.Automation.CompletionResult($_,$_,'ParameterValue', $_) }
    }
}
begin {
    if ($PSCmdlet.ParameterSetName -eq "TemplateParameterSet") {
        $(switch ($PSBoundParameters.Template) {
#region template
            "IsNotSchlussbescheid" {
            "    iif(Nz(Dlookup('Bezeichnung', 'KundenartikelProzess', 'ID={ProzessId}') LIKE 'SchlussBescheid *'),0,1)"
            }

            "PBG" {
            "    iif(IsNull({StammSatzMainID}),"
            "        1,"
            "        DCount2('*',"
            "                'Betreute Personen',"
            "                'Betr_von<=' & DatumSQLnew({RechVon}) & ' AND (Betr_Bis IS NULL OR Betr_Bis>=' & DatumSQLnew({RechVon}) & ') AND StammSatzMainId={StammSatzMainId}'"
            "        )"
            "    )"
            }

            "ChecklisteWohnung" {
            "    Nz("
            "       Dlookup2('Nz(w.$($TemplateArguments[1]), 0)',"
            "                '((Stammdaten_Wohnungen AS sw) INNER JOIN (SELECT * FROM weitereInfos WHERE ID_Label=$($TemplateArguments[0])) AS w ON w.ID_Wohnung=sw.WohnungId)',"
            "                'sw.VON<=' & DatumSQLnew({RechBis}) & ' AND (sw.Bis IS NULL OR sw.Bis>=' & DatumSQLnew({RechBis}) & ') AND sw.PersonId=' & {PersonID}"
            "       ),"
            "       0"
            "    )"
            }

            "IsEinzug" {
            "    -("
            "        Dlookup2('{RechVon} <= [von] AND [von] <= {RechBis} AND [bis] IS NULL',"
            "                  '[Stammdaten_Wohnungen]',"
            "                  'VON<=' & DatumSQLnew({RechVon}) & ' AND (Bis IS NULL OR Bis>=' & DatumSQLnew({RechVon}) & ') AND PersonId=' & {PersonID}"
            "        )"
            "    )"
            }

            "IsAuszug" {
            "    -("
            "        Dlookup2('{RechVon} <= [bis] AND [bis] <= {RechBis}',"
            "                  '[Stammdaten_Wohnungen]',"
            "                  'VON<=' & DatumSQLnew({RechVon}) & ' AND (Bis IS NULL OR Bis>=' & DatumSQLnew({RechVon}) & ') AND PersonId=' & {PersonID}"
            "        )"
            "    )"
            }

            default {
                Write-Error "unknown template"
            }
#endregion
        }) |
            Join-String -Separator `n |
            Out-String
        exit
    }

    Set-Alias Backup-SqlDatabase C:\GIT\Profile\Powershell\Startup\Backup-SqlDatabase.ps1
    Set-Alias Delete-SqlTable C:\GIT\Profile\Powershell\Startup\Delete-SqlTable.ps1
    Set-Alias Import-SqlTable C:\GIT\Profile\Powershell\Startup\Import-SqlTable.ps1
    Set-Alias Invoke-MsAccess C:\GIT\Profile\Powershell\Startup\Invoke-MsAccess.ps1
    Set-Alias Stop-MsAccess C:\GIT\Profile\Powershell\Startup\Stop-MsAccess.ps1
    Set-Alias Update-SqlTable C:\GIT\Profile\Powershell\Startup\Update-SqlTable.ps1
    Set-Alias Invoke-Sqlcmd C:\GIT\Profile\Powershell\Startup\Invoke-Sqlcmd.ps1

    $PSDefaultParameterValues["*:Password"] = "T0bmCL5J"
    $PSDefaultParameterValues["*:Username"] = "sa"
    $PSDefaultParameterValues["Invoke-Sqlcmd:TrustServerCertificate"] = $true
    $PSDefaultParameterValues["*:ServerInstance"] = "127.0.0.1,1433"
    $PSDefaultParameterValues["*:Database"] = $Database
    $MainDatabase = $Database.Split("_") | Select-Object -SkipLast 1 | Join-String -Separator "_"

    if (! $PSBoundParameters.ContainsKey("ErrorAction")) {
        $ErrorActionPreference = 'Stop'
    }

    if ($Prepare) {
        Stop-MsAccess
        Stop-Process -ProcessName MsAccess -ErrorAction SilentlyContinue
        Repair-SqlDatabase $Database

        $PSDefaultParameterValues["*:Database"] = $MainDatabase
        Update-SqlTable -Table ZR_Account -Data @{Stammdaten_BildAnzeige=83}

        $PSDefaultParameterValues["*:Database"] = $Database
        Update-SqlTable -Table Zuteilungsplan -Data @{LetzteVorbelegung=(Get-Date).AddYears(1)}
        Delete-SqlTable -Table Filtereinstellungen
        Invoke-Sqlcmd "UPDATE KundenartikelProzess SET AbrechnenBis=NULL"
        invoke-sqlcmd "UPDATE KundenartikelProzess SET Rechnungsformular=N'None'"

        Invoke-Item C:\GIT\TauOffice\tau-office\bin\tau-office.mdb
        exit

    } elseif ($Backup) {
        Get-ChildItem *.zip | Remove-Item
        Backup-SqlDatabase -Database $MainDatabase,$Database
        Get-ChildItem *.bak | Compress-Archive -DestinationPath $Database -CompressionLevel Optimal
        Get-ChildItem *.bak | Remove-Item
        Get-ChildItem *.zip | ForEach-Object FullName
        exit

    } else {
        Write-Host -ForegroundColor Cyan "Searching for clients .. " -NoNewline
        $persons = Invoke-Sqlcmd "SELECT ID, Name, Vorname, Aktz FROM [Betreute Personen]"
        $persons = $Clients |
            ForEach-Object { $_.Trim() } |
            ForEach-Object {
                $name = $_
                [pscustomobject]@{
                    name = $name
                    id = $persons |
                        Where-Object { "$($_.Name), $($_.Vorname)" -eq $name } |
                        ForEach-Object ID
                }
            }
        if (($persons | Where-Object { $null -EQ $_.ID } | Measure-Object).Count -gt 0) {
            $persons | Format-Table
            throw "Not all names could be found in database!"
        } elseif (($persons | Measure-Object).Count -eq 0) {
            throw "No persons found!"
        } else {
            Write-Host -ForegroundColor Green "$(($persons | Measure-Object).Count) found"
        }
        $persons = $persons.ID

        Write-Host -ForegroundColor Cyan "Searching for processId .. " -NoNewline
        $processId = Invoke-Sqlcmd "SELECT * FROM KundenartikelProzess WHERE Nummernkreis <> 0 AND PersonId IN ($($persons | Join-String -Separator "," ))" |
            Group-Object ProzessVorlageID |
            ForEach-Object { [int]($_.Name) }
        if (($processId | Measure-Object).Count -gt 1) {
            Invoke-Sqlcmd "SELECT ID, PersonId, Bezeichnung, ProzessVorlageID FROM KundenartikelProzess WHERE ID IN ($($processId | Join-String -Separator ","))"
            throw "ProzessVorlageID could not be could not be determined!"
        } else {
            Write-Host -ForegroundColor Green "found id $processId"
        }

        Write-Host -ForegroundColor Cyan "Deleting new data .. " -NoNewline
        Delete-SqlTable Kundenartikel -Criteria "ID >= 1111 and ID <= 1199"
        Delete-SqlTable Kundenartikel ProzessId $processId
        Delete-SqlTable Rechnungen_10060
        Write-Host -ForegroundColor Green "done"

        $p = 10
        $id = 1111
    }
}
process {
    $Articles |
        Add-Member -PassThru -NotePropertyName "ID"         -NotePropertyValue $($id; $id+=1) |
        Add-Member -PassThru -NotePropertyName "Position"   -NotePropertyValue $($p; $p+=10) |
        Add-Member -PassThru -NotePropertyName "ProzessId"  -NotePropertyValue $processId |
        Add-Member -PassThru -NotePropertyName "ErstelltAm" -NotePropertyValue (Get-Date) |
        Add-Member -PassThru -NotePropertyName "GueltigAb"  -NotePropertyValue ([datetime]::new(2000,1,1)) |
        Add-Member -PassThru -NotePropertyName "MwSt"       -NotePropertyValue 3 |
        Import-SqlTable -Table Kundenartikel
}
end {
    if ($ExportXml) {
        Write-Host -ForegroundColor Cyan "Exporting Xml .. " -NoNewline
        $filename = "C:\temp\articles.xml"
        Invoke-Sqlcmd "SELECT * FROM Kundenartikel WHERE ProzessId=$processid AND NOT Beschreibung LIKE N'%DEBUG%'" -As "ReplItem" |
            Set-Content $filename -Encoding 1250

        $keys = "ID","Beschreibung", "Einheit"
        ([xml](Get-Content $filename)).'DatML-RAW-D'.replizierung.replitem.fields |
            ForEach-Object {
                $data = $_
                $obj = @{}
                $keys |
                    ForEach-Object {
                        $key = $_
                        $obj[$key] = $data.field |
                            Where-Object field_fieldname -eq $key |
                            ForEach-Object field_newvalue
                    }
                [pscustomobject]$obj
            } |
            Select-Object $keys |
            ForEach-Object -Begin   {
                Write-Host -ForegroundColor Green "done"
                Write-Host -ForegroundColor Cyan "`nContent of $((Resolve-Path $filename).Path) :"
            } -Process { $_ } |
            Format-Table

    } else {
        if ($null -ne (Get-Process MsAccess -ErrorAction SilentlyContinue)) {
            if (Test-Path "$env:TEMP\KundenartikelProzess.json") {
                Delete-SqlTable KundenartikelProzess -Filter PersonID -Value $persons
                Get-Content "$env:TEMP\KundenartikelProzess.json" |
                    ConvertFrom-Json |
                    Import-SqlTable -Table KundenartikelProzess
            }

            "Abrechnungsdaten","Steuerdatei","Rechnungen_10060" | Delete-SqlTable
            Invoke-Sqlcmd "SELECT * FROM KundenartikelProzess WHERE PersonID IN ($($persons | Join-String -Separator ","))" -OutputAs Json |
                Set-Content "$env:temp\KundenartikelProzess.json"
            Invoke-Sqlcmd "SELECT * FROM Kundenartikel" -OutputAs Json |
                Set-Content "$env:temp\Kundenartikel.json"
            Invoke-Sqlcmd "SELECT * FROM KundenartikelProzess WHERE PersonID IN ($($persons | Join-String -Separator ",")) AND Nummernkreis=7 AND (Aktiv=1)" -OutputAs Json |
                ConvertFrom-Json |
                ForEach-Object {
                    $name = Invoke-Sqlcmd "SELECT id, name, vorname FROM [Betreute Personen] WHERE ID=$($_.PersonID)" |
                                ForEach-Object { "$($_.vorname) $($_.name)" }

                    Write-Host -ForegroundColor Cyan "Billing $name - $($_.Bezeichnung) ($($_.ID)) .. "
                    Invoke-Sqlcmd "UPDATE KundenartikelProzess SET AbrechnenBis=Null WHERE ID=$($_.ID)"

                    Delete-SqlTable Rechnungen_10060 -Filter ID_Rechnung -Value $null
                    Invoke-MsAccess -Procedure test_clsAbrechnung10060_billIndividuell -Arguments $_.ID | Out-Null

                    $data = Invoke-Sqlcmd "SELECT Id, Beschreibung, Anzahl, Preis FROM Rechnungen_10060 WHERE ID_Rechnung IN (SELECT Nr FROM Steuerdatei WHERE Person_ID=$($_.PersonID)) ORDER BY Position" |
                                Sort-Object Beschreibung

                    $colors = [pscustomobject]@{
                        default = @("`e[90m", "`e[0m")
                        1       = @("`e[90m", "`e[38;5;155m")
                        2       = @("`e[90m", "`e[38;5;205m")
                        3       = @("`e[90m", "`e[38;5;166m")
                        4       = @("`e[90m", "`e[38;5;226m")
                        5       = @("`e[90m", "`e[38;5;105m")
                        6       = @("`e[90m", "`e[38;5;189m")
                        7       = @("`e[90m", "`e[38;5;10m")
                        8       = @("`e[90m", "`e[38;5;9m")
                    }
                    $color_index = 0
                    $color_map = @{
                        "" = $colors.default
                    }

                    $data |
                        Where-Object Beschreibung -Like "ZS *" |
                        Group-Object { $_.Beschreibung -replace "^(ZS [^:]+):.*",'$1' } |
                        ForEach-Object {
                            $color_index += 1
                            $color_map.Add($_.Name, $colors."$color_index") | Out-Null
                        }
                    Remove-Variable color_index, colors

                    $data |
                        Where-Object { $_ -ne $null } |
                        ForEach-Object {
                            $color_key = if ($_.Beschreibung.Length -gt 13) { $_.Beschreibung.Substring(0, 13) } else { "" }
                            if (!$color_map.ContainsKey($color_key)) { $color_key = "" }

                            $c = $(if ($_.Anzahl -eq 0) {$color_map[$color_key][0]} else {$color_map[$color_key][1]})
                            $r = "`e[0m"
                            [pscustomobject]@{
                                Beschreibung = "${c}$($_.Beschreibung)"
                                Anzahl       = `
                                if ($_.Anzahl -gt 40000 -and $_.Anzahl -lt 999999) {
                                    $d = [datetime]::new(1900,1,1).AddDays($_.Anzahl-2)
                                    if ($d.Hour -eq 0 -and $d.Minute -eq 0 -and $d.Second -eq 0) {
                                        "${c}$($_.Anzahl) ($($d.ToString("dd.MM.yyyy")))"
                                    } else {
                                        "${c}$($_.Anzahl) ($($d.ToString("dd.MM.yyyy HH:mm")))"
                                    }
                                } else {
                                    "${c}$($_.Anzahl.ToString())"
                                }
                                Preis        = "${c}$([Math]::Round($_.Preis, 2))${r}"
                                ID_Rechnung = $_.ID_Rechnung
                            }
                            if ($_.Beschreibung -match ": P_") {
                                $p_sum += $_.Anzahl
                            }
                        } `
                        -End {
                            # $c = "`e[100m`e[37m"
                            # $r = "`e[0m"
                            # [pscustomobject]@{
                            #     Beschreibung = "${c}P_SUM"
                            #     Anzahl       = "${c}${p_sum}"
                            #     Preis        = "${c}     ${r}"
                            # }
                        } |
                        Format-Table

                    Delete-SqlTable Rechnungen_10060 -Filter ID -Value $data.Id
                }
        } else {
            throw "MsAccess is not running"
        }

        Delete-SqlTable KundenartikelProzess -Filter PersonID -Value $persons
        Get-Content "$env:TEMP\KundenartikelProzess.json" -ErrorAction SilentlyContinue |
            ConvertFrom-Json |
            Import-SqlTable -Table KundenartikelProzess
        Remove-Item "$env:TEMP\KundenartikelProzess.json" -ErrorAction SilentlyContinue
    }

    # nvr -cc "lua require('FTerm').close()"
}
