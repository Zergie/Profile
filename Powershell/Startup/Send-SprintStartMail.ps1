#Requires -PSEdition Core
[CmdletBinding()]
param(
    [string[]]
    $Recipient = @("to_tester@rocom.de", "rgumberger@rocom.de"),

    [string[]]
    $Bcc = @("wpuchinger@rocom-service.de"),

    [string[]]
    $Cc = @(),

    [double]
    $WaitHours,

    [switch]
    $ExportHtml
)
if ($null -eq $PSBoundParameters.ErrorAction) { $ErrorActionPreference = 'Stop' }
Set-Alias -Name "Invoke-RestApi" -Value "$PSScriptRoot\Invoke-RestApi.ps1"

if ($WaitHours -gt 0) {
    Set-Alias -Name "Wait-Hours" -Value "$PSScriptRoot\Wait-Hours.ps1"
    Wait-Hours -Hours $WaitHours
}

# get secrets
$credentials = Get-Content "$PSScriptRoot/../secrets.json" -Encoding utf8 |
                    ConvertFrom-Json |
                    ForEach-Object Send-SprintStartMail

# get sprint
$sprint = Invoke-RestApi -Endpoint 'GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=6.0' |
                    ForEach-Object value |
                    Where-Object { $_.attributes.finishDate -gt (get-date).AddDays(5)} |
                    Select-Object -First 1 |
                    ForEach-Object {
                        $daysoff = Invoke-RestApi `
                                    -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/capacities?api-version=7.1-preview.3" `
                                    -Variables @{ iterationId = $_.Id }

                        [pscustomobject]@{
                            id                  = $_.id
                            name                = $_.name
                            attributes          = $_.attributes
                            path                = $_.path
                            url                 = $_.url
                            teamMembers         = $daysoff.teamMembers
                            totalCapacityPerDay = $daysoff.totalCapacityPerDay
                            totalDaysOff        = $daysoff.totalDaysOff
                        }
                    }
$sprint.attributes.startDate  = [datetime]$sprint.attributes.startDate
$sprint.attributes.finishDate = [datetime]$sprint.attributes.finishDate
$sprintStart                  = $sprint.attributes.startDate.ToString("dd.MM.yyyy")
$sprintFinish                 = $sprint.attributes.finishDate.ToString("dd.MM.yyyy")

# get holidays
$holidays = (Invoke-RestMethod "https://feiertage-api.de/api/?jahr=$((Get-Date).Year)").BY
$holidays = $holidays |
                Get-Member -Type NoteProperty |
                ForEach-Object{ [pscustomobject]@{holiday=$_.name;date=([datetime]$holidays.($_.name).datum).Date}}

# get issues of sprint
$missing_ids = Invoke-RestApi `
        -Endpoint "GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/workitems?api-version=6.0-preview.1" `
        -Variables @{ iterationId = $sprint.Id } |
        ForEach-Object workItemRelations |
        ForEach-Object target |
        ForEach-Object id

$workitems = @()
while ($missing_ids.Count -gt 0) {
    while ($missing_ids.Count -gt 0) {
        $items = Invoke-RestApi `
                    -Endpoint "GET https://dev.azure.com/{organization}/{project}/_apis/wit/workitems?ids={ids}&`$expand=relations&api-version=6.0" `
                    -Variables @{ ids = ($missing_ids | Select-Object -First 200) -join "," } |
                    ForEach-Object value
        $workitems += $items
        $missing_ids = $missing_ids | Select-Object -Skip 200
    }
}
$workitems = $workitems | Where-Object { $_.fields.'System.WorkItemType' -eq "Issue" }

# compose mail
$mail         = [System.Net.Mail.MailMessage]::new($credentials.Username, $credentials.Username)
$Recipient | ForEach-Object { $mail.To.Add($_) }
$Bcc       | ForEach-Object { $mail.Bcc.Add($_) }
$Cc        | ForEach-Object { $mail.Cc.Add($_) }
$mail.ReplyTo = "noreply@rocom.de"
$mail.Subject = "$($sprint.Name) - $($sprintStart) bis $($sprintFinish)"
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
<p>Sehr geehrte Stakeholder,</p>

