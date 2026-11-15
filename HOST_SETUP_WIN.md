# Windows sandbox setup

For local SBX sandboxes of type `opencode`. Run host commands in **Windows
PowerShell** and deployment commands in **sandbox Bash**. Skip completed setup.
Keep host credentials outside mounted workspaces. Preserve existing logins.

## 1. Choose the sandbox

```powershell
sbx ls
```

Replace `<sandbox-name>` below with its name.

## 2. Configure credentials

Check existing entries first:

```powershell
sbx secret ls
```

If OpenAI OAuth is missing, run and complete browser sign-in:

```powershell
sbx secret set openai --oauth
```

Check the host GitHub login:

```powershell
gh auth status --hostname github.com
```

If the login is missing or invalid:

```powershell
gh auth login --hostname github.com
```

If the SBX GitHub entry is missing:

```powershell
sbx secret set github --command 'gh auth token --hostname github.com'
```

Merge these bindings into `%APPDATA%\sbx\credentials.yaml`. Preserve existing
keys and domains. Do not put tokens in this file or duplicate existing keys.

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

## 3. Attach Context7

Check registration:

```powershell
sbx mcp inspect context7
```

If absent, register it and complete browser sign-in:

```powershell
sbx mcp add context7 --url https://mcp.context7.com/mcp/oauth
```

Check authorization:

```powershell
sbx mcp auth status context7
```

If authorization is required:

```powershell
sbx mcp auth context7
```

Attach it to the running sandbox if not already attached:

```powershell
sbx mcp load context7 --sandbox <sandbox-name>
```

Context7 needs no API key or credential binding. Use `sbx mcp` for this setup.

## 4. Deploy and check

Configure any optional startup kit or desktop access below before deployment.
Paste into **sandbox Bash** and select `local` at the environment prompt.
For an explicit selection before the paste, use:

```bash
export SBX_ENV=local
```

Paste the complete `sbx_local_opencode_deploy.sh` as `agent`.
The installer saves this selection for automatic reruns on the same hostname.
If it cannot select the environment, export `SBX_ENV=local` again. A cloud
sandbox uses [HOST_SETUP_CLOUD.md](HOST_SETUP_CLOUD.md).
New timezone setup uses `America/Toronto`; existing timezone settings stay.

If setup fails, follow the printed recovery commands, then rerun:

```bash
bash ~/sbx_local_opencode_deploy.sh
```

After successful setup:

```bash
check_credentials
```

```bash
check_mcp
```

Check a model response in OpenCode and Codex. Rerun the installer unchanged
and confirm it skips installs, downloads, configuration writes, and new backups.

## Optional VS Code tunnel

For automatic startup, save work and attach the startup kit before deployment.
Kit attachment recreates the container and interrupts sessions. Skip attachment
if `sbx inspect <sandbox-name>` already lists `vscode-tunnel`, including a local
path. Choose one source: local or GitHub. Do not attach both.

For the local source kit, run these commands in **Windows PowerShell**.
Wait for deployment to finish before attachment.

```powershell
sbx kit inspect C:\repo\sbx_deploy\kits\vscode-tunnel --resolved --format yaml
```

```powershell
sbx kit add <sandbox-name> C:\repo\sbx_deploy\kits\vscode-tunnel
```

These commands use the local kit. They do not need a published Git reference.
Local kits must be allowed by `kit.allowLocalKits`. Online inspection can load
the v3 source kit. Offline inspection can fail because no kit builder is configured.

For the published kit, use the `main` branch. Do not attach it until inspection
succeeds.

Check the publisher allowlist in **Windows PowerShell**:

```powershell
sbx settings get kit.allowedSources
```

If missing, add `github.com/n2tr0n/` to the full `kit.allowedSources` list.
Preserve all existing entries.

Inspect the v3 kit, then attach it only if inspection succeeds:

