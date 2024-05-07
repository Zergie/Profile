[cmdletbinding()]
param(
    [string[]]
    $Recipient = @("fannen@rocom.de"),

    [string[]]
    $Bcc = @("wpuchinger@rocom.de"),

    [string[]]
    $Cc = @("jriedl@rocom.de"),

    [double]
    $WaitHours
)
Set-Alias Get-Issues "$PSScriptRoot/Get-Issues.ps1"

if ($WaitHours -gt 0) {
    $Wait = [TimeSpan]::FromHours($WaitHours)
    Write-Host
    while ($Wait.TotalHours -gt 1) {
        Write-Host "Waiting $($Wait.TotalHours) h, sending @ $([datetime]::Now.Add($Wait).ToString("HH:mm")) .."
        Start-Sleep -Duration ([TimeSpan]::FromHours([System.Math]::Min(1, $Wait.TotalHours)))
        $Wait -= [TimeSpan]::FromHours(1)
    }
    while ($Wait.TotalMinutes -gt 1) {
        Write-Host "Waiting $($Wait.TotalMinutes.ToString("0")) minutes, sending @ $([datetime]::Now.Add($Wait).ToString("HH:mm")) .."
        Start-Sleep -Duration ([TimeSpan]::FromMinutes([System.Math]::Min(10, $Wait.TotalMinutes)))
        $Wait -= [TimeSpan]::FromMinutes(10)
    }
    while ($Wait.TotalSeconds -gt 1) {
        Write-Host "Waiting $($Wait.TotalSeconds.ToString("0")) seconds, sending @ $([datetime]::Now.Add($Wait).ToString("HH:mm")) .."
        Start-Sleep -Duration ([TimeSpan]::FromSeconds([System.Math]::Min(10, $Wait.TotalSeconds)))
        $Wait -= [TimeSpan]::FromSeconds(10)
    }
    Write-Host
}

