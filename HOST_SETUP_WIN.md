# Windows host setup and troubleshooting

For local Docker Sandboxes (`sbx`), run host commands in **Windows PowerShell**.
Real credentials stay in the host keychain; sandbox files contain placeholders.
The sandbox installer cannot configure or restart the host. Keep these settings
outside sandbox-mounted workspaces. Never paste real tokens into logs or chat.

## Setup (once per host)

Check `sbx secret ls` first; skip entries already configured correctly.
Use ChatGPT subscription OAuth, not an OpenAI API key:

```powershell
sbx secret set openai --oauth
gh auth status --hostname github.com
# If the host GitHub login is missing/invalid: gh auth login --hostname github.com
sbx secret set github --command 'gh auth token --hostname github.com'
```

Create `%APPDATA%\sbx\credentials.yaml` with the following bindings. **Merge into
an existing file; preserve other bindings.** This file holds permissions, not tokens.

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

These settings survive sandbox recreation. Afterward, run the current installer
in sandbox Bash; it imports masked OpenCode OAuth and configures Codex routing.
`auth_all` is an optional sandbox-local login, stores credentials there, and does
not disable the host proxy.

## Context7 MCP gateway

Configure Context7 from **host PowerShell**, outside the sandbox installer.
Check `sbx mcp ls` and `sbx mcp inspect context7` first. If a matching registration
already exists, skip registration; check `sbx mcp auth status context7` and run
`sbx mcp auth context7` only if authorization is needed.

```powershell
# Once per host, if context7 is not registered; complete browser sign-in.
sbx mcp add context7 --url https://mcp.context7.com/mcp/oauth

# Once per sandbox: use the target name from sbx ls.
sbx mcp load context7 --sandbox <sandbox-name>
```

The attachment persists across sandbox restarts; skip loading it again after a
successful setup. For a new sandbox, pass `--static-mcp context7` at creation
to preload it. Registration and OAuth credentials remain on the host; Context7
runs remotely. No API key, sandbox package install, or credentials.yaml binding
is needed for this OAuth setup. Docker Desktop MCP Toolkit registrations are
separate from `sbx mcp`.

Supported SBX agent integrations connect to the sandbox gateway at startup.
The installer configures the same gateway URL in OpenCode and Codex, including
Codex installed into an OpenCode sandbox. Host loading alone does not configure
a manually installed harness. For an existing sandbox without the Codex entry,
check `codex mcp list` in **sandbox Bash**, then run this once if absent:

```bash
codex mcp add mcp-gateway --url http://mcp-gateway.docker.internal/mcp
```

Restart Codex after adding the entry and check `/mcp`; tools appear under the
gateway, rather than a separate Context7 server entry. OAuth stays on the host;
do not run a separate Context7 login in Codex. Verify Context7 tools in both
OpenCode and Codex and try a documentation query before considering each
harness verified. The gateway may expose tools through `mcp-exec` or `code-mode`
rather than listing every upstream tool directly.

[Docker gateway guide](https://docs.docker.com/ai/sandboxes/mcp-gateway/) ·
[Context7 OAuth guide](https://context7.com/docs/howto/oauth)

## Troubleshoot

- Confirm the target with **host** `sbx ls`; use its current name below.
- GitHub: compare **host** `gh api user --jq .login` with **host**
  `sbx exec <sandbox-name> gh api user --jq .login`. Both should return the same account.
- If only the sandbox returns 401, verify the secret and binding above, then run
  **host** `sbx daemon restart`. This fixed stale GitHub injection after fresh
  sandbox creation on v0.51.0; stopping/starting the sandbox alone did not.
  Restarting the daemon can interrupt sessions but preserves sandbox files.
- If the host check fails, repair its `gh` login, then update the source with
  `sbx secret set github --command 'gh auth token --hostname github.com' --force`.
- OpenAI: `sbx secret ls` should show `(oauth configured)`; renew with
  `sbx secret set openai --oauth` if needed. A sandbox's credential mode is only
  a hint: it does not prove proxy injection works. Missing `api.responses.write`
  can mean OpenCode is using API routing instead of its imported OAuth record;
  rerun the current installer before changing account permissions.
- Recheck in **sandbox Bash**: `SBX_CHECK_AUTH=1 bash ~/sbx_deploy.sh`.
  Otherwise successful checks are cached. OpenAI's probe checks model-list access,
  not inference; try a new prompt in each harness to verify inference.
- Still failing? **Host** `sbx daemon status` shows the log path. Temporarily run
  `sbx daemon log-level set proxy debug`, reproduce one failure, then restore
  `sbx daemon log-level set proxy info`. Inspect recent entries for the target
  host: `skipping mitm (no credentials to inject)` indicates missing active
  injection. Redact tokens before sharing logs. Avoid `sbx reset`: it deletes
  sandbox state and stored secrets.

[Docker credential reference](https://docs.docker.com/ai/sandboxes/configuration/credentials/)
