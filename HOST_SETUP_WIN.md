# Windows host setup and troubleshooting

For local Docker Sandboxes (`sbx`) of type `opencode`.
Run host commands in **Windows PowerShell**. Run the installer in **sandbox Bash**.
The installer cannot configure or restart the host.

Host-managed credentials stay on Windows. Local logins can store credentials
inside the sandbox. Keep host settings outside mounted workspaces.
Never put real tokens in logs or chat.

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

### Local logins

The installer preserves saved login choices on rerun. Local login helpers
override the default host OAuth choice. Host proxy substitution can still apply.
Do not copy real tokens into the managed provider or placeholder files.

### Context7 registration

In **host PowerShell**, check `sbx mcp ls` and `sbx mcp inspect context7`.
Skip registration if a matching entry exists.

```powershell
# Register only if absent, then complete browser sign-in:
sbx mcp add context7 --url https://mcp.context7.com/mcp/oauth

# Check authorization; run sbx mcp auth context7 if required:
sbx mcp auth status context7
```

Context7 needs no API key or `credentials.yaml` binding.
Use `sbx mcp`; Docker Desktop MCP Toolkit registrations are separate.

[Docker gateway guide](https://docs.docker.com/ai/sandboxes/mcp-gateway/),
[Context7 OAuth guide](https://context7.com/docs/howto/oauth)

## Per-sandbox MCP attachment

For each running sandbox, attach Context7 if absent. Use its name from `sbx ls`:

```powershell
sbx mcp load context7 --sandbox <sandbox-name>
```

Attachments survive restarts.

## Optional VS Code tunnel

Use this section to connect Windows VS Code to the sandbox.
No sandbox port mapping is required. VS Code AI extensions need separate setup.

### One-time startup registration

In **host PowerShell**, from the SBX Deploy repository, check the sandbox's kit
list with `sbx inspect <sandbox-name>`. Skip attachment if `sbx-vscode-tunnel`
is already present. Inspect the kit, then attach it only if absent:

```powershell
sbx kit validate ./kits/vscode-tunnel --offline
sbx kit inspect ./kits/vscode-tunnel --offline
sbx kit add <sandbox-name> ./kits/vscode-tunnel
```

Kit attachment recreates the sandbox container and interrupts sessions.
Save open work first. Attach before tunnel setup. Rerun the installer if required.
Run the installer and tunnel as `agent` (UID 1000). For another user, add
`--kit-arg user=<user-or-uid>` to all three kit commands. Use that user for setup.
If SBX rejects the kit, stop. Do not reset the sandbox. Check `sbx kit add --help`.

The kit restarts an enabled tunnel when the sandbox starts. After a Windows
reboot, start the sandbox with `sbx start <sandbox-name>`.

### Tunnel setup and control

In **sandbox Bash**, after deployment:

```bash
vscode_tunnel
vscode_status
# To stop the tunnel and disable automatic startup:
# vscode_disable
```

`vscode_tunnel` accepts the VS Code Server license terms, signs in when needed,
and enables the background tunnel. It copies the device code and opens the
GitHub sign-in page on Windows. If either step fails, use the displayed code
and URL manually. The tunnel keeps a separate login from VS Code and `gh`.

In Windows VS Code, use the same GitHub account. Install **Remote - Tunnels**.
Run **Remote Tunnels: Connect to Tunnel**. Use `vscode_status` to check access.
Use `vscode_disable` to stop the tunnel and disable startup; allow up to 30 seconds.

### Tunnel troubleshooting

If the sign-in page does not open, check `sbx settings get browser.enabled` in
**host PowerShell**. To enable browser forwarding, run
`sbx settings set browser.enabled true`. This changes a global SBX setting.

For expired authorization, run `vscode_tunnel --login`. This replaces the tunnel's
saved login. To investigate a failed connection, run `vscode_disable`, then
`vscode_tunnel --foreground`. Press Ctrl+C to stop. Run `vscode_tunnel` to enable
background startup again.

If a connection fails, check the sandbox proxy policy from **host PowerShell**.
Use `sbx policy check network <domain>:443`. Allow a required domain only when
no allow rule matches. Downloads need `update.code.visualstudio.com` and
`vscode.download.prss.microsoft.com`. Tunnels also need GitHub or Microsoft
sign-in endpoints and the Azure tunnel endpoints listed in
[Microsoft's network requirements](https://learn.microsoft.com/en-us/azure/developer/dev-tunnels/security#domains).
Do not add token bindings for Azure tunnel domains. Use the tunnel's sign-in flow.

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
  Remove tokens before sharing logs.

Avoid `sbx reset`: it deletes sandbox state and stored secrets.

[Docker credential reference](https://docs.docker.com/ai/sandboxes/configuration/credentials/)