Push-Location C:\GIT\TauOffice
git fetch --all
$branches = git --no-pager branch --remote --list 'origin/release/*' |
    ForEach-Object { $_.Substring(2) } |
    Sort-Object -Descending |
    Select-Object -First 4 |
    ForEach-Object {
        $root = git --no-pager rev-list ^origin/master "$_" | Select-Object -Last 1
        $s    = $_.Substring("origin/release/".Length).Split('-')
        $tag  = "setup_v$($s[0]).$($s[1]).$($s[2])"
        [pscustomobject]@{
            branch     = $_
            given_name = switch ( $_ ){
                "origin/release/2021-07-16" { "TO 2021/Q2" }
                default {
                    git --no-pager log $root^1..$root --pretty=format:'%B' |
                        Select-String "\d{4}[\\/]Q\d" -AllMatches |
                        ForEach-Object { $_.Matches.Value }
                }
            }
            root       = $root
            commits    = git --no-pager log $root..$_ --pretty=format:'%H,,,%d,,,%B;;;' |
                Out-String |
                ForEach-Object { $_.Split(";;;") } |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_.Length -gt 0 } |
                ForEach-Object {
                    $a   = $_.Split(",,,")

                    [pscustomobject]@{
                        hash=$a[0].Trim()
                        tags=$a[1] |
                            ForEach-Object { $_.Trim(' ', '(', ')') } |
                            ForEach-Object { $_ -replace "tag: ","" } |
                            ForEach-Object { $_.Split(",") } |
                            ForEach-Object { $_.Trim() } |
                            Where-Object   { $_.StartsWith($tag) } |
                            ForEach-Object { $_.Substring("setup_v".Length) }
                        message=($a[2].Split("`n") |
                            Where-Object { $_ -notmatch "^(\s*$|Related work items: #\d+|Cherry picked from !\d+)"}) |
                            Join-String -Separator `n
                        workitems=($a[2] | Select-String "#\d{3,4}" -AllMatches).Matches.Value |
                            Group-Object |
                            ForEach-Object name |
                            ForEach-Object { $_.TrimStart('#') }
                    }
                }
        }
    }
Pop-Location

$msi_files = ssh u266601-sub2@u266601-sub2.your-storagebox.de -p23 tree CD/Tau-Office |
    Where-Object   { $_ -like "*.msi" } |
    ForEach-Object {
        $x = $_.LastIndexOf(" ")
        $_.Substring($x).Trim()
    }

# add workitems and PR
$workitems = $branches.commits.workitems |
    Group-Object |
    ForEach-Object Name |
    ForEach-Object { [int]::Parse($_) }
$workitems = Get-Issues -WorkitemId $workitems
$branches = $branches |
    ForEach-Object {
        $_.commits = $_.commits |
            ForEach-Object {
                $item = $_
                $item.workitems = $workitems | Where-Object ID -In $item.workitems
                $item
            }
        $_
    }

# find workitems that still need work
Write-Host
Write-Host "Workitems that need work:"
Get-Issues -Iteration '@Current Iteration' |
    Where-Object { $_.fields.'System.State' -eq "Done"} |
    Where-Object { $_.fields.'System.Tags'.Length -gt 0 } |
    Where-Object { $_.fields.'System.Tags'.Split(";") -like "TO *" } |
    ForEach-Object {
        $workitem = $_
        $_.fields.'System.Tags'.Split(";") |
            Where-Object { $_ -like "TO *" } |
            ForEach-Object {
                $search = ($_.Substring("TO ".Length))
                [pscustomobject]@{
                    workitem = $workitem.Id
                    tag      = $_
                    found    = $branches |
                            Where-Object given_name -Like $search |
                            ForEach-Object commits |
                            ForEach-Object workitems |
                            Where-Object Id -eq $workitem.Id |
                            Measure-Object |
                            ForEach-Object Count
                }
            }
    } |
    Where-Object found -eq 0 -OutVariable workNeeded
if ($workNeeded.Count -eq 0) {
    Write-Host "None" -ForegroundColor Magenta
}
Write-Host

# write excel
$filename = "${env:temp}/release_notes.xlsx"
Remove-Item $filename -Force -ErrorAction SilentlyContinue

Import-Module ImportExcel
$branches |
    ForEach-Object {
        $branch = $_
        Write-Host -ForegroundColor Cyan "Branch: $($branch.given_name) ($($branch.branch))"

        $output = $branch.commits |
            ForEach-Object {
                [pscustomobject]@{
                    commit   = $_.hash |
                        Where-Object   { $_.Length -gt 0 } |
                        ForEach-Object {
                            $obj = [OfficeOpenXml.ExcelHyperLink]::new("https://dev.azure.com/rocom-service/TauOffice/_git/TauOffice/commit/$_")
                            $obj.Display = $_
                            if ($obj.Display.Length -ne 0) { $obj }
                        }
                    revision = $_.tags |
                        Where-Object   { $_.Length -gt 0 } |
                        ForEach-Object { "tauoffice_$_.msi" } |
                        ForEach-Object {
                            $revision = $_.Split(".")[3]
                            if ($msi_files -contains $_) {
                                $obj = [OfficeOpenXml.ExcelHyperLink]::new("https://u266601-sub2.your-storagebox.de/CD/Tau-Office/Setup$($branch.given_name -replace "[\\/]","_" )/$_")
                                $obj.Display = [string]::new(9) + $revision.PadLeft(3, '0')
                                if ($obj.Display.Length -ne 0) { $obj }
                            } else {
                                [string]::new(9) + $revision.PadLeft(3, '0')
                            }
                        }
                    # message  = $_.message
                    Issue = $_.workitems |
                        ForEach-Object {
                            $obj = [OfficeOpenXml.ExcelHyperLink]::new("https://dev.azure.com/rocom-service/TauOffice/_workitems/edit/$($_.id)")
                            $obj.Display = @($_.id, $_.fields.'System.Title') | Join-String -Separator " - "
                            if ($obj.Display.Length -ne 0) { $obj }
                        }
                }
            } |
            ForEach-Object {
                $item = $_
                if ($item.Issue.Count -eq 0) {
                    $item
                } else {
                    1..($_.Issue.Count) |
                        ForEach-Object {
                            [pscustomobject]@{
                                commit   = $item.commit
                                revision = $item.revision
                                Issue    = $item.Issue | Select-Object -Skip ($_ - 1) -First 1
                            }
                        }
                }
            }

        # $output |
        #     Format-Table

        $ws_name = ($branch.given_name -replace "[\\/]"," " )
        $excel = $output |
            Export-Excel `
                -Path $filename `
                -WorksheetName $ws_name `
                -Title "Tau-Office $($branch.given_name)" `
                -PassThru
        $ws = $excel.Workbook.Worksheets | Select-Object -Last 1
        $PSDefaultParameterValues["*:Worksheet"] = $ws
        Set-ExcelColumn -Column 1 -Width 42 -HorizontalAlignment Left -VerticalAlignment Center -FontColor Black -Underline -UnderLineType None
        Set-ExcelColumn -Column 2 -Width 12 -HorizontalAlignment Center -VerticalAlignment Center -FontColor Black -Underline -UnderLineType None
        Set-ExcelColumn -Column 3 -Width 128 -HorizontalAlignment Left -VerticalAlignment Center -FontColor Black -Underline -UnderLineType None -WrapText
        Set-ExcelRow  -Row 2 -Bold -HorizontalAlignment Left
        $last = $null
        $ws.Cells["A:A"] |
            ForEach-Object {
                if ($null -ne $last -and $_.Value -eq $last.Value) {
                    Set-ExcelRange  -Range "A$($last.Start.row):A$($_.Start.row)" -Merge
                    Set-ExcelRange  -Range "B$($last.Start.row):B$($_.Start.row)" -Merge
                }
                $last = $_
            }
        Set-ExcelRange -Range "A1:C1" -Merge
        $last_commit = ""
        $index = 0
        $color = $null
        $ws.Cells["A:A"] |
            ForEach-Object {
                if ($last_commit -eq $_.Value) {
                } elseif ($_.Start.Row -eq 1) {
                } elseif ($_.Start.Row -eq 2) {
                    Set-Format `
                        -Range "A$($_.Start.Row):C$($_.Start.Row)" `
                        -BackgroundColor ([System.Drawing.Color]::FromArgb(68, 114, 196)) `
                        -ForegroundColor White
                } elseif ($index % 2 -eq 0) {
                    $color = [System.Drawing.Color]::FromArgb(217, 225, 242)
                    $index += 1
                } else {
                    $color = $null
                    $index += 1
                }
                if ($null -ne $color) {
                    Set-Format -Range "A$($_.Start.Row):C$($_.Start.Row)" -BackgroundColor $color
                }
                $last_commit = $_.Value
            }
        Close-ExcelPackage $excel
    }
