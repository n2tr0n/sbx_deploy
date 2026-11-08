# Reported issues

Revalidate each report against current code before making changes. The AI-reported
items below are unverified diagnoses, not confirmed bugs or instructions to apply
the suggested fix. Record reproduction evidence and update or close entries as
they are investigated.

- [AI-reported; unverified] Auth cache: `check_credential` may report old success after a failed recheck. Check whether fresh probes clear the cache and only successful results are cached.
- [AI-reported; unverified] Repeated OpenAI login: auth helpers may trust `SBX_CRED_OPENAI_MODE` over saved credentials. Check local-login versus host-placeholder detection and preserve explicit `--force` behavior.
- [AI-reported; unverified] Shell startup hangs: investigate whether startup `flock 9` in `sbx-local-syslog` can wait indefinitely. Consider a bounded wait that warns and lets shells continue, including noninteractive agent shells.
- [AI-reported; unverified] Webtop prompt: FD 6 may be closed by the wrapper. Check terminal stdin (FD 0) handling, `/dev/tty` fallback, and protection against consuming pasted script text.
- [AI-reported; unverified] Missing GitHub CLI: check whether installer auth checks, `check_credentials`, and `auth_gh` identify missing `gh` instead of suggesting network or login repairs.
- [Unreproduced] Codex “broken pipe” on select/copy: investigate if encountered again; capture reproduction steps and relevant version/output details.

# Documented host requirements

These former backlog notes are documented in [HOST_SETUP_WIN.md](HOST_SETUP_WIN.md).
Keep setup and troubleshooting details there rather than duplicating them here.

- GitHub credential passthrough may require a host `sbx daemon restart` after creating a sandbox on the documented Windows setup.
- MCP gateway attachment requires host setup for each new sandbox; the installer cannot perform that attachment.
