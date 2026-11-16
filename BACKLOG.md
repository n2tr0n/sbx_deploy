# Open work

Check reports against current code before changing behavior. Keep credentials
out of logs and shared output.

- Validate public plugin downloads after the GitHub key correction. Confirm
  successful download, cleanup after interruption, and an unchanged rerun.
  The installer now stops on clone failure instead of requesting a login.

- Improve the PowerShell host setup TUI. Check layout, stage rows, narrow
  windows, `NO_COLOR`, and line-input fallback. Validate numbered choices,
  Enter defaults, y/n confirmation, and Esc cancellation in Windows Terminal.

- Finish live masked-input checks in `sbx_cloud_host_setup_win.ps1`. Check
  GitHub, OpenAI, and Context7 keys, visible masking, save status, empty input,
  cancellation, and failed saves. Confirm cloud standard-input delivery.
  Keep values out of arguments, receipts, logs, and output.

- Validate the wizard's stale-receipt recovery path. Recreate a missing
  sandbox with its existing scoped secret. Check old-receipt migration,
  declined recreation, account review, unrelated inspection errors, and an
  unchanged rerun. Manual secret retention and reuse do not need another test.

- Complete deployment validation in disposable local and cloud sandboxes.
  For cloud, run `sbx_cloud_host_setup_win.ps1` with correct credentials
  prepared before creation, then paste the Bash installer. Confirm one clean
  install without manual repair, the Bash handoff, models, inference, and
  direct Context7 in both harnesses after automated configuration. Check
  unchanged reruns for no installs, network calls, writes, or new backups.
  Check upgrades, user-setting preservation, interruption, and receipt recovery.
  The latest cloud run needed a key correction; its recovery is not yet
  confirmed complete. It does not count as a clean successful deployment.

- Investigate the report that cloud post-deployment shell and alias settings
  need a manual session restart. Check activation in the current shell,
  reconnect, and new tmux panes. Preserve user shell settings.

- BLOCKED: Repair Docker-managed cloud MCP gateway creation. On SBX v0.53.0,
  manual OpenCode and shell creation with `--static-mcp context7` fails with
  `secret not found ... name=docker`. Console creation fails separately with
  Context7 and public no-auth DeepWiki. Cloud diagnostics pass. Local gateway
  registration did not repair it. The cause and supported repair remain
  unconfirmed. This does not block the working direct Context7 method.

# Feature roadmap

- Add the same guided PowerShell setup for local sandboxes in
  `HOST_SETUP_WIN.md` after the cloud setup is complete.
- Validate environment confirmation after the logo. Check Enter for local,
  cloud, saved, and `SBX_ENV` defaults. Check manual changes, cancellation,
  narrow terminals, and unchanged reruns. Every run must ask.
- After Docker gateway repair, validate cloud gateway discovery from existing
  OpenCode or Codex config without a URL variable. Check attachment, discovery
  on rerun, and authentication in both harnesses without copying credentials.
- Validate the remaining cloud OAuth placeholder contract and environment
  detection cases. Check ambiguous markers, overrides, and both harnesses.
- Validate the VS Code tunnel and startup kit in cloud mode. Keep Webtop
  disabled until an authenticated cloud access path is supported.
- Add RTK and Superpowers support.
- Add a Git user name and email wizard.
- Clean up powershell script TUI; it's really sloppy
- Cloud post-deployment doesn't load new shell/alias ENV - requires manual session restart
- Give local sbx the same full pipeline treatment as cloud
- rename main play to not say local, since its local and cloud now