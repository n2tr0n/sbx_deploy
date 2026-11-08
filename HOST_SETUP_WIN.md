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

## Optional Webtop desktop

Allow LinuxServer's image registry once per **Windows host**, so existing and
future sandboxes can pull Webtop. Check first and skip adding an already allowed
destination:

```powershell
sbx policy check network lscr.io:443
# If denied because there is no matching allow rule:
sbx policy allow network lscr.io:443
```

Without `--sandbox`, this is a global host default. An explicit deny still takes
precedence. LinuxServer's redirect target `ghcr.io:443` and image blob host
`pkg-containers.githubusercontent.com:443` must also be allowed; check these if
the pull still fails. A `403 Forbidden` while resolving `lscr.io` can be the SBX
proxy rejecting an unlisted registry. Rerun the installer after allowing it;
the sandbox installer cannot edit host policy.

The installer asks on every run whether to deploy/start Ubuntu XFCE Webtop.
Answering No leaves an existing desktop intact. Without terminal input it skips
deployment. Docker must already be available inside the sandbox; the installer
does not install Docker or change its permissions. A running matching container
is reused without pulling an image or rewriting configuration. A stopped one is
started only when you answer Yes. Existing conflicting containers are preserved
and reported rather than replaced. Interrupted downloads/starts can be retried.

After deployment, check the mapping in **host PowerShell**:

```powershell
sbx ls
sbx ports <sandbox-name>
# Only if the mapping is absent:
sbx ports <sandbox-name> --publish 127.0.0.1:3001:3001
```

Open **https://127.0.0.1:3001/** and accept the self-signed certificate. The
installer prints this URL for an existing matching desktop even if deployment
was declined; a stopped desktop is identified as stopped. It cannot verify host
port mappings. If host port 3001 is already used by another sandbox, publish a
different host port (for example `127.0.0.1:3002:3001`) and use that port in the
URL instead. Keep the host binding on loopback: Webtop has no login by default.

The `webtop` container uses `lscr.io/linuxserver/webtop:ubuntu-xfce`, 1 GiB shared
memory, and the `webtop-config` Docker volume at `/config`. The volume survives
container removal, but lives inside this sandbox; deleting the sandbox removes
that storage too. Desktop apps and files are separate from the outer sandbox;
no workspace or Docker socket is mounted. Install desktop applications from a
terminal inside Webtop. Clipboard access may need permission in the outer
browser's site settings.

Run `desktop` inside the sandbox anytime to recall its desktop URL, container
status, and host PowerShell commands for reconnecting and checking/publishing
the port. It only displays information. The suggested name defaults to the
sandbox hostname; confirm it with host `sbx ls`, or pass `desktop <sandbox-name>`.
Disconnecting does not normally remove a port binding. After reconnecting,
`tmux attach` resumes an existing tmux session. If completely disconnected, use
host `sbx ls`, then `sbx exec -it <sandbox-name> bash`, then run `desktop`.

[Webtop documentation](https://docs.linuxserver.io/images/docker-webtop/)

## Troubleshoot

- Confirm the target with **host** `sbx ls`; use its current name below.
- GitHub: compare **host** `gh api user --jq .login` with **host**
  `sbx exec <sandbox-name> gh api user --jq .login`. Both should return the same account.
- On this v0.51.0 Windows setup, **`sbx daemon restart` is typically required
  after creating a sandbox for GitHub credentials to pass through**. Host login
  worked; reapplying the GitHub secret did not fix the sandbox's 401; restarting
  the daemon did. This suggests stale daemon/proxy state, not a missing login.
  Run the restart in host PowerShell, then repeat the sandbox API check.
  It can interrupt sessions but preserves sandbox files. The installer does not
  restart the host daemon.
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
- Run **sandbox** `check_credentials`
  for live GitHub, OpenCode and Codex credential checks and source modes.
  Passthrough uses host placeholders; local login is `auth_all` style. Mixed
  setups are reported per harness. Source detection cannot prove which token
  the host proxy ultimately sent. OpenAI checks model access, not inference;
  MCP OAuth stays on the host and must be checked through each harness's tools.
- Still failing? **Host** `sbx daemon status` shows the log path. Temporarily run
  `sbx daemon log-level set proxy debug`, reproduce one failure, then restore
  `sbx daemon log-level set proxy info`. Inspect recent entries for the target
  host: `skipping mitm (no credentials to inject)` indicates missing active
  injection. Redact tokens before sharing logs. Avoid `sbx reset`: it deletes
  sandbox state and stored secrets.

[Docker credential reference](https://docs.docker.com/ai/sandboxes/configuration/credentials/)
