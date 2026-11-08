# SBX Deploy

SBX Deploy is a Bash installer for Debian/Ubuntu environments inside local
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`).[^docker]

`sbx_deploy.sh` installs sandbox tools, tmux, TPM, tmux-resurrect, UTF-8 wrappers,
and Bash aliases. It configures OpenCode and Codex for host credentials and the MCP gateway.

To use other harnesses or providers, fork this project. Ask your coding agent to
update the installer and authentication instructions for your requirements.

This project has been tested on Windows hosts only at this time.

## Run

- Complete the Windows host setup in [HOST_SETUP_WIN.md](HOST_SETUP_WIN.md).
- Inside the sandbox, use the default user with passwordless sudo.
- Paste the **entire script** into sandbox Bash.
- Press Enter and follow the prompts.
- Read the final output for host setup and verification steps.

Provided as-is, without warranty. Review the script before use.
See [SECURITY.md](SECURITY.md) to report security issues.
Third-party software and services remain subject to their respective licenses and terms.

[^docker]: The author is not affiliated with Docker, Inc. This independent project
    is not sponsored, endorsed, or supported by Docker, Inc. Docker is a trademark
    or registered trademark of Docker, Inc. in the United States and/or other countries.
