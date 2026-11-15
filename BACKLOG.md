# Open work

Check reports against current code before changing behavior. Keep credentials
out of logs and shared output.

- Document how to create network exceptions in the Docker Agentic Platform
  cloud UI. Verify the available methods, rule scope, and required access.
  Add the instructions to `HOST_SETUP_CLOUD.md`. Preserve intentional denies.

- Investigate intermittent cloud environment detection failure at the end of
  this session. The user reported "Environment markers are unknown or
  conflict" in a cloud sandbox. The cause is unknown. Current detection
  checks the hostname pattern and environment markers. Compare reports
  from working and failing runs before changing detection. Use manual
  `cloud` selection until then.

- Validate the cloud OpenCode OAuth service restart in the full installer.
  The user confirmed that the exact placeholder import supports standalone
  inference in OpenCode v2.3.0. Normal inference failed until `opencode service
  restart`, then passed. Deployment now restarts once and records success.
  Check fresh deployment, an unchanged rerun with no restart or receipt write,
  interrupted restart recovery, and saved login preservation. Keep OAuth and
  the working local credential path. Codex inference still needs confirmation.

- Review local OpenCode managed OAuth updates. OpenCode v2.3.0 `auth import`
  skips existing credential IDs. It does not update values. The cloud path
  now verifies imports and stops on a different existing managed value.
  The local expiry-update path still needs a supported update operation and
  a check against actual import semantics. Preserve saved logins and IDs.

# Feature roadmap

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
