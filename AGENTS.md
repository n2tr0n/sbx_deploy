# SBX Deploy

- Maintain `sbx_local_opencode_deploy.sh` as a Bash installer for local SBX sandboxes of type `opencode`.
- Read [HOST_SETUP_WIN.md](HOST_SETUP_WIN.md) for Windows credentials, bindings, and proxy troubleshooting. Update it when host requirements change.
- Run the installer inside the sandbox. Document Windows host actions in `HOST_SETUP_WIN.md`. Do not perform them from the installer.
- Keep deployment defaults equivalent across harnesses: models, subagents, MCP servers, and shared tools. Use shared values. Document unsupported differences. Preserve deliberate local overrides.
- Update only content that deployment owns. Preserve unrelated settings and user edits. If ownership is uncertain, stop and give recovery instructions.
- Never log real credentials. Never replace host placeholders with tokens. Never overwrite local logins without an explicit request.
- Describe installer operations briefly in its header. Keep it current. Do not add to or expand `README.md` unless asked. Keep it short.
- Make each change idempotent. After success, an unchanged rerun must skip package installs, network calls, configuration writes, and new backups. An explicit refresh or recheck can repeat them. Make interrupted runs safe to retry. Preserve user data.
- Preserve the SBX Deploy banner and supplied tmux configuration unless asked to change them.
- Preserve the compact stage checklist, live APT progress, terminal fallbacks, and `SBX_VERBOSE=1` live output. Keep five run logs. Use the existing reporting helpers for new operations.
- Preserve Bash strict-mode error handling. Stop on errors. Preserve exit codes. Show a short reason or excerpt and the log path. Clean up safely after failure or interruption.
- Review changes without running the installer, including generated scripts and embedded payloads. Run available syntax checks. Report completed checks and remaining sandbox checks. The user tests the installer in their sandbox.
- Preserve complete-file paste execution in interactive Bash. Keep the outer wrapper and literal payload boundaries. Prompts must not read pending script text as input.
- Assume passwordless sudo is available. Use noninteractive elevation so missing privileges cause an immediate failure.
- Track reported issues in [BACKLOG.md](BACKLOG.md). Check each report against current code before changing behavior. Treat reported diagnoses as unverified.
- Use ASD-STE100 principles where possible in documentation and comments. Use short sentences, direct instructions, and consistent terms. Preserve technical meaning. Prefer shorter text.

## Validation

The user runs these checks in disposable sandboxes after local review:

- Fresh install: paste the entire installer. Check installation, terminal output, shell setup, tmux, logging, and helpers.
- Unchanged rerun: confirm no package installs, network calls, configuration writes, or new backups.
- Upgrade and preservation: check supported upgrades. Confirm user edits and unrelated settings are preserved.
- Interrupted run: interrupt deployment, then rerun. Confirm safe completion and preserved user data.
- Harness checks: confirm shared models, authentication, inference, and MCP tools in OpenCode and Codex.
