# SBX Deploy

- Maintain `sbx_deploy.sh` as a Bash installer for the Debian/Ubuntu sandbox.
- Make idempotence a requirement for every change. After a successful run, an identical rerun should skip package installs, network calls, config rewrites, and new backups. Make interrupted runs safe to retry and preserve existing user data.
- Keep the SBX Deploy banner and supplied tmux config intact unless asked to change them. Install tmux-resurrect automatically through TPM. After setup, tell the user how to start tmux or reload its config.
- Review changes statically. The user runs the installer and tests it in their sandbox.
- **Preview** means one copyable code block. **File link** means a clickable link to the latest saved script. Show either only when explicitly requested.
- For a paste-to-file preview, start with the `cat` command and preserve the final newline. Put the finish instruction at the end of the preview, outside the script: press Ctrl+D on a blank line for plain `cat`, or press Enter after the closing marker for a heredoc.
