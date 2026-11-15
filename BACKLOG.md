# Open work

Check reports against current code before changing behavior. Keep credentials
out of logs and shared output.

- BLOCKED: Complete the guided Windows setup for cloud sandboxes in
  `sbx_cloud_host_setup.ps1`, linked from `HOST_SETUP_CLOUD.md`.
  Required MCP setup cannot pass live validation.
  On SBX v0.53.0, manual OpenCode and shell creation with
  `--static-mcp context7` fails with `secret not found ... name=docker`.
  Shell creation without MCP succeeds. The Console also fails with Context7
  and, separately, with public no-auth DeepWiki. Both Console tests report
  `MCP servers couldn't be connected. Try again.` All six cloud diagnostic
  checks pass. Local gateway registration and sign-in did not repair it.
  The failure occurs outside the PowerShell script and affects more than
  Context7. The exact cause and supported repair remain unconfirmed.
  Get Docker guidance or a verified cloud MCP repair before continuing live
  validation. A support report is in `HOST_SETUP_CLOUD.md`. Do not create a
  guessed `docker` token or replace host credentials. Test sandboxes are
  disposable; the user permits deletion and recreation.

- Confirm recorded sandbox lookup after the setup reported `cloud-test01`
  absent. User inspection confirmed a running sandbox with the displayed
  name `opencode/cloud-test01`. The script compared `ls --quiet` output with
  the unqualified name. It now checks the recorded name directly with
  `inspect`. PowerShell 5.1 regression checks pass with a qualified list name.
  Confirm resume with the updated script. Keep inspection errors fatal and
  do not recreate a recorded sandbox.

- Validate cloud creation with `--static-mcp` and the connected Context7 name.
  The user confirmed that `mcp load` cannot add a missing gateway. The script
  now asks for Context7 before creation and passes `--static-mcp`. Existing
  sandboxes without a gateway stop with recovery instructions. PowerShell 5.1
  syntax and mocked checks pass for default and custom server names, retry,
  and missing-gateway preservation. Confirm the gateway and tools in a new
  sandbox. Preserve old sandboxes and secrets.

- Validate `sbx_cloud_host_setup.ps1`, linked from `Windows setup` in
  `HOST_SETUP_CLOUD.md` in a disposable cloud sandbox. Local PowerShell 5.1
  syntax and mocked flow checks pass. Check CLI login, secret metadata and
  scope, initial network exceptions, Context7 authorization, and the Bash
  handoff. Confirm existing secrets, sandboxes, and intentional denies stay.
  Check unchanged reruns for no CLI calls or file writes. Interrupt creation
  and MCP attachment, then resume. Check expired sandbox and receipt recovery.
  The script must stop before the user pastes the Bash installer.

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
- Confirm the cloud MCP endpoint and OAuth placeholder contract from a real
  cloud `opencode` sandbox. Validate automatic selection in both environments
  using the supplied report patterns. Check overrides and ambiguous markers.
- Validate the VS Code tunnel and startup kit in cloud mode. Keep Webtop
  disabled until an authenticated cloud access path is supported.
- Add RTK and Superpowers support.
- Add a Git user name and email wizard.
