# Cloud sandbox setup

For cloud SBX sandboxes of type `opencode`. Cloud runtime validation is pending.
Use a disposable sandbox first. Run host commands in **Windows PowerShell**
and deployment commands in **sandbox Bash**. Skip completed setup.

## 1. Allow required downloads

In **Windows PowerShell**:

```powershell
sbx --cloud ls
```

Replace `<sandbox-id>` below with the name or ID from this list.

Record the SBX version, image, and expiration time. Allow enough time for
deployment and validation. Collect a report with
[SANDBOX_VALIDATION.md](SANDBOX_VALIDATION.md) before deployment.

In **Windows PowerShell**, inspect account and sandbox rules:

```powershell
sbx --cloud policy ls
```

```powershell
sbx --cloud policy ls <sandbox-id>
```

Skip this step if all four hosts are already allowed. Keep intentional denies.
For missing Codex or VS Code download access, add a sandbox-scoped rule in
**Windows PowerShell**:

```powershell
sbx --cloud policy allow network "chatgpt.com:443,releases.openai.com:443,update.code.visualstudio.com:443,vscode.download.prss.microsoft.com:443" --sandbox <sandbox-id>
```

## 2. Check cloud credentials

Cloud secrets are separate from local secrets and Docker Agentic Platform
secrets. Local Windows bindings do not configure cloud credentials.

Check metadata before adding credentials:

```powershell
sbx --cloud secret ls
```

If OpenAI OAuth is missing, complete browser sign-in:

```powershell
sbx --cloud secret set openai --oauth
```

Cloud OpenAI OAuth uses account scope. For an API key instead, use
`sbx --cloud secret set openai`. Do not replace an existing credential unless
you intend to change it.

If the GitHub secret is missing:

```powershell
sbx --cloud secret set github
```

Enter the token at the secret prompt. Do not put it in shell commands, files,
or shared output. Cloud secrets do not support the local `--command` resolver.
Configure credentials before creating a new sandbox. For an existing sandbox,
check that its startup credentials are available before deployment.

The installer preserves cloud startup credentials and saved logins. With
`SBX_CRED_OPENAI_MODE=oauth`, it configures both harnesses with shared proxy
placeholders. Cloud OpenCode does not need the local OAuth bridge file.
Its managed OAuth entry uses a fixed future expiry because the cloud proxy
refreshes real tokens. The installer preserves other active logins and an
inactive managed login. It stops if its credential ID contains different
tokens. The user confirmed inference with these placeholders in OpenCode
v2.3.0 after a background service restart. Deployment restarts the cloud
OpenCode service once for the managed OAuth entry. Save work before deployment;
restart can interrupt OpenCode sessions. A success receipt prevents repeat
restarts on unchanged runs. A failed or interrupted restart is retried.
The full installer path and unchanged reruns still need sandbox checks.

### OpenAI HTTP 401 with a stored OAuth secret

An `oauth_refresh` entry confirms that the host has an OAuth secret. It does
not confirm access from an existing sandbox. Docker requires credential setup
before sandbox launch. Keep the existing secret and saved logins.

The credential helper can report `API key` when it selects `OPENAI_API_KEY`.
This label does not confirm that the value is a real API key. The helper tests
`https://api.openai.com/v1/models` for this source. A cloud placeholder can need
a different OAuth route. Confirm the route before changing configuration.

In **sandbox Bash**, print only the advertised mode and key presence:

```bash
printf 'OpenAI mode: %s; OPENAI_API_KEY: %s\n' "${SBX_CRED_OPENAI_MODE:-unset}" "${OPENAI_API_KEY:+set}"
```

An empty key-presence field means the variable is empty or unset. Do not print
the key or auth files. Check a model response in OpenCode and Codex. Record
whether each response works and whether the sandbox started before the secret
was stored. A model-list failure alone does not establish an inference failure.

### GitHub HTTP 401

The helper tests GitHub account access with `gh api user`. `Host proxy` means
it found a proxy placeholder. This label does not confirm a valid cloud secret.
A 401 does not identify the cause. OpenAI access uses a separate credential.

For a sandbox created with the CLI, check metadata in **Windows PowerShell**:

```powershell
sbx --cloud secret ls
```

Check the GitHub entry and its scope. A sandbox-scoped secret takes precedence
over an account-scoped secret. A local secret or Windows GitHub login does not
configure cloud access. If the cloud GitHub secret is missing:

```powershell
sbx --cloud secret set github
```

Enter a valid GitHub token at the prompt. If an entry exists, check its scope
and token validity before replacing it. Do not share the token or auth files.
For a sandbox created in the web UI, check its Docker Agentic Platform secrets.
The CLI cloud store does not supply that interface.

Repeat `check_credentials` in **sandbox Bash**. Docker requires secrets before
sandbox launch. If access still fails, record whether the sandbox started before
the secret was set. Keep the existing sandbox and saved logins. Test a disposable
new sandbox after secret setup to check startup access. Do not reset the working
sandbox or restart the local daemon to repair cloud access.

### OpenCode reports missing scope `api.responses.write`

The user confirmed this recovery in a fresh cloud sandbox:

1. In OpenCode, open `/connect` and select **OpenAI**.
2. Select **Codex device code (legacy)**.
3. Complete browser sign-in with the ChatGPT subscription account.
4. Start a new chat and ask `Reply with OK only.`

