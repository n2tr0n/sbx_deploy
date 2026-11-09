# Windows host setup and troubleshooting

For local Docker Sandboxes (`sbx`) of type `opencode`, run host commands in
**Windows PowerShell**.
Real credentials stay in the host keychain. Sandbox files contain placeholders.
The installer cannot configure or restart the host. Keep host settings outside
sandbox-mounted workspaces. Never put real tokens in logs or chat.

## One-time host setup

### Credentials

Check `sbx secret ls` first. Skip correctly configured entries.
Use ChatGPT subscription OAuth instead of an OpenAI API key:

```powershell
sbx secret set openai --oauth
gh auth status --hostname github.com
# If the host GitHub login is missing or invalid:
# gh auth login --hostname github.com
sbx secret set github --command 'gh auth token --hostname github.com'
```

Create `%APPDATA%\sbx\credentials.yaml` with these bindings.
If the file exists, merge missing entries under the existing keys. Do not
duplicate `bindings:`, service, or mechanism keys. Preserve other entries and domains.
This file holds permissions, not tokens.

```yaml
bindings:
  openai:
    oauth:
      domains:
        - auth.openai.com
        - chatgpt.com
  github:
    apiKey:
      domains:
        - api.business.githubcopilot.com
        - api.enterprise.githubcopilot.com
        - api.github.com
        - api.githubcopilot.com
        - api.individual.githubcopilot.com
        - copilot.github.com
        - github.com
        - raw.githubusercontent.com
```

These settings survive sandbox recreation.

### Context7 registration

In **host PowerShell**, check `sbx mcp ls` and `sbx mcp inspect context7`.
Skip registration if a matching entry exists.

```powershell
# Register only if absent, then complete browser sign-in:
sbx mcp add context7 --url https://mcp.context7.com/mcp/oauth

# Check authorization; run sbx mcp auth context7 if required:
sbx mcp auth status context7
```

Registration and OAuth stay on the host. No API key or
`credentials.yaml` binding is required. Docker Desktop MCP Toolkit registrations
are separate from `sbx mcp`.

