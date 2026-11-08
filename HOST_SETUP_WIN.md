# Windows host setup and troubleshooting

For local Docker Sandboxes (`sbx`), run host commands in **Windows PowerShell**.
Real credentials stay in the host keychain. Sandbox files contain placeholders.
The installer cannot configure or restart the host. Keep host settings outside
sandbox-mounted workspaces. Never put real tokens in logs or chat.

## Host setup

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
**If the file exists, add the bindings without replacing other entries.**
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

These settings survive sandbox recreation. Run the current installer in sandbox
Bash. It imports masked OpenCode OAuth and configures Codex routing.
Host credentials require no sandbox login.

For an optional local login, run sandbox `auth_all`. This stores credentials
inside the sandbox. It does not disable the host proxy. Individual commands are
`auth_opencode_openai`, `auth_codex_openai`, and `auth_gh`. Add `--force` to repeat
a local login. Rerun the installer to restore deployment defaults for OpenCode and Codex.

## Context7 MCP gateway

Configure Context7 in **host PowerShell**. First, check `sbx mcp ls` and
`sbx mcp inspect context7`. Skip registration if a matching entry exists.
Check `sbx mcp auth status context7`. If authorization is required, run
`sbx mcp auth context7`.

```powershell
# If context7 is not registered, add it and complete browser sign-in:
sbx mcp add context7 --url https://mcp.context7.com/mcp/oauth

# For each sandbox, use the target name from sbx ls:
sbx mcp load context7 --sandbox <sandbox-name>
```

The attachment survives sandbox restarts. After successful setup, do not load it
again. For a new sandbox, use `--static-mcp context7` during creation to preload it.
Registration and OAuth credentials stay on the host. Context7 runs remotely.
This OAuth setup needs no API key, sandbox package, or `credentials.yaml` binding.
Docker Desktop MCP Toolkit registrations are separate from `sbx mcp`.

The installer reports credential problems and recovery steps. It marks cached
successes as previously verified. Its final output shows `sbx daemon restart`
and a Context7 load command with the sandbox hostname. Confirm the target with
host `sbx ls`. Restart when required. Attach Context7 if absent.
The installer cannot verify host attachment, inference, or upstream MCP authorization.
After setup, run sandbox `check_credentials` and `check_mcp`.

Supported SBX agent integrations connect to the sandbox gateway at startup.
The installer sets the same gateway URL in OpenCode and Codex. This includes
Codex installed in an OpenCode sandbox. Host loading does not configure a
manually installed harness. In an existing sandbox, check `codex mcp list` in
**sandbox Bash**. If the Codex entry is absent, run:

```bash
codex mcp add mcp-gateway --url http://mcp-gateway.docker.internal/mcp
```

Restart Codex. Check `/mcp`. Tools appear under the gateway, without a separate
Context7 server entry. OAuth stays on the host. Do not log in to Context7
separately in Codex. Check Context7 tools in both harnesses. Test a documentation
query in each. The gateway can expose tools through `mcp-exec` or `code-mode`
instead of listing each upstream tool.

