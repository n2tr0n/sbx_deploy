# Open work

Check each report against current code before changing behavior. Keep real
credentials out of logs and shared output.

- [Unreproduced] Codex "broken pipe" during selection or copying. Investigate if
  it recurs. Record the steps, versions, and relevant output.

- [Sandbox check] Verify release cleanup in disposable sandboxes. Check a fresh
  full-file paste and an unchanged rerun. Check helper upgrades, preserved user
  edits, and interruption recovery. Test the login helpers and MCP checks in
  both harnesses. Check the desktop helper's terminal output. New tmux snapshots
  must use session name `sbx` and the caller's home directory. Keep user saves.

- [Sandbox check] Verify the Webtop registry 403 hint. Confirm that the failure
  output shows the Windows policy commands and keeps Docker exit code 125.
  The reported download was blocked by the host network policy.

# Feature roadmap

- enable a module system
- add RTK and Superpowers support
