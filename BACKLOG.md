# Open work

Check each report against current code before changing behavior. Keep real
credentials out of logs and shared output.

- [Reported image regression; pending sandbox checks] Collect requirements
  with `sbx_sandbox_validate.sh` on the updated image. The report collects
  paths, package versions, permissions, and credential-file metadata.
  Optional probes check tool versions and network responses. Local checks
  do not confirm sandbox compatibility. Record host image and kit details
  using [SANDBOX_VALIDATION.md](SANDBOX_VALIDATION.md). Compare a fresh report
  with a working sandbox before changing installer behavior. Confirm all
  reported failures. Keep this item until collection and the required
  deployment checks pass in user sandboxes.
  The sandbox report confirms Debian 13, passwordless sudo, and no installed
  Python 3. Node, npm, and Codex are absent from PATH. The installer already
  installs Python 3 and standalone Codex. It has no Node or npm requirement.
  Collect the remaining package, network, authentication, and MCP evidence.

- [Confirmed compatibility gap] SBX v0.53.0 OpenCode sandbox uses Debian 13
  and OpenCode v2.3.0 at `/usr/local/bin/opencode`. The installer requires
  `/home/agent/.opencode/bin/opencode`, which is absent in the checked sandbox.
  The upgrade stage skips OpenCode. Login helpers also use the missing path.
  The latest sandbox report confirms that `/usr/local/bin/opencode` is an
  executable symlink owned by root. It points to `/opt/opencode/bin/opencode`.
  User `agent` cannot write through it. The latest version check confirms
  OpenCode v2.3.0. The target owner and supported upgrade method remain
  unverified. Do not assume that the user-local curl updater can replace it.
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
