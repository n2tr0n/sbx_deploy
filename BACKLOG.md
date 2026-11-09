# Open work

Check each report against current code before changing behavior. Keep real
credentials out of logs and shared output.

- [Unreproduced] Codex "broken pipe" during selection or copying. Investigate if
  it recurs. Record the steps, versions, and relevant output.

- [Cause unknown] OpenAI device login returns HTTP 401 in both harnesses.
  OpenCode v2.2.6 reports `Request failed: 401`. Codex CLI 0.167.0 reports
  `401 Unauthorized: Invalid client specified`. Host SBX is v0.51.0.
  On `newtest1`, Codex also fails without the deployment login helper and after
  a host daemon restart. Direct-login request ID:
  `7b20b7fd-564d-4b3e-89d7-e3e7307b245d`.
  Model-access checks pass. Proxy debug output shows HTTPS interception and
  `custom_secret_replacement_skipped` with `no_target_match`. This does not
  establish the cause. Investigate the clients and host proxy before changing
  behavior. Exit 137 was also reported before reconnection; its cause is unknown.

- [Sandbox validation pending] Local authentication preservation. Fixture checks
  pass. Check fresh authentication selection and a successful local login followed
  by rerun in both harnesses. The device-login failure above blocks the local-login
  check.

- [Sandbox validation pending] Model and MCP override preservation. Fixture checks
  pass in `newtest1` (17 tests). Check the full installer with fresh setup, custom
  overrides, and interrupted runs in both harnesses.
  The migration backup review found no replaced model settings. Codex provider
  settings are unchanged. OpenCode lost `mcp.mcp-gateway.headers.Authorization`.
  The saved value contains placeholder text. The user does not know its source
  or why it was removed. Do not restore it until ownership is clear.
  The current code preserves MCP headers;
  a new fixture check passes. Keep both backups:
  `~/.config/opencode/opencode.json.bak.iyIORl` and
  `~/.codex/config.toml.bak.7AVe1J`. If the header is confirmed as a user setting,
  copy only that setting from the OpenCode backup. Preserve the current config.
