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

Optional sandbox login: run `auth_all`, or use `auth_opencode_openai`,
`auth_codex_openai`, or `auth_gh`. Add `--force` to repeat a login.
Local credentials stay in the sandbox; host proxy substitution remains active.
Rerun the installer to restore deployment defaults for OpenCode and Codex.

## Context7 MCP gateway

In **host PowerShell**, check `sbx mcp ls` and `sbx mcp inspect context7`.
Skip registration if a matching entry exists.

```powershell
# Register only if absent, then complete browser sign-in:
sbx mcp add context7 --url https://mcp.context7.com/mcp/oauth

# Check authorization; run sbx mcp auth context7 if required:
sbx mcp auth status context7

# Attach to each sandbox; use its name from sbx ls:
sbx mcp load context7 --sandbox <sandbox-name>
```

Attachments survive restarts. Load only if absent, or use `--static-mcp context7`
during sandbox creation. Registration and OAuth stay on the host. No API key or
`credentials.yaml` binding is required. Docker Desktop MCP Toolkit registrations
are separate from `sbx mcp`.

The installer configures the gateway in OpenCode and Codex. Restart the harnesses
after setup. Context7 tools appear under the gateway, sometimes through
`mcp-exec` or `code-mode`. Do not log in to Context7 separately in Codex.

[Docker gateway guide](https://docs.docker.com/ai/sandboxes/mcp-gateway/),
[Context7 OAuth guide](https://context7.com/docs/howto/oauth)

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
After permitting access, rerun the installer and choose Webtop.

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

Run sandbox `desktop` for status and reconnection commands. Confirm its suggested
sandbox name with host `sbx ls`, or run `desktop <sandbox-name>`.
Desktop storage survives container removal. Deleting the sandbox deletes it.

[Webtop documentation](https://docs.linuxserver.io/images/docker-webtop/)

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
  Missing `api.responses.write` can indicate incorrect OpenCode routing.
  Rerun the current installer before changing account permissions.
- In **sandbox Bash**, run `check_credentials` for live access and credential
  sources. It cannot prove which token the host proxy sent.
  Repeat cached installer checks with `SBX_CHECK_AUTH=1 bash ~/sbx_deploy.sh`.
  OpenAI checks cover model-list access only. Test a prompt in each harness.
- Run sandbox `check_mcp` for gateway discovery. It does not verify upstream
  OAuth or host attachment. Test a Context7 tool in each harness.
- For persistent failures, run host `sbx daemon status` to find the log path.
  Set `sbx daemon log-level set proxy debug`, reproduce one failure, then restore
  `sbx daemon log-level set proxy info`. Check entries for the target host.
  `skipping mitm (no credentials to inject)` indicates missing active injection.
  Remove tokens before sharing logs.

Avoid `sbx reset`: it deletes sandbox state and stored secrets.

[Docker credential reference](https://docs.docker.com/ai/sandboxes/configuration/credentials/)

## Installer recovery

Run the installer in sandbox Bash. After an interruption, rerun it.
If another deployment is active, wait for it to finish. Do not delete its lock
file or edit configuration during deployment. Failures show the private log path.

If deployment identifies an edited helper, preserve a copy, then rename the
helper so deployment can recreate it. Keep personal changes in a separate file.
Helpers have no force-overwrite flag.

For an unrecognized or edited `/etc/tmux.conf`, deployment stops and preserves
the file. To back it up and restore the supplied configuration, run
`bash ~/sbx_deploy.sh --tmux-redeploy` in sandbox Bash. Keep personal settings in
`~/.tmux.conf`. The flag still rejects symlinks and concurrent edits.

For edited, duplicate, or partial startup blocks, preserve the startup file and
compare it with its backup. Restore a complete supported block, or remove only
the conflicting managed block before retrying. Keep unrelated settings.