[Docker gateway guide](https://docs.docker.com/ai/sandboxes/mcp-gateway/),
[Context7 OAuth guide](https://context7.com/docs/howto/oauth)

## Per-sandbox MCP attachment

For each running sandbox, attach Context7 if absent. Use its name from `sbx ls`:

```powershell
sbx mcp load context7 --sandbox <sandbox-name>
```

Attachments survive restarts. Alternatively, use `--static-mcp context7`
during sandbox creation.

## Headless VS Code tunnel

The installer installs Microsoft's standalone VS Code CLI and the
`vscode_tunnel` alias. The final information box shows the setup commands.
Run the alias in sandbox Bash after deployment. It signs in when needed,
accepts the VS Code Server license terms, and starts a background supervisor.
The supervisor retries after a tunnel exit. A lock prevents duplicate supervisors.
Sign-in and runtime output stay outside deployment logs.
During sign-in, the helper copies the device code to the terminal clipboard.
It then uses the SBX browser bridge to open the GitHub device page on Windows.
If copying fails, copy the displayed code manually. If browser opening fails,
open the displayed URL. The terminal must support clipboard forwarding (OSC 52).
Inside tmux, clipboard copying uses the existing tmux clipboard settings.

If the host page does not open, check `sbx settings get browser.enabled` in
**host PowerShell**. If it is false and you want browser forwarding, run
`sbx settings set browser.enabled true`. This is a global SBX setting.
The installer does not change it. See the
[Docker browser setting](https://docs.docker.com/ai/sandboxes/configuration/settings/#browserenabled).

### One-time startup registration

The standard sandbox runs `sh` as PID 1. It has no active systemd manager.
`/etc/sandbox-persistent.sh` runs on Bash startup, not at sandbox boot.
Use the supplied SBX startup kit for restart support.

In **host PowerShell**, from the SBX Deploy repository, check the sandbox's kit
list with `sbx inspect <sandbox-name>`. Skip attachment if `sbx-vscode-tunnel`
is already present. Inspect the kit, then attach it only if absent:

```powershell
sbx kit validate ./kits/vscode-tunnel --offline
sbx kit inspect ./kits/vscode-tunnel --offline
sbx kit add <sandbox-name> ./kits/vscode-tunnel
```

Kit attachment recreates the sandbox container and interrupts sessions.
Save open work first. Attach the kit before tunnel setup. Then rerun the installer
inside the sandbox if required. Run the installer and `vscode_tunnel` as `agent`
(UID 1000). For another user, supply `--kit-arg user=<user-or-uid>` when you
validate, inspect, and attach the kit. Use the same user for all tunnel commands.
If the installed SBX version rejects startup kits or container recreation, stop
and keep the existing sandbox. Do not reset it. Check `sbx kit add --help`.

The startup kit makes no files or network requests until tunnel setup is enabled.
It starts the enabled supervisor on each sandbox start without a shell login.
Attaching the kit does not start a stopped sandbox after a Windows reboot.
Start that sandbox with `sbx start <sandbox-name>`; its tunnel then starts too.

### Tunnel setup and control

In **sandbox Bash**, after deployment:

```bash
vscode_tunnel
vscode_status
# To stop the tunnel and disable automatic startup:
# vscode_disable
```

Use the same GitHub account in Windows VS Code. Install **Remote - Tunnels**.
Run **Remote Tunnels: Connect to Tunnel**. `vscode_status` shows a status box
with the connection state, startup setting, supervisor state, and tunnel name.
It shows a browser URL when connected. `vscode_tunnel --status` gives the same
output. Status checks do not start the tunnel or sign in.
No sandbox port mapping is required.

The helper stores its own CLI login under
`~/.local/state/sbx-deploy/vscode-tunnel/cli`. The directory is private. The CLI
uses a file credential store with mode 600, separate from its default keyring.
It preserves existing VS Code and `gh` logins. It does not import host credential placeholders. Run
`vscode_tunnel --foreground` to show a connection URL or investigate a failed
connection. Stop the background tunnel first with `vscode_disable`.
Press Ctrl+C to stop a foreground tunnel. Run `vscode_tunnel` to enable startup
again. For expired or revoked authorization, run `vscode_tunnel --login` to authorize
again. This explicit command can replace the tunnel helper's saved login.
Automatic startup continues until disabled; disable can take up to 30 seconds.

An unchanged deployment skips CLI downloads and settings writes. Tunnel setup
runs only when requested. Tunnel runtime can use the network and download
VS Code Server updates. OpenCode and Codex keep their shared models,
authentication, and MCP settings. VS Code AI extensions need separate setup.

If a connection fails, check the sandbox proxy policy from **host PowerShell**.
Use `sbx policy check network <domain>:443`. Allow a required domain only when
no allow rule matches. Downloads need `update.code.visualstudio.com` and
`vscode.download.prss.microsoft.com`. Tunnels also need GitHub or Microsoft
sign-in endpoints and the Azure tunnel endpoints listed in
[Microsoft's network requirements](https://learn.microsoft.com/en-us/azure/developer/dev-tunnels/security#domains).
Keep real tokens out of command output. Do not add token bindings for Azure
tunnel domains. Host-managed tunnel authentication needs separate validation.

[VS Code Remote Tunnels guide](https://code.visualstudio.com/docs/remote/tunnels),
[Docker startup kit reference](https://docs.docker.com/ai/sandboxes/customize/kits-v2/#startup)

## Optional Webtop desktop

Check registry access in **host PowerShell**:

```powershell
sbx policy check network lscr.io:443
# Allow only if no allow rule matches:
sbx policy allow network lscr.io:443
```

Without `--sandbox`, this sets a global default for existing and future sandboxes.
An explicit deny takes precedence. If the pull fails, also check access to
`ghcr.io:443` and `pkg-containers.githubusercontent.com:443`.
A registry `403 Forbidden` can indicate a proxy policy block.

After deployment, check the host port mapping:

```powershell
sbx ls
sbx ports <sandbox-name>
# Publish only if absent:
sbx ports <sandbox-name> --publish 127.0.0.1:3001:3001
```

Open **https://127.0.0.1:3001/** and accept the self-signed certificate.
If host port 3001 is in use, publish another port, such as
`127.0.0.1:3002:3001`, and use it in the URL.
Keep the binding on loopback. Webtop has no login by default.

## Troubleshooting

Confirm the target with **host PowerShell** `sbx ls`.

- GitHub: compare host `gh api user --jq .login` with
  `sbx exec <sandbox-name> gh api user --jq .login`. Both should return the same account.
  If host access works but sandbox access returns 401, run `sbx daemon restart`
  and retry. Restart can interrupt sessions.
- If host GitHub access fails, repair its `gh` login. Then update the source:
  `sbx secret set github --command 'gh auth token --hostname github.com' --force`.
- OpenAI: check for `(oauth configured)` in host `sbx secret ls`.
  Renew with `sbx secret set openai --oauth` if required.
- For persistent failures, run host `sbx daemon status` to find the log path.
  Set `sbx daemon log-level set proxy debug`, reproduce one failure, then restore
  `sbx daemon log-level set proxy info`. Check entries for the target host.
  `skipping mitm (no credentials to inject)` indicates missing active injection.
  Remove tokens before sharing logs.

Avoid `sbx reset`: it deletes sandbox state and stored secrets.

[Docker credential reference](https://docs.docker.com/ai/sandboxes/configuration/credentials/)

