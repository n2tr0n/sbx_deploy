# Reported issues

Check each report against current code before making changes. AI reports below
are unverified. Record reproduction evidence. Update or close each entry after investigation.

- [AI-reported; unverified] OpenCode V2 MCP layout: the installer writes `mcp.mcp-gateway` with `enabled`, while V2 documents `mcp.servers.mcp-gateway` with `disabled`. The reviewed schema still accepts the legacy layout; no connection failure is confirmed. Check the installed version and legacy support. Test gateway discovery and a Context7 tool before changing the layout. Preserve user MCP settings during migration.
- [Unreproduced] Codex "broken pipe" during selection or copying: investigate if it recurs. Record reproduction steps, versions, and relevant output.

# Future roadmap features

- vscode headless + tunnel enabled
