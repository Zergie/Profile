---
name: remote-server
description: Connect to a remote server or VM for terminal or desktop access. Use when the user wants to log in to, run commands on, copy files to, or look at the screen of a remote machine — via SSH, tailnet-term, or Guacamole.
---

# Remote server access

## Pick the channel

**Hard rule: never use Guacamole as the terminal for the task.** In a Guacamole session, type only the tailnet-term setup commands below. Don't explore the server, search for files or run any task command there, not even "just a quick check". Task commands run over SSH or tailnet-term only.

1. **SSH**: `ssh <user>@<host>`. Run commands non-interactively (`ssh host 'cmd'`), copy with `scp` or `sftp`. If it works, stop here.
2. **tailnet-term**: if SSH fails, set it up through Guacamole (below) right away. A missing server or exe is the normal case, not a reason to skip.
3. **Guacamole as the terminal**: only after tailnet-term setup has actually failed. Tell the user why first.

Use Guacamole freely for GUI work.

### Set up tailnet-term via Guacamole

If an approval check blocks a step (download, running the exe), don't work around it and don't fall back to Guacamole as the terminal. Tell the user what was blocked, quote the reason, and ask them to approve it.

`tailnet-term.exe` lives only in `$env:TEMP\tailnet-term\` (local) and runs straight from `\\tsclient\Guacamole\` (remote). Don't copy it anywhere else.

1. Open Guacamole and the connection to the server, and note the connection name. If you can't get a session, stop and tell the user. In the session, type nothing yet.
2. Locally, download the latest release and create a client key:
   ```powershell
   $dir = New-Item -ItemType Directory -Force "$env:TEMP\tailnet-term"
   $tt  = "$dir\tailnet-term.exe"
   $asset = (Invoke-RestMethod https://api.github.com/repos/Zergie/tailnet-term/releases/latest).assets |
       Where-Object name -like 'tailnet-term-*-windows-x64.exe'
   Invoke-WebRequest $asset.browser_download_url -OutFile $tt
   $sums = Invoke-RestMethod ($asset.browser_download_url -replace '[^/]+$', 'SHA256SUMS.txt')
   $want = (($sums -split "`n") -match [regex]::Escape($asset.name))[0].Split(' ')[0]
   if ((Get-FileHash $tt -Algorithm SHA256).Hash -ne $want) { Remove-Item $tt; throw 'checksum mismatch' }
   & $tt keygen "$dir\client.key"   # prints the public key
   & $tt ip                         # prints this machine's Tailnet IP
   ```
3. Copy `tailnet-term.exe` to the connection's folder on the shared drive (see below).
4. **The user provides the auth key; you never create, read, copy or type it.** Skip this step if `$env:TEMP\tailnet-term.state` already exists on the remote. Otherwise stop and ask the user to set `$env:TS_AUTH_KEY` in the Guacamole session's PowerShell window and to tell you when it's done. They can create a single-use key with either of these:
   - `$env:TS_AUTH_KEY = & \\tsclient\Guacamole\tailnet-term.exe ephemeral-key api` (needs `TAILSCALE_API_KEY`), or `ephemeral-key oauth tag:<tag>`
   - Tailscale admin console → Settings → Keys → Generate auth key (ephemeral), pasted into `$env:TS_AUTH_KEY = '...'`
5. In that same window, start the server in its own window so it keeps running:
   ```powershell
   Start-Process \\tsclient\Guacamole\tailnet-term.exe "server <client-ip> <client-pubkey> `"$((Get-Command pwsh, powershell -ErrorAction Ignore)[0].Source)`" $env:TEMP\tailnet-term.state"
   ```
   Read the server's Tailnet IP from its window.
6. Locally, run each command non-interactively, like ssh: `& $tt client <server-ip> "$dir\client.key" '<command>'`. Put the whole remote command in single quotes so its quotes, pipes and semicolons survive. Never pipe commands into the client's stdin. Check first that `hostname` matches.
   - The command runs in the server's PowerShell without stdin. stdout and stderr arrive separately as UTF-8.
   - The client's exit code is the remote command's. 255 means the connection failed.
   - If the client reports an invalid argument count or an incompatible server, client and server are different releases. Stop and tell the user; don't fall back to piping into stdin.
7. **Switch over**: leave the Guacamole tab alone and do the actual task through tailnet-term. Go back to Guacamole only for GUI work or to restart the server.

On Windows remotes, use `pwsh` first, then `powershell`, then `cmd` (e.g. `ssh host pwsh -NoProfile -Command '...'`).

## Guacamole

- URL: http://127.0.0.1:8088/guacamole/#/ when the instance runs on this machine (check `docker ps` for `guacamole`), otherwise http://10.0.0.44:8088/guacamole/#/.
- Prefer the built-in browser. Let the user sign in; never enter the password yourself.
- Read the remote screen via screenshots; type with the `type` action.

### Copy files to the shared drive (local instance only)

guacd mounts the shared drive at `/drive`; each connection has its own folder (`/drive/<connection-name>/`). On the remote server that folder is `\\tsclient\Guacamole` — read and write files there.

Files go into the **guacd** container (not the `guacamole` web container). Find it by name; if nothing matches, look for the container whose mounts include `/drive`:

```powershell
$guacd = docker ps --filter name=guacd --format '{{.Names}}' | Select-Object -First 1
# fallback: docker ps -q | Where-Object { docker inspect $_ --format '{{range .Mounts}}{{.Destination}} {{end}}' | Select-String '/drive' }
docker exec $guacd ls /drive                                         # list connection folders
docker cp .\file.zip "${guacd}:/drive/<connection-name>/"
docker exec -u root $guacd chown -R guacd:guacd /drive/<connection-name>   # docker cp writes as root
docker cp "${guacd}:/drive/<connection-name>/result.log" .\          # copy back
```

No guacd container in `docker ps` means Guacamole runs elsewhere (10.0.0.44): upload files through the Guacamole UI instead.
