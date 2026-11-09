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