<p>ich freue mich, euch über die geplanten Aktivitäten für den bevorstehenden Sprint zu informieren. Der $($sprint.Name) ist für den Zeitraum vom $($sprintStart) bis zum $($sprintFinish) geplant.</p>

<p>Um euch den Zugang zu den detaillierten Informationen zu erleichtern, findet ihr hier einen direkten <a href='https://dev.azure.com/rocom-service/TauOffice/_sprints/taskboard/TauOffice%20Team/TauOffice/$($sprint.Name)'>Link zu $($sprint.Name)</a> in unserem DevOps-System. Dieser Link ermöglicht euch einen schnellen und unkomplizierten Zugriff auf alle relevanten Informationen und Ressourcen, die im Rahmen dieses Sprints von Bedeutung sind.</p>

<p><h1>Arbeitsaufgaben</h1>
<p>$(@(
"Wir haben für euch eine klare Übersicht der geplanten Arbeitsaufgaben im Rahmen des Sprint in Tabellenform zusammengestellt."
"Zur besseren Veranschaulichung und Planung eurer Aktivitäten im Sprint präsentieren wir eine Tabelle der geplanten Arbeitsaufgaben."
"Um euch eine strukturierte Darstellung der geplanten Aufgaben zu bieten, haben wir eine Tabelle mit den Arbeitsaufgaben für den Sprint erstellt."
"Im Sinne einer übersichtlichen Planung und Koordination eurer Aufgaben im Sprint stellen wir euch eine Tabelle der geplanten Arbeitsaufgaben zur Verfügung."
"Die folgende Tabelle bietet eine detaillierte Übersicht über die Arbeitsaufgaben, die im Rahmen des Sprint erledigt werden müssen."
"Wir haben eine tabellarische Übersicht der geplanten Arbeitsaufgaben für den Sprint vorbereitet, um eure Arbeit effizienter zu organisieren."
"Um eure Planung zu erleichtern, haben wir eine Tabelle erstellt, die die geplanten Arbeitsaufgaben und zugehörige Details enthält."
"Die nachfolgende Tabelle gibt euch einen klaren Überblick über die geplanten Arbeitsaufgaben im Sprint und unterstützt eure Planung."
"Wir präsentieren euch eine übersichtliche Tabelle mit den geplanten Arbeitsaufgaben für den bevorstehenden Sprint."
"Damit ihr eure Aufgaben im Sprint besser koordinieren könnt, haben wir eine Tabelle der geplanten Arbeitsaufgaben zusammengestellt."
"Wir möchten euch die Planung und Umsetzung eurer Aufgaben im Sprint erleichtern und bieten dazu eine übersichtliche Tabelle an."
"Zur effizienten Koordination eurer Aufgaben im Sprint findet ihr hier eine Tabelle der geplanten Arbeitsaufgaben."
"Die folgende Tabelle enthält eine klare Aufschlüsselung der geplanten Arbeitsaufgaben für den Sprint."
"Wir haben eine Tabelle erstellt, die euch eine strukturierte Übersicht über die geplanten Arbeitsaufgaben im Sprint bietet."
"Zur besseren Planung und Koordination eurer Aufgaben im Sprint haben wir eine Tabelle der geplanten Arbeitsaufgaben erstellt."
"Die nachfolgende Tabelle veranschaulicht die geplanten Arbeitsaufgaben und bietet euch eine nützliche Übersicht."
"Um euch eine leicht verständliche Übersicht über die bevorstehenden Aufgaben zu bieten, haben wir eine Tabelle vorbereitet."
"Wir haben für euch eine Tabelle zusammengestellt, die die geplanten Arbeitsaufgaben für den Sprint übersichtlich darstellt."
"Die folgende Tabelle gibt euch eine klare Darstellung der geplanten Aufgaben im Rahmen des Sprint."
"Zur effizienten Planung und Umsetzung der Aufgaben im Sprint findet ihr hier eine Tabelle mit den geplanten Arbeitsaufgaben."
) | Get-Random)</p>
<table>$(
$odd = $false
$workitems |
    ForEach-Object {[pscustomobject]@{
        Id    = "<a href='https://dev.azure.com/rocom-service/TauOffice/_workitems/edit/$($_.Id)'>$($_.Id)</a>"
        Title = $_.fields.'System.Title'
        Tags  = ($_.fields.'System.Tags' -split ';') |
                    ForEach-Object { $_.Trim() } |
                    Where-Object Length -GT 0 |
                    ForEach-Object { "<code>$_</code>" } |
                    Join-String
    }} |
    ForEach-Object -Begin   {
        "<thead style='background: #4b8af7' ><tr><th>Id</th><th>Title</th><th>Tags</th></tr></thead>"
        "<tbody>"
    } -Process {
        $odd = (! $odd)
        "<tr style='background: $(if ($odd) { "#ffffff" } else { "#e7effe" })'><td>$($_.Id)</td><td>$($_.Title)</td><td>$($_.Tags)</td></tr>"
    } -End {
        "</tbody>"
    }
)</table></p>


