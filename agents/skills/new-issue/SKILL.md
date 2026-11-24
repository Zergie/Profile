---
name: new-issue
description: Neue Issues für TauOffice in Azure DevOps (Organisation rocom-service, Projekt TauOffice) formulieren und eintragen. Verwende diesen Skill immer, wenn der Nutzer ein Issue, eine Aufgabe, einen Fehler, ein Wartungsthema oder einen Backlog-Eintrag für Azure DevOps / DevOps / Boards anlegen, erstellen, eintragen, vorbereiten oder formulieren lassen will – auch wenn er nur sagt "mach daraus ein Issue" oder "trag das in DevOps ein". Der Skill erzeugt zuerst nur einen Vorschlag im Chat und trägt erst nach ausdrücklicher Freigabe ein.
---

# Issues in Azure DevOps anlegen

Ziel: Ein Issue so formulieren, dass es ohne Nacharbeit in Azure DevOps passt – gleiche Sprache, gleiches Format und gleiche Pflichtfelder wie die bestehenden Issues. Eingetragen wird erst nach ausdrücklicher Freigabe, weil ein Work Item für das ganze Team sichtbar ist und sich Texte nicht spurlos zurücknehmen lassen.

## Ablauf

1. **Eingabe klären.** Fehlt etwas Wesentliches (was ist das Problem, was soll erreicht werden), frage kurz nach. Andernfalls direkt einen Vorschlag machen – Annahmen im Vorschlag kennzeichnen statt vorab viele Fragen zu stellen.
2. **Vorschlag im Chat zeigen** (Format unten). Nichts in DevOps schreiben.
3. **Auf Freigabe warten.** Als Freigabe gilt nur ein klares Ja des Nutzers im Chat ("ja", "freigegeben", "trag es ein"). Änderungswünsche → Vorschlag überarbeiten und erneut zeigen. Eine Freigabe gilt nur für den gezeigten Stand; wurde danach etwas geändert, erneut freigeben lassen.
4. **Eintragen** mit `scripts/New-DevOpsIssue.ps1` (oder gleichwertig per REST), dann **zurücklesen** und das Ergebnis (ID, Titel, Link) melden.

## Pflichtfelder

| Feld | Wert |
|---|---|
| Typ | immer `Issue` |
| Titel | knapp, beschreibt Problem oder Ziel (siehe Sprache) |
| Priorität (`Microsoft.VSTS.Common.Priority`) | Standard 2; 3 für weniger dringend. Im Zweifel 2 vorschlagen und begründen |
| Effort (`Microsoft.VSTS.Scheduling.Effort`) | **immer füllen**; in TauOffice bedeutet Effort **Aufwand in Stunden** (inkl. Analyse, Umsetzung, Tests), keine Story Points |
| Area Path | `TauOffice` |
| Fristdatum (`Microsoft.VSTS.Scheduling.DueDate`) | **füllen, sobald eine Frist bekannt ist** (z. B. Supportende, Kundentermin, Gesetzesstichtag), sonst leer lassen und nichts erfinden |

Kann der Aufwand nicht seriös geschätzt werden, trotzdem einen Wert vorschlagen und im Vorschlag als vorläufig kennzeichnen. Die Iteration wird bei der Planung gesetzt – nicht vorbelegen, außer der Nutzer nennt sie.

## Kind-Task "Implementierung und Test"

Zu **jedem** Issue gehört ein Kind-Task mit dem Titel `Implementierung und Test` (Typ Task, Area Path `TauOffice`, Priorität wie das Issue, als Child mit dem Issue verknüpft) – so ist es bei den bestehenden Issues üblich, und die Arbeit wird über diesen Task erfasst. Das Skript legt ihn unmittelbar nach dem Issue an; er wird nie ohne das zugehörige Issue und nie nachträglich vergessen. Im Vorschlag wird er als Zeile aufgeführt, damit die Freigabe beides umfasst. Task-Titel und -Priorität nicht eigenmächtig ändern; einen Bearbeiter setzt der Skill nicht.

## Umsetzungsversion (nur TauOffice und TauCloud.Desktop)

Für Issues, die dieses Repo (TauOffice) oder TauCloud.Desktop (auch „TauOffice NEXT Desktop“ genannt) betreffen, muss die Version, in der das Issue umgesetzt werden soll, **ausdrücklich benannt** sein – sie steuert die Quartalsplanung. Nennt der Nutzer sie nicht, frage danach, bevor du einen Vorschlag machst; eine Version wird nie geraten oder aus dem Datum abgeleitet.

Sie wird an zwei Stellen festgehalten, immer übereinstimmend:

- in der Beschreibung als eigene Zeile `Umsetzen in: Q1 26` (Quartal, zweistelliges Jahr), direkt nach der Fristzeile bzw. als erste Zeile, wenn es keine Frist gibt;
- als Tag, z. B. `TO 2026\Q1` (Schema `TO <Jahr>\Q<Quartal>`, im Skript `-Tags "TO 2026\Q1"`).

Diese Regel gilt **nur** für Issues dieses Repos und für TauCloud.Desktop / „TauOffice NEXT Desktop“. Betrifft das Issue ein anderes Repo oder Produkt (z. B. TauServer, Tau-Cloud-Portal), entfallen `Umsetzen in:` und der Versions-Tag, und nach der Version wird nicht gefragt. Ist unklar, zu welchem Repo das Issue gehört, kurz nachfragen.

Ist eine Frist bekannt, steht sie **zusätzlich** als erste Zeile der Beschreibung: `Fristdatum: TT.MM.JJJJ (Anlass)`, z. B. `Fristdatum: 10.11.2026 (Supportende .NET 8)`. So ist sie auch im Text sichtbar.

