# Cloud sandbox setup

For cloud SBX sandboxes of type `opencode`. Cloud runtime validation is pending.
Use a disposable sandbox first. Run host commands in **Windows PowerShell**
and deployment commands in **sandbox Bash**. Skip completed setup.

## Windows setup

Run [sbx_cloud_host_setup_win.ps1](sbx_cloud_host_setup_win.ps1) from the repository
root in Windows PowerShell 5.1 or PowerShell 7:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sbx_cloud_host_setup_win.ps1
```

Install the [SBX CLI](https://docs.docker.com/ai/sandboxes/) first. Your Docker
account needs cloud access and permission to create billable sandboxes.
The script asks for the sandbox name first. It prepares secrets and network
access, creates an `opencode` sandbox, checks startup prerequisites, then
opens Bash. Paste the complete `sbx_local_opencode_deploy.sh` there and select
**cloud**. The PowerShell script does not run the Bash installer.

Creation uses 2 CPUs, 4 GiB, and a two-hour timeout with the stop action.
Compute is billable while the sandbox runs. Use a disposable sandbox for the
first full script test. The manual direct MCP path passed; the updated full
script flow still needs live validation.

### Keys and MCP

Context7 uses a **global Docker cloud custom secret**. It applies to all new
cloud sandboxes in this Docker account. Configure it before creation:

- Name: `context7`
- Host: `mcp.context7.com`
- Environment placeholder: `CONTEXT7_API_KEY`
- Header: `Authorization`
- Format: `Bearer %s`

Choose **Keep** when this secret already exists. Choose **Add** only when it
is missing. The script shows secret metadata for review. It does not overwrite
an existing key without your explicit selection. Keys use a masked prompt
with `*`, a saving message, and a success message. Values go through standard
input. They do not go in command arguments, receipts, or config files.
OpenAI OAuth uses browser sign-in. Existing host logins stay.

The Bash installer adds direct `context7` connections in OpenCode and Codex
when no existing Docker MCP gateway is configured. Both use
`https://mcp.context7.com/mcp`. Docker's cloud proxy adds the global API key.
The real key stays outside the sandbox. Matching existing client entries and
user overrides stay. A direct connection is separate from Docker's MCP gateway.

The user confirmed real tool calls in both harnesses. Context7 API-key usage
increased for both. No Context7 OAuth login or API-key header in either client
was needed. See [cloud custom secrets](https://docs.docker.com/ai/sandboxes/cloud/credentials/#configure-a-custom-secret).

Docker-managed MCP gateway creation remains a separate open issue. On the
reported SBX v0.53.0 setup, `--static-mcp context7` failed with a missing
`docker` secret. Console creation also failed with Context7 and DeepWiki.
This setup avoids that path. Do not create a guessed `docker` token.

### Controls and reruns

Use numbered menus. Press Enter for a displayed default or a review step.
Creation and recovery of an interrupted creation require `y`; Enter cancels.
Esc cancels menus and confirmations. Use `0` with the line-input fallback.
Line input requires Enter after a choice. Names and masked keys use text
input; Ctrl+C cancels those prompts. `NO_COLOR` disables color. Narrow
terminals use a compact layout.

Receipts contain no credentials. They are under
`%LOCALAPPDATA%\sbx-deploy\cloud`. A completed rerun skips CLI calls and file
writes unless you choose **Recheck cloud state**. Use that choice after
changing Docker accounts, secrets, or sandbox state. A receipt does not prove
that a sandbox still exists. Old gateway-mode receipts require a new review
of the global Context7 key before migration to the direct setup.

If the recorded sandbox is missing, the script checks the cloud list and
inspects its name. When both confirm absence, it offers recreation with y/n.
Check the Docker account before selecting `y`. Review the existing secrets
and choose **Keep** where they still apply. Review network access, then
confirm creation. The script reuses the name without deleting or replacing
cloud secrets. Enter, `n`, or Esc cancels recreation and keeps the receipt.
Other inspection errors stop setup; they do not offer recreation.

The user confirmed that a sandbox-scoped GitHub secret can be reused after
deletion and recreation with the same name. Account access passed before
and after recreation without storing the secret again. A retained secret
can still be expired or invalid; its presence alone does not prove access.

If a command fails, keep the receipt and fix the reported cause. Rerun the
same script. Completed creation is not repeated. If startup lacks the
Context7 placeholder, check the global secret's settings. A sandbox created
before the secret existed needs a fresh creation. Test sandboxes are
disposable. Keep host logins and secrets when replacing a test sandbox.

Unknown or damaged receipts stop setup. Keep them for review. Check the
sandbox and secret metadata before repair. Do not reset policies or delete
host credentials to repair a receipt. Do not run two setups for the same name.

## Manual creation with a sandbox GitHub token


The user confirmed that this setup works for cloud GitHub access.

For a new sandbox, run these commands in **Windows PowerShell**. Keep existing
sandboxes. Replace `repo-a` with your chosen sandbox name in both commands.
Check existing secrets first with `sbx --cloud secret ls`. Complete any missing
OpenAI setup in section 2 before creating the sandbox.

Store the GitHub token for this sandbox:

```powershell
sbx --cloud secret set github --sandbox repo-a
```

Paste the repository token at the secret prompt. Do not put it in the command.
Then create the sandbox with the same name:

```powershell
sbx --cloud create --name repo-a --allow-network mcp.context7.com:443 opencode
```

For another repository, repeat with a different sandbox name and its token.
Prepare the global Context7 custom secret before creation as described above.
A sandbox-scoped GitHub secret overrides the account-scoped GitHub secret.
Use the CLI for these steps. Cloud naming in the TUI is not confirmed.
See [cloud creation](https://docs.docker.com/ai/sandboxes/cloud/usage/#create-a-sandbox)
and [secret scope](https://docs.docker.com/ai/sandboxes/cloud/credentials/#set-credential-scope).
Continue below with the new sandbox name or ID.

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
Do not add an allow rule for a target covered by an intentional deny. The
cloud CLI can replace an exact deny with an allow in the same scope.
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

For a separate GitHub token per sandbox, use the steps at the top of this file.
Only if you want an account-wide GitHub default and it is missing, run:

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

The Bash installer configures direct Context7 in both harnesses when no
existing gateway is configured. The global cloud custom secret must exist
before sandbox creation. No real API key is written into client settings.

The user tested these commands manually inside sandbox Bash:

```bash
opencode mcp add context7 --global --url https://mcp.context7.com/mcp
```

```bash
codex mcp add context7 --url https://mcp.context7.com/mcp
```

Use them only for a missing entry during manual repair. Preserve existing
entries and user edits. Confirm a real Context7 tool call in each harness and
check API-key usage in the Context7 dashboard. A connected status alone does
not prove that the API key is used.

Existing Docker gateways remain supported. Deployment can discover their
URL from existing client config or `SBX_MCP_GATEWAY_URL`. Gateway URLs must
omit real credentials, query strings, and fragments. Existing headers stay
in their original client. Direct Context7 is the tested path for new cloud
sandboxes; local sandboxes keep their host-managed gateway setup.

## 4. Deploy and check

Paste into **sandbox Bash**. After the logo, always confirm the environment.
Press Enter to accept the displayed default, or type `local` or `cloud`.
The installer offers cloud mode when the hostname
matches `sbx-` plus 27 lowercase letters or digits, and local sandbox ID and
agent variables are absent. Credential modes do not select the environment.
These markers match the supplied
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
