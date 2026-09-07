# Codex

Install with `.\Install-Tools.ps1 -junctions` (also included in `-all`).
The regular `Install-Junction` helper hard-links these files into `CODEX_HOME`,
or `$env:USERPROFILE/.codex` when it is unset:

| Profile file | Codex location |
| --- | --- |
| `codex/config.toml` | `config.toml` |
| `codex/hooks.json` | `hooks.json` |
| `codex/hooks/deny-ask.ps1` | `hooks/deny-ask.ps1` |

Installation replaces the destination files with the profile versions, just like
other tools. Save any local settings you want to retain before running it.
Hard links require the repository and destination to be on the same volume.
Other hooks, credentials, plugins, caches and sessions stay local.

The hook resolves its script through `CODEX_HOME`, with the same user-profile
fallback. It denies `request_user_input` and `request_user_input_async`, including
their `functions.` names. Essential questions can still be asked in plain text.

Generated runtime paths and trust history were omitted from the initial config
snapshot. Codex may write local settings into the linked config; review diffs
before committing. Atomic file replacements can break hard links; preserve any
wanted changes and re-run `-junctions` to restore them.

Restart Codex after installation and review changed hooks in `/hooks`.
See the official [configuration documentation](https://learn.chatgpt.com/docs/config-file/config-basic)
and [hook documentation](https://learn.chatgpt.com/docs/hooks).