[Docker gateway guide](https://docs.docker.com/ai/sandboxes/mcp-gateway/),
[Context7 OAuth guide](https://context7.com/docs/howto/oauth)

## Optional Webtop desktop

Permit LinuxServer's image registry in **host PowerShell**. Check for an existing
allow rule first:

```powershell
sbx policy check network lscr.io:443
# If access is denied because no allow rule matches:
sbx policy allow network lscr.io:443
```

Without `--sandbox`, the rule applies to existing and future sandboxes as a global
host default. An explicit deny takes precedence. The redirect target
`ghcr.io:443` and image blob host `pkg-containers.githubusercontent.com:443` also
require access. Check these if the pull fails. A `403 Forbidden` for `lscr.io`
can indicate that the SBX proxy blocked an unlisted registry.
After permitting access, rerun the installer. It cannot edit host policy.
It preserves existing desktops.

After deployment, check the mapping in **host PowerShell**:

```powershell
sbx ls
sbx ports <sandbox-name>
# If the mapping is absent:
sbx ports <sandbox-name> --publish 127.0.0.1:3001:3001
```

Open **https://127.0.0.1:3001/**. Accept the self-signed certificate.
The installer cannot verify host port mappings. If another sandbox uses host port
3001, publish a different port, such as `127.0.0.1:3002:3001`. Use that host port
in the URL. Keep the host binding on loopback. Webtop has no login by default.

The `webtop` container uses `lscr.io/linuxserver/webtop:ubuntu-xfce`, 1 GiB of
shared memory, and the `webtop-config` Docker volume at `/config`. The volume
survives container removal. Deleting the sandbox deletes that storage.
Desktop apps and files are separate from the outer sandbox. No workspace or
Docker socket is mounted. Install desktop applications from a Webtop terminal.
Clipboard access can require permission in the outer browser's site settings.

Run sandbox `desktop` to show its URL, container status, and host reconnection
and port commands. It changes no settings. The suggested name is the sandbox
hostname. Confirm it with host `sbx ls`, or use `desktop <sandbox-name>`.
Disconnection normally preserves the port binding. After reconnection, run
`tmux attach` to resume an existing session. If fully disconnected, run host
`sbx ls`, then `sbx exec -it <sandbox-name> bash`. Run `desktop` in the sandbox.

[Webtop documentation](https://docs.linuxserver.io/images/docker-webtop/)

## Troubleshooting

Confirm the target with **host** `sbx ls`. Use its current name in these commands.

- GitHub: compare **host** `gh api user --jq .login` with **host**
  `sbx exec <sandbox-name> gh api user --jq .login`. Both should return the same account.
- On the documented v0.51.0 Windows setup, GitHub credentials usually required
  **host** `sbx daemon restart` after sandbox creation. The host login worked.
  Reapplying the secret did not correct the sandbox's 401 response. Restarting
  the daemon did. This suggests stale daemon or proxy state.
  Run the restart in host PowerShell. Repeat the sandbox API check.
  Restart can interrupt sessions but preserves sandbox files.
  The installer does not restart the host daemon.
- If the host GitHub check fails, repair its `gh` login. Then update the source:
  `sbx secret set github --command 'gh auth token --hostname github.com' --force`.
- OpenAI: check for `(oauth configured)` in `sbx secret ls`.
  If required, renew with `sbx secret set openai --oauth`.
  Sandbox credential mode does not prove that proxy injection works.
  Missing `api.responses.write` can indicate OpenCode API routing instead of imported OAuth.
  Rerun the current installer before changing account permissions.
- To repeat cached installer checks, run **sandbox Bash**
  `SBX_CHECK_AUTH=1 bash ~/sbx_deploy.sh`. OpenAI checks model-list access only.
  Test a new prompt in each harness to verify inference.
- Run **sandbox** `check_credentials` for live GitHub, OpenCode, and Codex checks
  and credential sources. Host passthrough uses placeholders. Local login uses
  `auth_all` or an individual login command. The check reports mixed setups per
  harness. Source detection cannot prove which token the host proxy sent.
- Run **sandbox** `check_mcp` to list gateway tools and visible OAuth server names.
  Discovery wrappers can hide upstream names and tools. Listing does not verify
  upstream OAuth. Test a tool in each harness. The check executes no tools and
  attaches no servers.
- If failures continue, run **host** `sbx daemon status` to find the log path.
  Temporarily run `sbx daemon log-level set proxy debug`. Reproduce one failure.
  Restore `sbx daemon log-level set proxy info`. Check recent entries for the
  target host. `skipping mitm (no credentials to inject)` indicates missing active
  injection. Remove tokens before sharing logs.
  Avoid `sbx reset`: it deletes sandbox state and stored secrets.

[Docker credential reference](https://docs.docker.com/ai/sandboxes/configuration/credentials/)

## Installer updates and recovery

Deployment locks root-owned `/run/sbx-deploy.lock` before saving `~/sbx_deploy.sh`.
A competing run exits immediately. Retry after the active run finishes.
`flock` (util-linux) must be available. Local Codex login is interactive.
It then takes the same lock before updating configuration.
Do not delete the lock file to bypass an active run.

Generated helpers keep their filenames. Aliases, auth functions, and prompts
are in `/usr/local/lib/sbx-deploy/shell.bash`. Interactive startup sources this
file. User startup files source the separate `path.bash`.
The syslog startup hook remains in `/etc/sandbox-persistent.sh`.

If an earlier run reported permission denied at `gh-clipboard/xclip.tmp.*`,
paste the updated installer again. No directory deletion or recursive ownership
change is required. Staging supports existing root-owned directories.
New user helpers and new user helper directories belong to the invoking user.
Existing file metadata is preserved.

Private baselines are in `${XDG_STATE_HOME:-$HOME/.local/state}/sbx-deploy/managed`.
Each key is the SHA-256 of an absolute managed path without a trailing newline.
An update accepts the recorded baseline or exact desired content.
Without a baseline, it also accepts recognized historical versions.
Markers and filenames alone do not establish ownership.
Each file is published atomically before its baseline. A retry repairs an
interruption between these steps. Identical backups are reused.
Obsolete helpers are kept to protect unrecognized files.

If a helper differs, deployment stops and identifies its path.
Preserve a copy outside the managed path. Then rename the helper so deployment
can recreate it, or review your changes and restore its recorded baseline.
Keep personal changes in a separate file. There is no force-overwrite flag.

Edited, duplicate, or partial startup blocks also stop migration.
Preserve the startup file. Compare it with its previous backup.
Restore a complete supported block, or remove the incomplete managed block before retrying.
Keep unrelated startup settings. Deployment checks shell helpers and startup
migrations together before publishing them. Retry after an interruption during publication.

Configuration editors compare the original input immediately before publication.
They stop if another edit occurred. External editors do not use the deployment
lock. Do not edit these files during deployment. New files cannot overwrite
files created by another process during publication.

Unattended time limits are:

- Installer downloads: 60 seconds.
- CLI installs, upgrades, and plugin clones: 300 seconds.
- Credential commands and credential synchronization lock acquisition: 30 seconds.
- Version checks: 15 seconds.

Processes have five seconds to stop before forced termination.
Existing probes keep stricter limits. APT, Docker image deployment, and
interactive login have no new total time limit. Failures retain their exit
status and private log path. Credential command output stays out of installer logs.

OpenCode maps shared main/subagent defaults to build/plan and general/explore
agents. Codex uses its model and default-subagent settings.
Schemas differ. Deployment model values and the gateway URL stay equivalent.
Host credential substitution and environment overrides are unchanged.

### Sandbox verification checklist

Use disposable sandboxes. Local review checks syntax and publication/migration logic only.

- Fresh install: paste the entire script. Press Enter. Check the banner,
  confirmation, compact stages, APT progress, prompts, tmux bindings, logging,
  and existing auth/check/desktop commands.
- Unchanged rerun: compare managed file timestamps and backup counts.
  Confirm no package installs, network calls, configuration writes, or new backups.
  Repeat with `SBX_VERBOSE=1`, a limited terminal, and no terminal colors.
  Confirm that only five private run logs remain.
- Supported upgrades: test previous generated helpers and each supported legacy
  shell/auth form, including the original desktop helper. Confirm that loaders
  replace complete recognized blocks. Check that unrelated text remains unchanged.
- Edited helpers: change one helper. Rerun deployment. Confirm that it identifies
  the file and preserves its contents. Confirm that the shell group is not published.
  Use the recovery procedure above.
- Partial startup blocks: test a truncated block, an edited block, and a duplicate
  block. Confirm that each case stops without rewriting the startup file.
- Interrupted publication: interrupt after helper publication, before baseline
  recording. Also interrupt between startup-file publications. Retry each case.
  Check completion, ownership records, preserved user files, and backup reuse.
- Concurrency: hold one deployment open. Start another. Confirm that the second
  exits before saving or changing deployment files. Edit a staged configuration
  externally. Confirm that publication stops. Check that local Codex login waits
  for the same lock only after interactive authentication.
- Timeouts: stall downloads, clones, upgrades, credential commands, version checks,
  and credential lock acquisition. Check time limits, exit codes, cleanup, and logs
  without secrets.
- Harness defaults: confirm shared Sol/Luna models, host OAuth placeholders, and
  the MCP gateway in OpenCode and Codex. Test inference and Context7 tools in both.