This explicit OAuth login produced a model response. An API key is not required
for this tested path. Keep the saved login. Interactive sign-in can store real
credentials inside the sandbox; remove them before saving or moving a template,
as Docker directs. Do not share auth files or authentication headers.

The user also confirmed a stale background service after placeholder import:
standalone inference passed, normal inference failed, and normal inference
passed after the service restart. In sandbox Bash, save work, then run:

```bash
opencode service restart
```

Retry the same model. A passing `check_credentials --openai` tests direct
model-list access, not OpenCode inference or its live endpoint. Do not change
account roles based on this error alone.

## 3. Connect MCP

Connect Context7 through Docker Agentic Platform with the same Docker account.
Cloud sandboxes do not use registrations from local `sbx mcp add`.

Check the cloud sandbox gateway:

```powershell
sbx --cloud mcp ls <sandbox-id>
```

Load Context7 only if absent. Use its connected server name if different:

```powershell
sbx --cloud mcp load context7 --sandbox <sandbox-id>
```

The installer uses `SBX_MCP_GATEWAY_URL` or `MCP_GATEWAY_URL` if set. Otherwise,
it reuses its saved URL or reads the existing `mcp-gateway` entry in OpenCode,
then Codex. OpenCode JSONC takes precedence over JSON. Discovery reads no auth
files and copies no authentication headers. It makes no network requests.

If no endpoint exists, tool setup continues and reports MCP as pending. It
does not create an empty MCP entry or guess the local gateway address. Attach
the server, then rerun. If automatic discovery still finds no URL, review the
agent MCP config locally. Do not share its full contents or authentication headers.

Set the URL in **sandbox Bash**, only if needed. Replace the example value:

```bash
export SBX_MCP_GATEWAY_URL='<sandbox-mcp-url>'
```

Use an HTTP or HTTPS URL without credentials, a query string, or a fragment.
Both harnesses use this endpoint. Existing MCP headers and user overrides stay.
Do not put an access token in the URL. No cloud endpoint is verified by this
repository yet. Existing headers stay in their original harness. If cloud
MCP requires authentication, its equivalent Codex setup still needs validation.

## 4. Deploy and check

Paste into **sandbox Bash**. After the logo, always confirm the environment.
Press Enter to accept the displayed default, or type `local` or `cloud`.
The installer offers cloud mode when the hostname
matches `sbx-` plus 27 lowercase letters or digits, and local sandbox ID, agent,
and credential mode variables are absent. These markers match the supplied
cloud report. If signals are incomplete or conflict, type the environment.
To set the prompt default before the paste, use:

```bash
export SBX_ENV=cloud
```

Paste the complete `sbx_local_opencode_deploy.sh`. It remains one editable file.
No build step or extra deployment files are required. Check the environment row.
Wait for setup to finish. If a download fails, follow the printed recovery
commands, then rerun:

```bash
bash ~/sbx_local_opencode_deploy.sh
```

After successful setup, check credentials and MCP:

```bash
check_credentials
```

```bash
check_mcp
```

The installer saves the environment and MCP URL through its ownership checks.
The default record is `~/.local/state/sbx-deploy/environment`. Automatic
selection can reuse it only for the same hostname. `SBX_ENV` sets the default
before saved and detected settings. Every run still asks for confirmation.
Detection uses the reported combinations; it is not a universal guarantee for
other images. A terminal is required, including when `SBX_ENV` is set.

If setup stopped before saving the record, keep the environment exports set.
If ownership is unknown, preserve the record and its reported baseline.
Review both before repair. Do not delete saved logins.

Check a model response and an MCP tool in OpenCode and Codex. Cloud credential
checks cover selected OpenAI credentials in both harnesses. Model-list access
does not prove inference. Repeat cached checks with:

```bash
SBX_CHECK_AUTH=1 bash ~/sbx_local_opencode_deploy.sh
```

For authentication failures, check cloud secret scope and startup setup.
Do not restart the local daemon to repair cloud access. Interactive harness
sign-in is optional. It writes credentials inside the sandbox. Remove those
credentials before saving a template or moving the sandbox, as Docker directs.

## Supported differences and remaining checks

- Shared models, subagents, tools, shell, tmux, logs, and ownership rules apply
  to both environments. The installer needs a Debian-compatible image, Bash,
  `flock`, and passwordless sudo.
- Cloud OpenCode uses managed OAuth placeholders when OAuth mode is
  advertised. It creates no local bridge file. Startup credentials and
  saved selections stay. Confirm authentication and inference in both harnesses.
- Webtop deployment is disabled in cloud mode. Existing containers stay.
  Cloud port publication creates a public URL. Do not expose the default
  desktop without authentication.
- Run `vscode_tunnel` for remote access and after each cloud restart. Use the
  printed URL and device code if browser forwarding is absent. Cloud tunnel
  operation and startup-kit attachment still need validation.
- Cloud sandboxes have no Windows workspace mount. Transfer files or clone
  a repository inside the sandbox.
- Complete fresh install, unchanged rerun, upgrade and preservation,
  interruption, reconnect, and both harness checks. An unchanged successful
  rerun must skip installs, network calls, config writes, and new backups.

## Sources

- [Cloud credentials](https://docs.docker.com/ai/sandboxes/cloud/credentials/)
- [Cloud commands and MCP setup](https://docs.docker.com/ai/sandboxes/cloud/usage/)
- [Local and cloud differences](https://docs.docker.com/ai/sandboxes/cloud/local-vs-cloud/)
