# SBX Deploy

- Maintain `sbx_deploy.sh` as a Bash installer for the Debian/Ubuntu sandbox.
- Make idempotence a requirement for every change. After a successful run, an identical rerun should skip package installs, network calls, config rewrites, and new backups. Make interrupted runs safe to retry and preserve existing user data.
- Keep the SBX Deploy banner and supplied tmux config intact unless asked to change them.
- Review changes statically. The user runs the installer and tests it in their sandbox.
- Ensure the ability to paste > press enter as the execution method for the script is always preserved
- The sandbox has no sudo password, your installer can assume none is there