```powershell
sbx kit inspect "git+https://github.com/n2tr0n/sbx_deploy.git#ref=main&dir=kits/vscode-tunnel"
```

```powershell
sbx kit add <sandbox-name> "git+https://github.com/n2tr0n/sbx_deploy.git#ref=main&dir=kits/vscode-tunnel"
```

Use user `agent`. For another user, add `--kit-arg user=<user-name>` to both
commands. Use a name, not a numeric UID. Rerun deployment if attachment requires it.

After deployment, in **sandbox Bash**:

```bash
vscode_tunnel
```

Accept the license terms and complete browser sign-in. In Windows VS Code,
install **Remote - Tunnels**. Use the same GitHub account and select
**Remote Tunnels: Connect to Tunnel**.

Check the connection with `vscode_status`. Use `vscode_disable` to stop it and
disable startup. After a host reboot, start the existing sandbox in PowerShell:

```powershell
sbx run --name <sandbox-name> --detach
```

### Tunnel troubleshooting

- **Duplicate kit:** Keep the attached kit. Do not add it again from another source.
- **Disconnected:** Run `vscode_tunnel`, then `vscode_status` in sandbox Bash.
- **Expired login:** Run `vscode_tunnel --login` in sandbox Bash.
- **Stuck process:** Save work. In Windows PowerShell, run
  `sbx stop <sandbox-name>`, then `sbx run --name <sandbox-name> --detach`.
  Run `vscode_tunnel` in sandbox Bash.
- **No sign-in page:** Run `sbx settings set browser.enabled true` in Windows PowerShell.
- **OAuth conflict (409):** Keep the sandbox and bindings. Run `vscode_tunnel`
  after each restart until attachment works.
- **Network failure:** Check [required domains](https://learn.microsoft.com/en-us/azure/developer/dev-tunnels/security#domains).
  Allow only missing access. Do not add token bindings for tunnel domains.

## Optional Webtop desktop

Before choosing Webtop in the installer, check registry access in
**Windows PowerShell**:

```powershell
sbx policy check network lscr.io:443 --sandbox <sandbox-name>
```

If access is missing and not intentionally denied:

```powershell
sbx policy allow network lscr.io:443 --sandbox <sandbox-name>
```

If a registry pull still fails, check `ghcr.io` and
`pkg-containers.githubusercontent.com` on port 443. Keep intentional denies.

After deployment, check ports:

```powershell
sbx ports <sandbox-name>
```

Publish only if the mapping is absent:

```powershell
sbx ports <sandbox-name> --publish 127.0.0.1:3001:3001
```

Open **https://127.0.0.1:3001/** and accept the self-signed certificate.
Use another host port if 3001 is busy. Keep the binding on loopback;
Webtop has no login by default.

## If setup needs repair

### Expired OpenAI OAuth

If OpenCode and Codex report an expired token or Host proxy HTTP 401, renew
OpenAI OAuth in **Windows PowerShell**:

```powershell
sbx secret set openai --oauth
```

Complete browser sign-in. Repeat `check_credentials` and model requests in
sandbox Bash. If the sandbox still uses the expired credential, save work,
then restart the host daemon:

```powershell
sbx daemon restart
```

Reconnect and repeat the checks. Restart can interrupt sessions.
Keep local logins and managed token placeholders unchanged.

### Shell aliases and prompt after reconnect

Paste the updated installer, then check in **sandbox Bash**:

```bash
alias configcat
```

```bash
declare -p PROMPT_COMMAND
```

The hook list should include `_sbx_prompt`. Also check a new tmux pane.

### Image change evidence

Before testing a new image, record these in **Windows PowerShell**:

```powershell
sbx version
```

```powershell
sbx inspect <sandbox-name>
```

Run the sandbox collector using [SANDBOX_VALIDATION.md](SANDBOX_VALIDATION.md).
Remove credentials before sharing output. Keep the sandbox and saved logins;
do not use `sbx reset` to repair setup.