<p><h1>Arbeitstage</h1>
<p>$(@(
"Um euch einen besseren Überblick über die bevorstehenden Arbeitstage im Rahmen des Sprint zu verschaffen, haben wir ein Diagramm erstellt."
"Wir möchten eure Planung für den Sprint vereinfachen und haben daher ein Diagramm der Arbeitstage für die nächsten beiden Wochen vorbereitet."
"Zur Verbesserung eurer Zeitplanung im Sprint haben wir ein Diagramm erstellt, das die Arbeitstage der nächsten zwei Wochen anzeigt."
"Ein nützliches Werkzeug für die bevorstehende Planung des Sprint: Unser Diagramm zeigt die Arbeitstage der nächsten zwei Wochen."
"Wir stellen euch ein hilfreiches Diagramm zur Verfügung, das die Arbeitstage für den Sprint übersichtlich darstellt."
"Um euch bei der Vorbereitung auf den Sprint zu unterstützen, präsentieren wir ein Diagramm, das die Arbeitstage in den nächsten beiden Wochen anzeigt."
"Wir haben ein Diagramm entwickelt, das euch dabei helfen wird, die Arbeitstage für den bevorstehenden Sprint zu veranschaulichen."
"Damit ihr den Überblick behaltet, haben wir ein Diagramm mit den Arbeitstagen für den Sprint erstellt."
"Für eine bessere Planung eurer Aktivitäten im Sprint stellen wir euch ein Diagramm der Arbeitstage zur Verfügung."
"Wir möchten eure Planung für den Sprint erleichtern und haben ein Diagramm mit den Arbeitstagen der nächsten beiden Wochen erstellt."
"Wir haben für euch ein Diagramm vorbereitet, das die Arbeitstage im Rahmen des Sprint veranschaulicht."
"Zur Verbesserung eurer Zeitplanung haben wir ein Diagramm erstellt, das die Arbeitstage für den bevorstehenden Sprint aufzeigt."
"Wir möchten euch eine klare Übersicht über die Arbeitstage im Sprint verschaffen und haben dafür ein Diagramm erstellt."
"Um euch bei der Planung zu unterstützen, haben wir ein Diagramm mit den Arbeitstagen für den bevorstehenden Sprint entwickelt."
"Für eine übersichtlichere Zeitplanung im Sprint bieten wir ein Diagramm der Arbeitstage an."
"Damit ihr eure Arbeitstage im Sprint besser organisieren könnt, haben wir ein Diagramm erstellt."
"Wir präsentieren ein Diagramm, das die Arbeitstage für den bevorstehenden Sprint anschaulich darstellt."
"Zur besseren Planung eurer Aktivitäten im Sprint haben wir ein Diagramm mit den Arbeitstagen erstellt."
"Wir möchten euch eine visuelle Unterstützung für die Planung eurer Arbeitstage im Sprint bieten und haben dafür ein Diagramm vorbereitet."
"Damit ihr die Arbeitstage im Sprint klar im Blick habt, stellen wir euch ein Diagramm zur Verfügung, das sie übersichtlich darstellt."
) | Get-Random)</p>
<table>
$(
$start    = $sprint.attributes.startDate.AddDays(-3)
$end      = $sprint.attributes.finishDate.AddDays(4)
$workdays = 0

"<tr><thead>"
$dat = $start
do {
    "<th class='d$([int]$dat.DayOfWeek)'>$($dat.ToString("ddd dd."))</th>"
    $dat = $dat.AddDays(1)
} while ($dat -lt $end)

"</thead></tr><tr><tbody>"
$dat = $start
do {
    "<td class='$(
        if ($sprint.attributes.startDate -le $dat -and $dat -le $sprint.attributes.finishDate) {
            if ($dat.DayOfWeek -in 0,6) {
                "weekend"
            } elseif ($dat.Date -in $holidays.date) {
                "holiday"
            } else {
                "sprint"
                $workdays += 1
            }
        }
    )'></td>"
    $dat = $dat.AddDays(1)
} while ($dat -lt $end)

