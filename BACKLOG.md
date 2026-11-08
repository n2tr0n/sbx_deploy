# Reported issues

Check each report against current code before making changes. AI reports below
are unverified. Record reproduction evidence. Update or close each entry after investigation.

- [AI-reported; unverified] Auth cache: `check_credential` may show an old success after a failed recheck. Check cache removal after fresh probes. Confirm that only successful results enter the cache.
- [AI-reported; unverified] Repeated OpenAI login: helpers may trust `SBX_CRED_OPENAI_MODE` instead of saved credentials. Check local-login and host-placeholder detection. Preserve explicit `--force` behavior.
- [AI-reported; unverified] Shell startup hangs: check whether `flock 9` in `sbx-local-syslog` can wait indefinitely. Consider a time limit with a warning that lets shells continue. Include noninteractive agent shells.
- [AI-reported; unverified] Webtop prompt: the wrapper may close FD 6. Check terminal input on FD 0 and the `/dev/tty` fallback. Confirm that prompts cannot read pasted script text.
- [AI-reported; unverified] Missing GitHub CLI: check installer auth checks, `check_credentials`, and `auth_gh`. Confirm that they identify missing `gh` before suggesting network or login repairs.
- [Unreproduced] Codex "broken pipe" during selection or copying: investigate if it recurs. Record reproduction steps, versions, and relevant output.

# Documented host requirements

Keep setup and troubleshooting details in [HOST_SETUP_WIN.md](HOST_SETUP_WIN.md).

- On the documented Windows setup, GitHub credentials may require a host `sbx daemon restart` after sandbox creation.
- Each new sandbox requires host setup to attach the MCP gateway. The installer cannot attach it.

# Working backlog

- v2 mcp layout
- tmux overwrite