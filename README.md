# This is my profile.

This is my profile used daily on my Windows 10 machine.
Feel free to clone and modify, but I will not accept any PR ;)

PowerShell tests require PowerShell 7, Pester 5.0.0 or newer, and the command-test
dependencies (including Ghostscript and Git). Run the full suite with
`pwsh -NoProfile -File .\Powershell\Tests\Run-Tests.ps1`, internal coverage with
`pwsh -NoProfile -File .\Powershell\Tests\Run-Tests.ps1 -Tag Internal`, or command
coverage with `pwsh -NoProfile -File .\Powershell\Tests\Run-Tests.ps1 -Tag Command`.
Direct `Invoke-Pester -Path .\Powershell\Tests` remains available for debugging.

There are some scripts worth mentioning:

1. **Install-Tools.ps1** : Sets up chocolaty and installs my tools, links configuration files to the default locations.
2. **[codex](codex/README.md)** : Codex configuration and hooks, linked with `Install-Tools.ps1 -junctions` like the other tools.
