# Open work

Check reports against current code before changing behavior. Keep credentials
out of logs and shared output.

# Feature roadmap

- Validate the environment confirmation after the logo. Check Enter for local,
  cloud, saved, and `SBX_ENV` defaults. Check manual changes, cancellation,
  narrow terminals, and unchanged reruns. Every run must ask.
- Validate cloud MCP discovery from existing OpenCode or Codex configuration.
  The reported sandbox supplied no gateway URL variable. Check pending MCP
  setup without an attached endpoint, attachment, and a later rerun. Confirm
  gateway authentication in both harnesses without copying real credentials.
- Validate the single-file local/cloud profiles in disposable sandboxes. Check
  fresh install, unchanged rerun, upgrades, preservation, interruption, and both
  harnesses. See HOST_SETUP_CLOUD.md. Keep deployment free of build steps.
- Confirm the cloud MCP endpoint and OAuth placeholder contract from a real
  cloud `opencode` sandbox. Validate automatic selection in both environments
  using the supplied report patterns. Check overrides and ambiguous markers.
- Validate the VS Code tunnel and startup kit in cloud mode. Keep Webtop
  disabled until an authenticated cloud access path is supported.
- Add RTK and Superpowers support.
- Add a Git user name and email wizard.
