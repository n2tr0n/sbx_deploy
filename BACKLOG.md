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

- Investigate cloud OpenAI HTTP 401 in both harness credential checks while
  the host lists an account-scoped `oauth_refresh` secret. The helper reports
  API key access when it selects `OPENAI_API_KEY` and probes `/v1/models`.
  The user confirmed that cloud has no `SBX_CRED_OPENAI_MODE` and has
  `OPENAI_API_KEY`. OpenCode rejects the key. Codex requests authentication.
  The same deployment works locally. Preserve the local credential path.
  Confirm whether cloud creation preceded secret setup. Check the cloud
  OAuth route before changing credentials or configuration.

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
