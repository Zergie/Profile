[cmdletbinding()]
param(
    [string[]]
    # $Recipient = @("to_tester@rocom.de", "jriedl@rocom.de")
    $Recipient = @("wpuchinger@rocom.de")
)
Set-Alias Get-Issues "$PSScriptRoot/Get-Issues.ps1"

# git fetch --all

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
            commits    = git --no-pager log $root..$_ --pretty=format:'%h,,,%d,,,%B;;;' |
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

$msi_files = ssh u266601-sub2@u266601-sub2.your-storagebox.de -p23 tree CD/Tau-Office |
    Where-Object   { $_ -like "*.msi" } |
    ForEach-Object {
        $x = $_.LastIndexOf(" ")
        $_.Substring($x).Trim()
    }

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

$attachments = @()
$branches |
    ForEach-Object {
        Write-Host -ForegroundColor Cyan "Branch: $($_.given_name) ($($_.branch))"
        $output = $_.commits |
            ForEach-Object {
                [pscustomobject]@{
                    commit   = $_.hash
                    revision = $_.tags |
                        ForEach-Object { "tauoffice_$_.msi" } |
                        ForEach-Object {
                            $revision = $_.Split(".")[3]
                            if ($msi_files -contains $_) {
                                $revision
                            } else {
                                "$revision?"
                            }
                        } |
                        Join-String -Separator ","
                    # message  = $_.message
                    Issue = $_.workitems |
                        ForEach-Object {
                            @($_.id, $_.fields.'System.Title') | Join-String -Separator " - "
                        } |
                        Join-String -Separator `n
                    # Link = $_.workitems |
                    #     Where-Object { $_.Length -gt 0 } |
                    #     ForEach-Object {
                    #         "https://dev.azure.com/rocom-service/TauOffice/_workitems/edit/$($_.id)"
                    #     } |
                    #     Join-String -Separator `n
                }
            }
        $output |
            Format-Table
        $filename = "${env:temp}/$($_.given_name -replace "[\\/]",'').csv"
        $output |
            ConvertTo-Csv -UseQuotes Always -Delimiter `; |
            Set-Content $filename
        $attachments += (Resolve-Path $filename).Path
    }

# get secrets
$credentials = Get-Content "$PSScriptRoot/../secrets.json" -Encoding utf8 |
                    ConvertFrom-Json |
                    ForEach-Object Send-SprintStartMail

# compose mail
$mail = [System.Net.Mail.MailMessage]::new($credentials.Username, $credentials.Username)
$Recipient |
    ForEach-Object { $mail.To.Add($_) }
$mail.Bcc.Add("wpuchinger@rocom-service.de")
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

/* Stil für die gesamte Tabelle */
table {
    border-collapse: collapse;
    min-width: 400px;
    text-align: left;
}

/* Stil für Zellen (td und th) */
td, th {
    padding: 6px 15px; /* Erhöht den Zellenabstand */
    text-align: left;
}

/* Stil für den Code-Block */
code {
    color: white;
    background: #2c7acd;
    border-radius: 12px;
    padding: .2rem .5rem;
}

/* Stil für Datumsklassen */
.d0, .d6 {
    color: lightgrey; /* Ändert die Textfarbe für bestimmte Klassen */
}

/* Stil für Sprint-Klasse */
.sprint {
    background: #2c7acd; /* Hervorhebung des Hintergrunds für Sprint-Elemente */
    color: white; /* Textfarbe für bessere Lesbarkeit auf blauem Hintergrund */
}

/* Stil für Urlaubs-Klasse */
.holiday {
    background: red; /* Hervorhebung des Hintergrunds für Urlaubs-Elemente */
    color: white; /* Textfarbe für bessere Lesbarkeit auf rotem Hintergrund */
}

/* Stil für Wochenend-Klasse */
.weekend {
    background: #2c7acd88; /* Leicht transparenter blauer Hintergrund */
    color: white; /* Textfarbe für bessere Lesbarkeit auf blauem Hintergrund */
}

</style>
<p>Sehr geehrter Stackholder,</p>

anbei finden Sie die Release Notes für das neueste Software-Update unserer Anwendung als CSV-Datei angehängt. Bitte nehmen Sie sich Zeit, um die Änderungen und Verbesserungen zu überprüfen, damit Sie bestens auf eventuelle Kundenanfragen vorbereitet sind.

Wir bitten Sie, das Update umgehend zu installieren, um sicherzustellen, dass Sie die aktuellste Version der Software verwenden.

Bei Fragen oder Unklarheiten stehen wir Ihnen gerne zur Verfügung.

Vielen Dank für Ihre Aufmerksamkeit.

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
$attachments |
    ForEach-Object { [System.Net.Mail.Attachment]::new($_) } |
    ForEach-Object { $mail.Attachments.Add($_) }

# send mail via smtp
$smtp = [System.Net.Mail.SmtpClient]::new('mail.de2.hostedoffice.ag', 587)
$smtp.Credentials = [System.Net.NetworkCredential]::new($credentials.Username, $credentials.Password)
$smtp.EnableSsl = $true
$smtp.Send($mail)
$smtp.Dispose()

$mail.Attachments |
    ForEach-Object { $_.Dispose() }
$mail.Dispose()
