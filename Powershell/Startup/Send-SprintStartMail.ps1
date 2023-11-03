#Requires -PSEdition Core
[CmdletBinding()]
param(
    [switch]
    $ExportHtml,

    [string[]]
    $Recipient = @("to_tester@rocom.de", "jriedl@rocom.de")
)
Process {
    if ($null -eq $PSBoundParameters.ErrorAction) { $ErrorActionPreference = 'Stop' }
    New-Alias -Name "Invoke-RestApi" -Value "$PSScriptRoot\Invoke-RestApi.ps1" -ErrorAction SilentlyContinue

    # get secrets
    $credentials = Get-Content "$PSScriptRoot/../secrets.json" -Encoding utf8 |
                        ConvertFrom-Json |
                        ForEach-Object Send-SprintStartMail

    # get sprint
    $sprint = Invoke-RestApi -Endpoint 'GET https://dev.azure.com/{organization}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=6.0' |
                        ForEach-Object value |
                        Select-Object -Last 1 |
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
    $sprint.attributes.startDate = [datetime]$sprint.attributes.startDate
    $sprint.attributes.finishDate = [datetime]$sprint.attributes.finishDate
    $sprintStart  = $sprint.attributes.startDate.ToString("dd.MM.yyyy")
    $sprintFinish = $sprint.attributes.finishDate.ToString("dd.MM.yyyy")

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
    foreach ($item in $Recipient) {
        $mail.To.Add($item)
    }
    $mail.Bcc.Add("wpuchinger@rocom-service.de")
    $mail.ReplyTo = "noreply@rocom.de"
    $mail.Subject = "$($sprint.Name) - $($sprintStart) bis $($sprintFinish)"
    $mail.Body    = @"
<style>
* {
    font-family: sans-serif;
}
h1 {
    padding-top: 1em;
    font-size: 1em;
}
table {
    border-collapse: collapse;
    min-width: 400px;
    text-align: left;
}
td, th {
    padding: 6px 15px;
    text-align: left;
}
code {
    color: white;
    background: #2c7acd;
    border-radius: 12px;
    padding: .2rem .5rem;
}
.d0, .d6 { color: lightgrey; }
.sprint  { background: #2c7acd; }
.holiday { background: red; }
.weekend {
    /* background: repeating-linear-gradient(45deg, #2c7acd, #2c7acd 10px, #ffffff00 10px, #ffffff00 18px); */
    background: #2c7acd88;
}
</style>
<p>Sehr geehrte Stakeholder,</p>
<p>ich möchte euch über die Aufgaben des nächsten Sprints informieren.
Der $($sprint.Name) findet statt vom $($sprintStart) bis zum $($sprintFinish).</p>
<p>Hier ist auch ein direkter Link zum Sprint in DevOps: <a href='https://dev.azure.com/rocom-service/TauOffice/_sprints/taskboard/TauOffice%20Team/TauOffice/$($sprint.Name)'>$($sprint.Name)</a></p>

<p><h1>Arbeitsaufgaben:</h1><table>$(
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

<p><h1>Arbeitstage:</h1><table>
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

<p>Diese Informationen sollen euch helfen, eure Arbeit vorzubereiten und alle Fragen, die ihr habt, schon vorab zu klären.</p>

<p>Ich möchte auch darauf hinweisen, dass ihr in DevOps weitere Details zu den Aufgaben einsehen könnt, wie z.B. die Beschreibung der Issues, den aktuellen Arbeitstand und das Burndown-Diagramm. DevOps ist unser zentrales Werkzeug, um den Fortschritt und die Details zu jedem Sprint zu verfolgen und zu überwachen. Bitte nutzt es, um einen umfassenden Überblick über den Sprint zu erhalten.</p>

<p>Falls es Probleme bei der Anmeldung gibt, wendet euch bitte an Wolfgang.</p>

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
}
