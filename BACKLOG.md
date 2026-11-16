# Open work

Check reports against current code before changing behavior. Keep credentials
out of logs and shared output.

- Validate noninteractive public plugin downloads in the user's sandbox.
  Four mocked clone checks and wrapper, payload, and generated-helper syntax
  checks pass. Confirm successful download, cleanup after interruption, and
  an unchanged rerun. The user closed the old GitHub 401 investigation and
  chose to discard the affected test credentials.
  The later `sbxtest01` 401 cleared when the user supplied the correct GitHub
  key. Account access passed in the same running sandbox without recreation.
  Earlier wrong-key attempts do not establish a scripted-input defect.

- Validate the PowerShell host setup display and keyboard input in Windows
  Terminal. Check the SBX banner, compact stage rows, narrow windows,
  `NO_COLOR`, and line-input fallback. Check numbered choices, Enter defaults,
  y/n confirmation, Esc cancellation, and masked text input. Docker-managed
  cloud MCP remains blocked. The direct client method passed manual tool and key-usage
  checks in both harnesses; the full updated scripts still need validation.
  PowerShell 5.1 syntax and mocked menu, cancellation, and narrow-layout checks
  pass. A static display preview was reviewed without running host setup.

- Validate masked key entry in `sbx_cloud_host_setup_win.ps1` on a Windows
  terminal. GitHub, OpenAI, and Context7 keys must show `*` during input,
  then a save status. Check paste, empty input, cancellation, and a failed
  save. Keep values out of command arguments, receipts, logs, and output.
  PowerShell 5.1 syntax and mocked input, privacy, empty-input, and failed-save
  checks pass. Confirm terminal masking and live cloud standard input support.

- BLOCKED: Repair Docker-managed cloud MCP gateway creation. Manual OpenCode
  and shell creation with `--static-mcp context7` fails on SBX v0.53.0 with
  `secret not found ... name=docker`. Console creation also fails separately
  with Context7 and public no-auth DeepWiki. All six cloud diagnostics pass.
  Local gateway registration did not repair it. The cause and supported
  repair remain unconfirmed. Keep host credentials. Test sandboxes are
  disposable. This no longer blocks the direct Context7 setup path.

- Confirm recorded sandbox lookup after the setup reported `cloud-test01`
  absent. User inspection confirmed a running sandbox with the displayed
  name `opencode/cloud-test01`. The script compared `ls --quiet` output with
  the unqualified name. It now checks the recorded name directly with
  `inspect`. PowerShell 5.1 regression checks pass with a qualified list name.
  A later user report confirmed that the recorded sandbox was missing while
  its scoped secret still existed. The script now offers explicit recreation
  only after successful listing and a specific not-found inspection result.
  It reviews existing secrets and network access before creation. PowerShell
  syntax and mocked checks pass for old receipts, declined recreation,
  reused secrets, unrelated errors, and unchanged reruns. The user confirmed
  manual credential reuse: account access passed before deletion and after
  recreation of `credential-reuse-test`, without setting the secret again.
  Confirm the wizard's stale-receipt recovery path. Other errors still stop
  setup. Do not repeat the completed manual credential test.

- Validate `sbx_cloud_host_setup_win.ps1`, linked from `Windows setup` in
  `HOST_SETUP_CLOUD.md` in a disposable cloud sandbox. Local PowerShell 5.1
  syntax and mocked flow checks pass. Check CLI login, secret metadata and
  scope, global Context7 custom-secret setup, network access, and the Bash
  handoff. Confirm existing secrets, sandboxes, and intentional denies stay.
  Check unchanged reruns for no CLI calls or file writes. Interrupt creation
  and placeholder checks, then resume. Check expired sandbox and receipt recovery.
  The script must stop before the user pastes the Bash installer.
  The user confirmed direct Context7 tool calls in OpenCode and Codex with
  the global cloud key; the last Codex test added two dashboard queries.
  All 99 offline installer tests pass, including real TOMLKit config checks.
  PowerShell mocked checks pass for global key setup and legacy receipts.
  Check a fresh full script run, unchanged rerun, and both harnesses again
  after the automated integration. Do not repeat the completed manual test.

# Feature roadmap

- Add the same guided PowerShell setup for local sandboxes in
  `HOST_SETUP_WIN.md` after the cloud setup is complete.
- Validate the environment confirmation after the logo. Check Enter for local,
  cloud, saved, and `SBX_ENV` defaults. Check manual changes, cancellation,
  narrow terminals, and unchanged reruns. Every run must ask.
- Validate cloud MCP discovery from existing OpenCode or Codex configuration.
  The reported sandbox supplied no gateway URL variable. Check pending MCP
  setup without an attached endpoint, attachment, and a later rerun. Confirm
  gateway authentication in both harnesses without copying real credentials.
- Validate the single-file local/cloud profiles in disposable sandboxes. Check
  fresh install, unchanged rerun, upgrades, preservation, interruption, and both
  harnesses. See HOST_SETUP_CLOUD.md. Keep deployment free of build steps.
- Confirm the Docker cloud MCP gateway and OAuth placeholder contract from a real
  cloud `opencode` sandbox. Validate automatic selection in both environments
  using the supplied report patterns. Check overrides and ambiguous markers.
- Validate the VS Code tunnel and startup kit in cloud mode. Keep Webtop
  disabled until an authenticated cloud access path is supported.
- Add RTK and Superpowers support.
- Add a Git user name and email wizard.
- Clean up powershell script TUI; it's really sloppy
- Cloud post-deployment doesn't load new shell/alias ENV - requires manual session restart