Remove-Module ImportExcel


if ($Recipient.Count -eq 0) {
    Invoke-Item ${env:TEMP}/release_notes.xlsx
    exit
}

# get secrets
$credentials = Get-Content "$PSScriptRoot/../secrets.json" -Encoding utf8 |
                    ConvertFrom-Json |
                    ForEach-Object Send-SprintStartMail

# compose mail
$mail = [System.Net.Mail.MailMessage]::new($credentials.Username, $credentials.Username)
$Recipient | ForEach-Object { $mail.To.Add($_) }
$Bcc | ForEach-Object { $mail.Bcc.Add($_) }
$Cc | ForEach-Object { $mail.Cc.Add($_) }
$mail.ReplyTo = "noreply@rocom.de"
$mail.Subject = "Release Notes"
$mail.Body    = @"
<style>
/* Allgemeine Schriftart für den gesamten Inhalt */
body {
    font-family: Arial, Helvetica, sans-serif;
}

/* Stil für die Überschrift (h1) */
h1 {
    padding-top: 1em;
    font-size: 1.5em; /* Erhöht die Schriftgröße */
}

</style>
<p>Sehr geehrter Stackholder,</p>

<p>Im Anhang finden Sie die Release Notes der letzten vier Software-Updates unserer Anwendung als XLSX-Datei.
Ich bitte Sie, sich ausreichend Zeit zu nehmen, um die detaillierten Änderungen und Verbesserungen sorgfältig zu überprüfen.
Dies wird Ihnen helfen, bestmöglich auf eventuelle Kundenanfragen vorbereitet zu sein und ein umfassendes Verständnis für die neuesten Entwicklungen in meiner Anwendung zu erlangen.</p>

