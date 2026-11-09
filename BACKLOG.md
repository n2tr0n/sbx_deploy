# Open work

Check each report against current code before changing behavior. Keep real
credentials out of logs and shared output.

- [Unreproduced] Codex "broken pipe" during selection or copying. Investigate if
  it recurs. Record the steps, versions, and relevant output.

- [Sandbox validation pending] Model and MCP override preservation. Fixture checks
  pass. Check the full installer with fresh setup, custom
  overrides, and interrupted runs in both harnesses.
  OpenCode previously lost `mcp.mcp-gateway.headers.Authorization` in `newtest1`.
  The saved value contains placeholder text. The user does not know its source
  or why it was removed. Do not restore it until ownership is clear.
  The current code preserves MCP headers. Keep both backups:
  `~/.config/opencode/opencode.json.bak.iyIORl` and
  `~/.codex/config.toml.bak.7AVe1J`. If the header is confirmed as a user setting,
  copy only that setting from the OpenCode backup. Preserve the current config.