## Sprache und Stil

- Deutsch, sachlich, Präsens, Sicht des Betriebs/Anwenders ("Mitarbeiter", "Kunde", "Anwender") – nicht des Entwicklers.
- Titel: beschreibend, ohne Satzpunkt, ohne Ticket-Präfix. Fehler als Beobachtung formulieren ("… schlägt fehl", "… wird nicht gespeichert"), Wartungsthemen als Ziel ("… auf .NET 10 LTS migrieren").
- Der Anwender kennt den Quellcode nicht: **keine** Datei-, Klassen-, Methoden-, Funktions- oder Zeilenverweise, keine Code-Bezeichner. Technik nur so weit, wie sie für das Verständnis nötig ist, in Fachsprache ("Strukturupdate", "Installer", "Passwortgültigkeit").
- **Keine Überschriften** (Ursache, Umfang, Akzeptanzkriterien, Fundstellen u. ä.) – das nutzt in Issue-Beschreibungen niemand.
- Zahlen, Versionen und Termine konkret nennen; Quellen als Link angeben.
- Nichts als Kundenmeldung ausgeben, was keine ist: `Aufgenommen durch:` nennt die tatsächliche Quelle (Kunde/Mitarbeiter mit Bezug, "Codeanalyse (keine Kundenmeldung)", "Wartungsthema (kein belegter Kundenausfall)", "Paketprüfung" …).

## Aufbau der Beschreibung

Fließtext in Absätzen mit festen Beschriftungen, in dieser Reihenfolge:

```
[Fristdatum: TT.MM.JJJJ (Anlass)]
[Umsetzen in: Q1 26]   (nur TauOffice und TauCloud.Desktop)

Funktion: <betroffener Bereich>. Aufgenommen durch: <Quelle>.

IST-Stand: <was passiert heute, was ist das Problem / der Ausgangszustand>

SOLL-Stand: <gewünschter Zustand in ein bis zwei Sätzen>

- <konkrete Arbeitsschritte bzw. Prüfpunkte als Aufzählung>
- …
```

Die Aufzählung unter dem SOLL-Stand enthält Umsetzungsschritte und Testfälle (z. B. "Neuinstallation und Update testen"); sie wird im Kind-Task `Implementierung und Test` abgearbeitet. Verweise auf andere Issues im Text als `#1234` schreiben; ist ein inhaltlicher Zusammenhang belegt, im Vorschlag zusätzlich eine Verknüpfung (Related) vorschlagen.

## Vorschlag im Chat

Immer in dieser Form zeigen, damit der Nutzer 1:1 freigeben kann:

```
**Titel:** …

| Feld | Wert |
|---|---|
| Typ | Issue |
| Priorität | 2 |
| Effort | … (Stunden) |
| Fristdatum | TT.MM.JJJJ (Anlass) / – |
| Area Path | TauOffice |
| Umsetzen in / Tag | Q1 26 / `TO 2026\Q1` (entfällt bei anderen Repos als TauOffice und TauCloud.Desktop) |
| Kind-Task | Implementierung und Test (Task, Priorität wie Issue) |
| Verknüpfung | Related zu #… / – |

**Beschreibung:**
<Text wie oben>
```

Schließe mit der Frage, ob eingetragen werden soll. Wurde zuvor eine Entwurfsdatei verlangt (z. B. `ISSUE-VORSCHLAEGE.md`), schreibe den Vorschlag dorthin statt nur in den Chat.

## Eintragen

Erst nach Freigabe. Speichere die Beschreibung als UTF-8-Textdatei `issue-beschreibung.txt` im Repo-Root (Absätze durch Leerzeilen, Aufzählungspunkte mit `- `, Links als `[Text](URL)`), rufe das Skript vom Repo-Root aus auf und lösche die Datei danach wieder:

```powershell
pwsh -File .\.agents\skills\new-issue\scripts\New-DevOpsIssue.ps1 `
  -Title "…" -DescriptionFile .\issue-beschreibung.txt -Priority 2 -Effort 8 `
  [-DueDate 2026-11-10] [-Tags 'TO 2026\Q1'] [-RelatedTo 3964] [-DryRun]
```

`-DryRun` zeigt nur das zu sendende Work Item, ohne zu schreiben. Das Skript:

- verwendet Organisation `https://dev.azure.com/rocom-service` und Projekt `TauOffice` ausdrücklich, weil die `az`-Standardwerte auf eine andere Organisation zeigen können;
- wandelt den Text in HTML (`<p>`, `<ul><li>`), setzt das Fristdatum als lokale Mitternacht in UTC (so speichert es auch die Oberfläche, damit der Tag nicht verrutscht) und sendet UTF-8 per REST;
- legt danach den Kind-Task `Implementierung und Test` an und verknüpft ihn mit dem Issue;
- liest das angelegte Issue zurück und gibt ID, Titel, Priorität, Effort, Fristdatum, Link und die ID des Kind-Tasks aus.

Hinweise aus der Praxis:

- Umlaute in der `az`-Konsolenausgabe können zerstört dargestellt werden, obwohl sie korrekt gespeichert sind. Ob etwas stimmt, zeigt nur der Rücklese-Aufruf des Skripts (REST), nicht `az boards … show`.
- Erst nach dem Zurücklesen "fertig" melden und dabei ID, Link und Abweichungen nennen. Bei Fehlern den Fehlertext zeigen und nichts stillschweigend wiederholen (sonst entstehen Dubletten).
- Bestehende Issues ändern (z. B. Frist nachtragen) ist ein eigener Vorgang: Änderung zeigen, Freigabe abwarten, per PATCH ausführen, zurücklesen.
