# Codex

Install with `.\Install-Tools.ps1 -junctions` (also included in `-all`).
The regular `Install-Junction` helper hard-links `codex/config.toml` into
`CODEX_HOME/config.toml`, or `$env:USERPROFILE/.codex/config.toml` when
`CODEX_HOME` is unset.

Installation replaces the destination files with the profile versions, just like
other tools. Save any local settings you want to retain before running it.
Hard links require the repository and destination to be on the same volume.
Other hooks, credentials, plugins, caches and sessions stay local.

Generated runtime paths and trust history were omitted from the initial config
snapshot. Codex may write local settings into the linked config; review diffs
before committing. Atomic file replacements can break hard links; preserve any
wanted changes and re-run `-junctions` to restore them.

Restart Codex after installation. See the official
[configuration documentation](https://learn.chatgpt.com/docs/config-file/config-basic).
