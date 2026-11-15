# Open work

Check reports against current code before changing behavior. Keep credentials
out of logs and shared output.

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

# Feature roadmap

- Add a module system.
- Add RTK and Superpowers support.
- Add a Git user name and email wizard.
- Create a separate cloud installer with MCP gateway and credential support.
