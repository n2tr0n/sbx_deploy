# SBX Deploy

One installer for OpenCode and Codex in local
[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/).

An opinionated, pre-customized coding sandbox your AI agent can set up, make yours, and maintain—with Docker
support, host-managed credentials, and layered network security.

- Use either OpenCode or Codex to fix and deploy the other's setup.
- Switch between them with shared models, tools, and authentication defaults.
- Save and restore terminal sessions with tmux.
- Work in the terminal, VS Code, or an optional desktop.
- Track deployment progress. Use run logs to diagnose failures.
- Skip completed setup on reruns. Keep your edits and saved logins.

**Experimental public alpha. Tested on Windows hosts only.**
Check [known issues](BACKLOG.md) before deployment.

## Get started

1. Complete the [Windows host setup](HOST_SETUP_WIN.md). Use an `opencode` sandbox.
2. Review [the installer](sbx_local_opencode_deploy.sh). To customize, fork the
   project on your host and ask your AI agent to adapt it. Review its changes.
3. Paste the **entire installer file contents** into sandbox's bash prompt as the default user with the default passwordless sudo. Follow the prompts.

Licensed under [MIT-0](LICENSE).
See [SECURITY.md](SECURITY.md) to report security issues.
Third-party software and services remain subject to their respective licenses and terms.

The author is not affiliated with Docker, Inc. This independent project
is not sponsored, endorsed, or supported by Docker, Inc. Docker is a trademark
or registered trademark of Docker, Inc. in the United States and/or other countries.
