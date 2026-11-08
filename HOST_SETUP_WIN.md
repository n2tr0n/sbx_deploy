# Windows host setup and troubleshooting

For local Docker Sandboxes (`sbx`), run host commands in **Windows PowerShell**.
Real credentials stay in the host keychain. Sandbox files contain placeholders.
The installer cannot configure or restart the host. Keep host settings outside
sandbox-mounted workspaces. Never put real tokens in logs or chat.

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

### Context7 registration

In **host PowerShell**, check `sbx mcp ls` and `sbx mcp inspect context7`.
Skip registration if a matching entry exists.

```powershell
# Register only if absent, then complete browser sign-in:
sbx mcp add context7 --url https://mcp.context7.com/mcp/oauth

# Check authorization; run sbx mcp auth context7 if required:
sbx mcp auth status context7
```

Registration and OAuth stay on the host. No API key or
`credentials.yaml` binding is required. Docker Desktop MCP Toolkit registrations
are separate from `sbx mcp`.

[Docker gateway guide](https://docs.docker.com/ai/sandboxes/mcp-gateway/),
[Context7 OAuth guide](https://context7.com/docs/howto/oauth)

## Per-sandbox MCP attachment

For each running sandbox, attach Context7 if absent. Use its name from `sbx ls`:

```powershell
sbx mcp load context7 --sandbox <sandbox-name>
```

Attachments survive restarts. Alternatively, use `--static-mcp context7`
during sandbox creation.

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
  Set `sbx daemon log-level set proxy debug`, reproduce one failure, then restore
  `sbx daemon log-level set proxy info`. Check entries for the target host.
  `skipping mitm (no credentials to inject)` indicates missing active injection.
  Remove tokens before sharing logs.

Avoid `sbx reset`: it deletes sandbox state and stored secrets.

[Docker credential reference](https://docs.docker.com/ai/sandboxes/configuration/credentials/)

