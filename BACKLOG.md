# Open work

Check reports against current code before changing behavior. Keep credentials
out of logs and shared output.

- **Cloud validation:** Confirm full deployment after the VS Code download
  policy fix. Check the new DNS recovery summary: cloud target selection,
  scoped commands, copyable lines, exit status, log path, verbose output, and
  terminal fallbacks. Cloud authentication, inference, MCP, tunnel connections,
  and restart persistence still need cloud checks. See
  [HOST_SETUP_CLOUD.md](HOST_SETUP_CLOUD.md).

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
- Better / seperate cloud support - MCP gateway and credentials
