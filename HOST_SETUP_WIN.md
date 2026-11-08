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
not disable the host proxy. No sandbox login is needed when host credentials
are configured. Individual overrides are `auth_opencode_openai`,
`auth_codex_openai`, and `auth_gh`; add `--force` to repeat a local login.
Rerun the installer to restore managed OpenCode/Codex defaults.

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

The installer reports detected credential problems with relevant recovery steps
and labels cached successes as previously verified. Its post deployment section
prints `sbx daemon restart`, then the Context7 load command with the sandbox
hostname filled in. Confirm the target with host `sbx ls`; restart when needed,
then attach Context7 if absent. Host attachment is not verified by the installer.
Run sandbox `check_credentials` and
`check_mcp` afterward. Successful installer completion does not verify inference
or upstream MCP authorization.

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

Rerunning the installer preserves an existing desktop.

After deployment, check the mapping in **host PowerShell**:

```powershell
sbx ls
sbx ports <sandbox-name>
# Only if the mapping is absent:
sbx ports <sandbox-name> --publish 127.0.0.1:3001:3001
```

Open **https://127.0.0.1:3001/** and accept the self-signed certificate. The
installer cannot verify host port mappings. If host port 3001 is already used
by another sandbox, publish a
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
- Run **sandbox** `check_credentials` for live GitHub, OpenCode and Codex
  checks and credential sources; `check_mcp` lists brokered MCP servers/tools.
  Passthrough uses host placeholders; local login is `auth_all` style. Mixed
  setups are reported per harness. Source detection cannot prove which token
  the host proxy ultimately sent. OpenAI checks model access, not inference;
  `check_mcp` lists gateway tools and visible OAuth server names; discovery
  wrappers can hide upstream names/tools. Listing does not verify upstream OAuth;
  try a tool in each harness. No tools are executed or servers attached by the check.
- Still failing? **Host** `sbx daemon status` shows the log path. Temporarily run
  `sbx daemon log-level set proxy debug`, reproduce one failure, then restore
  `sbx daemon log-level set proxy info`. Inspect recent entries for the target
  host: `skipping mitm (no credentials to inject)` indicates missing active
  injection. Redact tokens before sharing logs. Avoid `sbx reset`: it deletes
  sandbox state and stored secrets.

[Docker credential reference](https://docs.docker.com/ai/sandboxes/configuration/credentials/)


## Installer updates and recovery

Deployment takes a sandbox-wide lock on root-owned `/run/sbx-deploy.lock`
before saving `~/sbx_deploy.sh`. A competing run exits promptly; retry after the
active run finishes. `flock` (util-linux) must already be available. Local Codex
login stays interactive, then takes the same lock for its configuration update.
Do not delete the lock file to bypass an active run.

Generated helpers retain their existing filenames. Aliases, auth functions, and
prompts now live in `/usr/local/lib/sbx-deploy/shell.bash`; interactive startup
sources that file. User startup files source the separate `path.bash`. The
syslog startup hook remains separate in `/etc/sandbox-persistent.sh`.

If an earlier run failed at `gh-clipboard/xclip.tmp.*` with permission denied,
paste the updated installer and rerun it. No directory deletion or recursive
ownership change is needed: staging handles existing root-owned directories,
new user helpers belong to the invoking user, and existing file metadata is
preserved. Fresh user helper directories are created as the invoking user.

Private baselines live under `${XDG_STATE_HOME:-$HOME/.local/state}/sbx-deploy/managed`,
keyed by the SHA-256 of each absolute managed path (without a trailing newline).
An update accepts the recorded baseline, exact desired contents, or a recognized
historical version when no baseline exists. Markers and filenames alone grant
no ownership. Each file is published atomically before its baseline; an
interruption between those steps is repaired on retry. Identical backups are
reused. Obsolete helpers are retained rather than deleting unrecognized files.

If a helper differs, deployment stops and names its path. Preserve your copy
outside the managed path, then either rename it away so deployment can recreate
it or restore its recorded baseline after reviewing your changes. Keep personal
customizations in a separate file. There is no force-overwrite flag. Edited,
duplicate, or partial startup blocks also stop migration: preserve the startup
file, compare against its prior backup, and restore a complete supported block
or remove the incomplete managed block yourself before retrying. Keep unrelated
startup settings. Shell helpers and startup migrations are preflighted together
before publication; a run interrupted during publication can be retried.

Configuration editors compare their original input immediately before publishing
and stop on an intervening edit. This detects changes but cannot make arbitrary
external editors participate in the deployment lock; avoid editing those files
while deployment runs. New files use publication that cannot overwrite a file
created concurrently.

Unattended limits are 60 seconds for installer downloads, 300 seconds for CLI
installs/upgrades and plugin clones, 30 seconds for credential commands and
credential synchronization lock acquisition, and 15 seconds for version checks.
Processes get five seconds after termination before forced termination; stricter
existing probes retain their limits. APT, Docker image deployment, and interactive
login have no new total deadline. Failures retain their exit status and private
log path; credential subprocess output stays out of installer logs.

OpenCode translates the shared main/subagent defaults into its build/plan and
general/explore agents; Codex uses its model and default-subagent settings.
The schemas differ, while the deployment model values and gateway endpoint stay
equivalent. Host credential substitution and environment overrides are unchanged.

### Sandbox verification checklist

Run these checks in disposable sandboxes; local review only checks syntax and
publication/migration logic.

- Fresh install: paste the entire script and press Enter. Check banner,
  confirmation, compact stages, APT progress, prompts, tmux bindings, logging,
  and all existing auth/check/desktop commands.
- Unchanged rerun: compare managed file timestamps and backup counts; confirm
  no package installs, network calls, configuration rewrites, or new backups.
  Repeat with `SBX_VERBOSE=1`, a limited terminal, and without terminal colors;
  retain only five private run logs.
- Supported upgrades: start from the previous generated helpers and each
  supported legacy shell/auth form, including the original desktop helper.
  Confirm loaders replace the complete recognized blocks and unrelated text survives.
- Edited helpers: change one helper, rerun, and confirm the named file survives
  unchanged and the shell group is not published. Restore/recover as above.
- Partial startup blocks: truncate or edit a loader/legacy block, and duplicate
  a block. Confirm each case stops without rewriting that startup file.
- Interrupted publication: interrupt after helper publication but before baseline
  recording, and between startup-file publications. Retry; check completion,
  ownership recording, preserved user files, and backup reuse.
- Concurrency: hold one deployment open and start another; the second should
  exit promptly before saving or modifying deployment files. Edit a staged
  configuration externally and confirm publication refuses it. Check local Codex
  login waits for the same lock only after interactive authentication.
- Timeouts and parity: stall downloads, clones, upgrades, credential commands,
  version checks, and credential lock acquisition; check bounded failure,
  exit codes, cleanup, and secret-free logs. Confirm OpenCode and Codex still
  share Sol/Luna models, host OAuth placeholders, and the MCP gateway; verify
  inference and Context7 tools manually in both harnesses.
