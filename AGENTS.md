# SBX Deploy

- Maintain `sbx_deploy.sh` as a Bash installer for the Debian/Ubuntu sandbox.
- Read [HOST_SETUP_WIN.md](HOST_SETUP_WIN.md) for Windows host credentials, bindings, and proxy troubleshooting; keep it current when those requirements change.
- Keep deployment-managed settings equivalent across all harnesses (models, subagents, MCP servers, and shared tools); use shared values and document unsupported differences.
- Describe script behavior briefly in operational terms in its header; keep it current. Do not add to or expand `README.md` unless explicitly asked; keep it mercifully short.
- Make idempotence a requirement for every change. After a successful run, an identical rerun should skip package installs, network calls, config rewrites, and new backups. Make interrupted runs safe to retry and preserve existing user data.
- Keep the SBX Deploy banner and supplied tmux config intact unless asked to change them.
- Preserve the compact stage checklist, live APT progress, terminal fallbacks, and `SBX_VERBOSE=1` live output with five-run log retention. Route new work through the existing reporting helpers.
- Keep Bash strict-mode failures effective: stop on errors, preserve exit codes, show a short reason/excerpt and log path, and clean up safely on failure or interruption.
- Review changes statically. The user runs the installer and tests it in their sandbox.
- Ensure the ability to paste > press enter as the execution method for the script is always preserved
- The sandbox has no sudo password, your installer can assume none is there

# Roadmap features

- doc deslop
- less failure prone, atomic hardening etc.
- release/public

# Known issues

- [AI-reported] Auth cache: `check_credential` can report old success after a failed recheck; clear the cache before fresh probes, and cache only success.
- [AI-reported] Repeated OpenAI login: auth helpers trust `SBX_CRED_OPENAI_MODE` over saved credentials; detect local logins versus host placeholders and preserve `--force`.
- [AI-reported] Shell startup hangs: bound the startup `flock 9` wait in `sbx-local-syslog`; warn and let shells continue, including noninteractive agent shells.
- [AI-reported] Webtop prompt: FD 6 is closed by the wrapper; use terminal stdin (FD 0), keeping `/dev/tty` fallback and pasted-input protection.
- [AI-reported] Missing GitHub CLI: installer auth checks, `check_credentials`, and `auth_gh` should identify missing `gh` instead of suggesting network or login repairs.
- gh daemon restart; bug - sbx daemon must restart to enable gh cred passthrough on new win sandbox
- MCP brokering; bug - must be configured outside the sandbox for every new sandbox
- codex 'broken pipe' on select/copy - can't reproduce; investigate if we encounter it again