"</tbody></tr>"
)</table></p>

<p>$(
$spintHolidays = $holidays |
    Where-Object date -GE $sprint.attributes.startDate |
    Where-Object date -LE $sprint.attributes.finishDate
if ($null -ne $spintHolidays) {
    "<h1>Feiertage:</h1>"
    "<p style='font-size: 0.8em; padding-left: 1em; padding-bottom: 2em'>"
    $spintHolidays | ForEach-Object { "    $($_.date.ToString("dd.MM.yyyy")) - $($_.holiday)<br>" }
    "</p>"
}
)</p>

<p><h1> </h1>
<p>Diese Informationen dienen dazu, euch bestmöglich auf eure bevorstehende Arbeit vorzubereiten und bereits im Voraus alle aufkommenden Fragen zu klären. Unsere Absicht ist es, euch alle notwendigen Details und Ressourcen zur Verfügung zu stellen, damit ihr eure Aufgaben erfolgreich bewältigen könnt.</p>

<p>Es ist wichtig zu betonen, dass ihr in unserem DevOps-System weitere umfassende Informationen zu den anstehenden Aufgaben finden könnt. Dazu gehören nicht nur die Beschreibungen der Issues, sondern auch der aktuelle Fortschrittsstatus sowie das Burndown-Diagramm. DevOps ist unser zentrales Werkzeug, mit dem wir den Fortschritt und die Einzelheiten jedes Sprints verfolgen und überwachen. Es bietet euch die Möglichkeit, einen ganzheitlichen Überblick über den aktuellen Sprint zu gewinnen.</p>

<p>Wir möchten euch ermutigen, DevOps aktiv zu nutzen, um eure Arbeit zu unterstützen und sicherzustellen, dass ihr stets über die neuesten Entwicklungen informiert seid. Solltet ihr Fragen zur Nutzung oder Schwierigkeiten beim Zugriff auf DevOps haben, zögert bitte nicht, euch an mich zu wenden. Ich werde euch gerne weiterhelfen und sicherstellen, dass ihr das System effizient nutzen könnt.</p>
</p>

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
if ($ExportHtml) {
    $file = "$(New-TemporaryFile).html"
    Set-Content -Path $file -Value $mail.Body -Encoding utf8
    Invoke-Item $file
    exit
}

# send mail via smtp
$smtp = [System.Net.Mail.SmtpClient]::new('mail.de2.hostedoffice.ag', 587)
$smtp.Credentials = [System.Net.NetworkCredential]::new($credentials.Username, $credentials.Password)
$smtp.EnableSsl = $true
$smtp.Send($mail)
$smtp.Dispose()

$mail.Attachments | ForEach-Object { $_.Dispose() }
$mail.Dispose()
