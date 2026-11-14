# Open work

Check each report against current code before changing behavior. Keep real
credentials out of logs and shared output.

- [Confirmed compatibility gap] SBX v0.53.0 OpenCode sandbox uses Debian 13
  and OpenCode v2.3.0 at `/usr/local/bin/opencode`. The installer requires
  `/home/agent/.opencode/bin/opencode`, which is absent in the checked sandbox.
  The upgrade stage skips OpenCode. Login helpers also use the missing path.
  Check binary discovery and upgrade permissions before changing the installer.
  Host OAuth mode, the OAuth bridge file, and the MCP gateway URL still match
  installer assumptions. Check remaining failures against reported output.

- [Reported failure] VS Code startup kit attachment returns `409 Conflict`
  during sandbox recreation. SBX reports an effective OAuth credential policy
  change. The kit declares no credentials. The cause is unverified.
  Preserve the sandbox and OAuth bindings. Use `vscode_tunnel` after each
  sandbox restart until attachment works. See the recovery steps in
  [HOST_SETUP_WIN.md](HOST_SETUP_WIN.md#tunnel-troubleshooting).
  Record host `sbx version`, sandbox inspection, and tunnel kit inspection.
  Remove credentials before sharing output. Compare the effective kit
  composition with the existing OAuth policy. Close after attachment and
  automatic tunnel startup pass without changes to stored logins.

- [Pending host checks] Validate the published VS Code startup kit from a host
  directory without this repository. The current kit uses v3 and defaults to
  user `agent`. It accepts user names only. Check the documented publisher
  allowlist setup, remote validation, inspection, and attachment. Offline
  validation cannot build this v3 source kit without a kit builder.
  After attachment works, check startup with the default and a custom user.
  Check sandbox restart, saved tunnel login, status, and disable controls.
  Automatic startup remains unconfirmed. Use
  [HOST_SETUP_WIN.md](HOST_SETUP_WIN.md#optional-vs-code-tunnel) for host steps.

- [Unreproduced] Codex "broken pipe" during selection or copying. Investigate if
  it recurs. Record the steps, versions, and relevant output.

# Feature roadmap

- enable a module system
- add RTK and Superpowers support
- git username/email wizard
