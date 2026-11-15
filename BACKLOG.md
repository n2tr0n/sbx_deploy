# Open work

Check reports against current code before changing behavior. Keep credentials
out of logs and shared output.

- **Cloud validation:** Confirm full deployment after the VS Code download
  policy fix. Check the new DNS recovery summary: cloud target selection,
  scoped commands, copyable lines, exit status, log path, verbose output, and
  terminal fallbacks. Cloud authentication, inference, MCP, tunnel connections,
  and restart persistence still need cloud checks. See
  [HOST_SETUP_CLOUD.md](HOST_SETUP_CLOUD.md).

- **First-paste shell activation:** Check that PATH, aliases, and the prompt
  activate immediately after a fresh cloud paste with the direct-helper fix.
  Reconnect already works. Check local activation, user overrides, and a new
  tmux pane. A child-script run must print the parent-terminal refresh command.

- **Remaining deployment checks:** Complete the remaining
  [sandbox checks](AGENTS.md#validation): Toronto timezone on fresh setup;
  preservation of an existing timezone, user edits, and logins; user-local
  OpenCode upgrades while image installations remain unchanged; safe recovery
  after interruption; and an unchanged rerun with no installs, network calls,
  configuration writes, or new backups. Use
  [SANDBOX_VALIDATION.md](SANDBOX_VALIDATION.md) for evidence collection.

- **VS Code startup kit:** Resolve attachment `409 Conflict` about an effective
  OAuth credential policy change. The kit declares no credentials; the cause
  remains unverified. Keep the sandbox and OAuth bindings. Use `vscode_tunnel`
  after each restart until fixed. Record host version, sandbox inspection, and
  kit inspection; compare effective kit composition and OAuth policy.
  Validate the published v3 kit from outside the repository: publisher
  allowlist, remote inspection, attachment, default `agent` and custom user
  names, automatic startup, restart, saved login, status, and disable controls.
  Offline validation needs a kit builder. See
  [tunnel setup](HOST_SETUP_WIN.md#optional-vs-code-tunnel) and
  [recovery](HOST_SETUP_WIN.md#tunnel-troubleshooting).

- **Codex broken pipe (unreproduced):** Investigate if selection or copying triggers it.
  Record steps, versions, and relevant output.

# Feature roadmap

- Add a module system.
- Add RTK and Superpowers support.
- Add a Git user name and email wizard.
- Better / seperate cloud support.
