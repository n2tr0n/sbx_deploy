# SBX Deploy

- Maintain `sbx_deploy.sh` as a Bash installer for the Debian/Ubuntu sandbox.
- Read [HOST_SETUP_WIN.md](HOST_SETUP_WIN.md) for Windows host credentials, bindings, and proxy troubleshooting; keep it current when those requirements change.
- The installer runs inside the sandbox. Document required Windows host actions in `HOST_SETUP_WIN.md`; do not attempt them from the installer.
- Keep deployment-managed defaults equivalent across all harnesses (models, subagents, MCP servers, and shared tools); use shared values, document unsupported differences, and preserve deliberate local overrides.
- Update only recognized deployment-managed content. Preserve unrelated settings and user edits; stop with recovery instructions when ownership is uncertain.
- Never log real credentials, replace host placeholders with tokens, or overwrite existing local logins implicitly.
- Describe script behavior briefly in operational terms in its header; keep it current. Do not add to or expand `README.md` unless explicitly asked; keep it mercifully short.
- Make idempotence a requirement for every change. After a successful run, an unchanged rerun must skip package installs, network calls, managed-config rewrites, and new backups unless an explicit refresh or recheck is requested. Make interrupted runs safe to retry and preserve existing user data.
- Keep the SBX Deploy banner and supplied tmux config intact unless asked to change them.
- Preserve the compact stage checklist, live APT progress, terminal fallbacks, and `SBX_VERBOSE=1` live output with five-run log retention. Route new work through the existing reporting helpers.
- Keep Bash strict-mode failures effective: stop on errors, preserve exit codes, show a short reason/excerpt and log path, and clean up safely on failure or interruption.
- Review changes statically, including generated scripts and embedded payloads. Use syntax checks where available; never execute the installer locally. Report which checks ran and which sandbox checks remain. The user runs the installer and tests it in their sandbox.
- Preserve execution by pasting the entire file into interactive Bash and pressing Enter. Preserve the complete-file paste wrapper and literal payload boundaries; prompts must not consume pending pasted script text.
- Assume passwordless sudo is available; use noninteractive elevation so missing privileges fail promptly.
- Track reported issues in [BACKLOG.md](BACKLOG.md). Revalidate them against current code before changing behavior; reported diagnoses are not established facts.

# Roadmap features

- less failure prone, atomic hardening etc.
- release/public

