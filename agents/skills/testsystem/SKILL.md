---
name: testsystem
description: TauOffice im lokalen Hyper-V-Testsystem über Guacamole und SSH reproduzieren und verifizieren. Verwenden bei Arbeiten an dieser Test-VM, Versionsvergleichen oder Dateiübertragungen dorthin sowie an C:\GIT\buildsystem\test.
---

# Testsystem

VM `Testsystem`, Windows 10, Definition in `C:\GIT\buildsystem\test\main.tf`; Infrastrukturdetails: `C:\GIT\buildsystem\README.md`. Der Basisgast enthält Windows, RDP und SSH. Access, .NET, SQL und TauOffice nur bei Bedarf einrichten; nach einem Neuaufbau fehlen sie wieder. Kein Terraform anwenden oder Disks ersetzen. Die VM startet der Nutzer.

## Zugang und Ausführung

- UI: `http://localhost:8088/guacamole/`, Verbindung **local - Testsystem**. Der Nutzer meldet sich an und öffnet die Verbindung. Bevorzugt Chrome, Browser-Pane als Ausweichlösung; den verfügbaren Browser-Skill verwenden.
- Befehle und Dateien über SSH/SCP/SFTP, Gast-Benutzer **IEUser** explizit angeben: `ssh IEUser@<Gast-IP>`, `scp <Datei> IEUser@<Gast-IP>:<Zielpfad>`. Gast-SSH wird durch `test/Enable-Ssh.ps1` bereitgestellt.
- `.guest-credentials.json` nicht lesen oder ausgeben; Windows-Anmeldung durch den Nutzer oder vorhandene Schlüssel nutzen. SQL-Passwörter und Tokens ebenfalls aus Ausgaben heraushalten.
- Einrichtung und Tests im beauftragten Umfang selbstständig durchführen; bei fehlendem Zugang den Nutzer einbeziehen. Skripte auf dem Host erstellen, übertragen und im Gast mit Logdatei ausführen.

## Versionsvergleich

1. Passenden Altstand und neuen Stand festlegen; Branch, Commit, Build-IDs und die im Setup verwendeten Anwendungs-Builds festhalten.
2. **Vorzugsweise das vollständige MSI-Setup beider Versionen installieren.** Vorhandenes altes Artefakt laden; neue Anwendungsartefakte und danach das Setup auf dem Feature-Branch bauen.
3. Vor jeder Installation Access, TauOffice und Tau-Admin schließen. Datenbank und Mandantendateien sichern und für beide Durchläufe denselben Ausgangsstand **vor der Installation** herstellen, damit auch Setup-Migrationen vergleichbar sind. Denselben Testfall ausführen und Soll-/Ist-Verhalten vergleichen.

Nur bei einem reinen VBA/MDE-Test mit passenden übrigen Komponenten genügt ausnahmsweise der MDE-Tausch: Access schließen, ursprüngliche `C:\Program Files (x86)\Tau-Office\tau-office.mde` sichern und ersetzen. Auch hier identischen Ausgangsdatenstand verwenden und die Einschränkung berichten.

## Builds und Artefakte

Azure DevOps, Projekt `TauOffice`; bei DevOps-Aktionen den `azure-devops`-Skill verwenden. Benötigte Feature-Branch-Pipelines im Testauftrag starten; `master` und `release/*` nur lesen/Artefakte laden.

- `TauOffice MDE` liefert die MDE. Artefakt `drop` per REST laden; `az pipelines runs artifact download` scheitert hier.
- `TauOffice Setup` (`azure-pipelines.yml`) verbaut vorhandene `drop`-Artefakte aus `TauOffice Basisstatistik`, `AdminTool` und `TauOffice MDE`. Die Ressourcen stehen standardmäßig auf `branch: master`: vor einem Feature-Setup die Quellen auf die gewünschten Stände abstimmen und erfolgreiche Builds aller drei Abhängigkeiten sicherstellen. Die Setup-Pipeline baut diese nicht selbst.
- Feature-Builds liefern nur das Artefakt; `master`/`release/*` veröffentlichen zusätzlich auf der Storage Box.

## Gast bei Bedarf einrichten

1. Access-Medium aus `C:\GIT\buildsystem\msaccess\media.iso` bereitstellen; `D:` nicht voraussetzen, da die Test-VM kein Medium konfiguriert.
2. .NET Framework 4.8 (`choco install netfx-4.8`), Neustart, .NET 8 Desktop Runtime **x64**, SQL Server Express (`SQLEXPRESS`). Installer-Prüfungen: `tau-office-installer/Package.wxs`.
3. SQL: Mixed Mode, `sa` aktivieren, zufälliges Passwort setzen, Dienst neu starten.
4. Testdaten: Storage Box per `ssh -p 23 u266601-sub2@u266601-sub2.your-storagebox.de`, Ordner `Testdatenbanken`, bevorzugt Q1–Q4 oder ENTWICKLUNG. ZIPs enthalten `.bak` und Mandantendateien (`CFG`, `Mand0000xx`, `Vorlagen`). Mit `RESTORE DATABASE ... WITH MOVE` nach `InstanceDefaultDataPath` wiederherstellen; Dateien als Mandantenpfad ablegen.
5. `Mandantenpfad=` in der installierten `tau-office.ini`; `Datenquelle.ini` im Mandantenpfad gemäß `Files/DATEN/Datenquelle.ini` mit Datenbank, `INSTANCE=.\SQLEXPRESS`, `USER=sa`, `PASSWORT`. Klartextpasswort wird anschließend verschlüsselt.

Testzugänge ausschließlich für diese Testdatenbanken: TauOffice `rocom/rocom`; Tau-Admin `rocom1/rocom-2020`. Sie gelten nicht für Windows, SQL, Azure oder Storage Box.

## Stolpersteine und Abschluss

- Guacamole verliert gelegentlich Eingaben: kurze Befehle, Return separat, Ergebnis visuell prüfen; längere Skripte per SSH ausführen.
- MSI-Logs sind UTF-16; mit `Select-String` lesen.
- Access 2010: Warnung „Ihre Access Version wird nicht mehr unterstützt!“ kann für den Test bestätigt werden.
- `.ACF`/`.ACM`: Windows-1252 und CRLF erhalten.

Nur selbst angelegte Scratch-Dateien entfernen. Testergebnis mit verwendeten Builds und Änderungen am Gast (Pakete, Datenbanken, Setup/MDE) kurz berichten.
