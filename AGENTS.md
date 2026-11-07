# SBX Deploy

- Maintain `sbx_deploy.sh` as a Bash installer for the Debian/Ubuntu sandbox.
- Describe script behavior briefly in operational terms in its header; keep it current. Do not add to or expand `README.md` unless explicitly asked; keep it mercifully short.
- Make idempotence a requirement for every change. After a successful run, an identical rerun should skip package installs, network calls, config rewrites, and new backups. Make interrupted runs safe to retry and preserve existing user data.
- Keep the SBX Deploy banner and supplied tmux config intact unless asked to change them.
- Preserve the compact stage checklist, live APT progress, terminal fallbacks, and `SBX_VERBOSE=1` live output with five-run log retention. Route new work through the existing reporting helpers.
- Keep Bash strict-mode failures effective: stop on errors, preserve exit codes, show a short reason/excerpt and log path, and clean up safely on failure or interruption.
- Review changes statically. The user runs the installer and tests it in their sandbox.
- Ensure the ability to paste > press enter as the execution method for the script is always preserved
- The sandbox has no sudo password, your installer can assume none is there

# Roadmap features

- desktop
- tmux default tabs populated
- second harness