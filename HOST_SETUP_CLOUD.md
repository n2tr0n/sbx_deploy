# Cloud sandbox setup

For cloud SBX sandboxes of type `opencode`. Cloud runtime validation is pending.
Use a disposable sandbox first. Run host commands in **Windows PowerShell**
and deployment commands in **sandbox Bash**. Skip completed setup.

## 1. Find the sandbox

In **Windows PowerShell**:

```powershell
sbx --cloud ls
```

Replace `<sandbox-id>` below with the name or ID from this list.

Record the SBX version, image, and expiration time. Allow enough time for
deployment and validation. Collect a report with
[SANDBOX_VALIDATION.md](SANDBOX_VALIDATION.md) before deployment.

## Check cloud credentials

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

The installer preserves cloud startup credentials and saved logins. It does
not import the local Docker OpenCode OAuth bridge. It uses the shared Codex
OAuth provider only when `SBX_CRED_OPENAI_MODE=oauth` is advertised. The cloud
placeholder contract still needs sandbox validation.

## Connect MCP

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

The installer uses `MCP_GATEWAY_URL` if the sandbox exports it. It does not
assume the local gateway address is valid in cloud mode. If the variable is
absent, find the sandbox gateway URL in the existing agent MCP configuration.
Review the file locally. Do not share its full contents or authentication headers.

Set the URL in **sandbox Bash**, only if needed. Replace the example value:

```bash
export SBX_MCP_GATEWAY_URL='<sandbox-mcp-url>'
```

Use an HTTP or HTTPS URL without credentials, a query string, or a fragment.
Both harnesses use this endpoint. Existing MCP headers and user overrides stay.
Do not put an access token in the URL. If no endpoint is available, stop and
collect evidence before configuration changes. No cloud endpoint is verified
by this repository yet.

## 2. Check network rules

In **Windows PowerShell**, inspect account and sandbox rules:

```powershell
sbx --cloud policy ls
```

```powershell
sbx --cloud policy ls <sandbox-id>
```

## 3. Allow required downloads

Skip this step if all four hosts are already allowed. Keep intentional denies.
For missing Codex or VS Code download access, add a sandbox-scoped rule in
**Windows PowerShell**:

```powershell
sbx --cloud policy allow network "chatgpt.com:443,releases.openai.com:443,update.code.visualstudio.com:443,vscode.download.prss.microsoft.com:443" --sandbox <sandbox-id>
```

## 4. Deploy and check

Paste into **sandbox Bash** and select `cloud` at the environment prompt.
The cloud hostname supplies the default. Press Enter to accept it. For an
explicit selection before the paste, use:

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
selection can reuse it only for the same hostname. On a new sandbox, automatic
selection also accepts a matching cloud hostname and `SBX_SANDBOX_NAME` ID.
The hostname pattern alone supplies only a prompt default. If automatic
selection is unavailable, the installer asks for the environment at the terminal.
Without a terminal, set `SBX_ENV` explicitly.

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
- Cloud OpenCode startup credentials stay unchanged. The local bridge import
  is skipped. Confirm authentication and inference in both harnesses.
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