<p>Bitte beachten Sie, dass die in der XLSX-Datei aufgeführte Revisionsnummer immer an der tau-office.mde orientiert ist.
Das bedeutet, dass wenn es zwischen zwei Setups keine Änderung an der tau-office.mde gibt, z.B. weil nur ein Bug im Admintool behoben wurde, wird das neue Setup die gleiche Revisionsnummer wie das alte Setup tragen.
Dieses Prinzip gilt auch für andere wichtige Komponenten wie die Basisstatistik oder Plugins.
Wenn Änderungen nur in weniger kritischen Teilen des Systems vorgenommen werden, kann dies dazu führen, dass die Revisionsnummer unverändert bleibt, solange die Hauptkomponente (tau-office.mde) unverändert ist.</p>

<p>Ich bitte Sie, das Update so bald wie möglich zu installieren, um sicherzustellen, dass Sie stets von den neuesten Funktionen und Verbesserungen der Software profitieren können.
Ihre Sicherheit und die optimale Leistung der Anwendung sind uns sehr wichtig.</p>

<p>Sollten Sie Fragen haben oder etwas unklar sein, stehe ich Ihnen jederzeit gerne zur Verfügung, um Ihnen weiterzuhelfen.
Zögern Sie nicht, mich zu kontaktieren, falls Sie Unterstützung benötigen.</p>

<p>Vielen Dank für Ihre Aufmerksamkeit und Ihr Verständnis.</p>

<p>Beste Grüße<br>
Wolfgang Puchinger<br>
- Geschäftsführung -<br>
&nbsp;<br>
rocom service GmbH<br>
<a href="http://www.rocom-service.de/" target="_blank">http://www.rocom-service.de</a><br>
&nbsp;<br>
Postanschrift:<br>
rocom service GmbH<br>
Eichenstraße 8b<br>
D-83083 Riedering<br>
Tel.: +49 8036 67482-41<br>
Fax: +49 8036 67482-10<br>
&nbsp;<br>
HRB 28512, Amtsgericht Traunstein&nbsp; - Geschäftsführer: Wolfgang Puchinger<br>
<br>
Der Inhalt dieser E-Mail ist vertraulich und ausschließlich für den bezeichneten Adressaten bestimmt.&nbsp; Wenn Sie nicht der vorgesehene Adressat dieser E-Mail oder dessen Vertreter sein sollten, so beachten Sie bitte, dass jede Form der Kenntnisnahme, Veröffentlichung, Vervielfältigung oder Wiedergabe des Inhalts dieser E-Mail unzulässig ist. Bitte setzen Sie sich in diesem Fall mit dem Absender der&nbsp; E-Mail in Verbindung (<a href="mailto:wpuchinger@rocom-service.de" target="_blank">wpuchinger@rocom-service.de</a>)
</p>
"@
$mail.IsBodyHtml = $true
$mail.Attachments.Add([System.Net.Mail.Attachment]::new($filename))

# send mail via smtp
$smtp = [System.Net.Mail.SmtpClient]::new('mail.de2.hostedoffice.ag', 587)
$smtp.Credentials = [System.Net.NetworkCredential]::new($credentials.Username, $credentials.Password)
$smtp.EnableSsl = $true
$smtp.Send($mail)
$smtp.Dispose()

$mail.Attachments | ForEach-Object { $_.Dispose() }
$mail.Dispose()
