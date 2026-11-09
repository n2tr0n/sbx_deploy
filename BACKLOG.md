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
  pass. Check fresh setup, custom overrides, and interrupted runs in both harnesses.
  Review the OpenCode and Codex config backups from the `newtest1` migration.
  Restore any custom or unrelated settings. Keep the backups until review is done.
