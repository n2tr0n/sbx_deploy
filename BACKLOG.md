# Reported issues

Check each report against current code before making changes. AI reports below
are unverified. Record reproduction evidence. Update or close each entry after investigation.

- [AI-reported; unverified] Auth cache: `check_credential` may show an old success after a failed recheck. Check cache removal after fresh probes. Confirm that only successful results enter the cache.
- [AI-reported; unverified] Repeated OpenAI login: helpers may trust `SBX_CRED_OPENAI_MODE` instead of saved credentials. Check local-login and host-placeholder detection. Preserve explicit `--force` behavior.
- [Code-reviewed; sandbox reproduction pending] Local OpenAI login selection: with host OAuth configured, installer reruns can reselect the managed OpenCode credential and Codex `sbx-chatgpt` provider after an explicit local login. The OpenCode import calls `auth switch` for an inactive matching managed record; the Codex configuration stage resets `model_provider`. Saved local tokens remain. Confirm in both harnesses. Preserve explicit local login selection on reruns.
- [AI-reported; unverified] Shell startup hangs: check whether `flock 9` in `sbx-local-syslog` can wait indefinitely. Consider a time limit with a warning that lets shells continue. Include noninteractive agent shells.
- [AI-reported; unverified] Webtop prompt: the wrapper may close FD 6. Check terminal input on FD 0 and the `/dev/tty` fallback. Confirm that prompts cannot read pasted script text.
- [AI-reported; unverified] Missing GitHub CLI: check installer auth checks, `check_credentials`, and `auth_gh`. Confirm that they identify missing `gh` before suggesting network or login repairs.
- [AI-reported; unverified] OpenCode V2 MCP layout: the installer writes `mcp.mcp-gateway` with `enabled`, while V2 documents `mcp.servers.mcp-gateway` with `disabled`. The reviewed schema still accepts the legacy layout; no connection failure is confirmed. Check the installed version and legacy support. Test gateway discovery and a Context7 tool before changing the layout. Preserve user MCP settings during migration.
- [Unreproduced] Codex "broken pipe" during selection or copying: investigate if it recurs. Record reproduction steps, versions, and relevant output.

# Future roadmap features

- vscode headless + tunnel enabled
