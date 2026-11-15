# Open work

Check reports against current code before changing behavior. Keep credentials
out of logs and shared output.

# Feature roadmap

- Validate first-paste environment selection in the reported cloud sandbox.
  Its hostname matches the cloud pattern, but no matching sandbox ID was
  supplied. Check the terminal prompt, cancellation, and saved-profile rerun.
- Validate the single-file local/cloud profiles in disposable sandboxes. Check
  fresh install, unchanged rerun, upgrades, preservation, interruption, and both
  harnesses. See HOST_SETUP_CLOUD.md. Keep deployment free of build steps.
- Confirm the cloud MCP endpoint and OAuth placeholder contract from a real
  cloud `opencode` sandbox. Check startup markers and automatic selection.
- Validate the VS Code tunnel and startup kit in cloud mode. Keep Webtop
  disabled until an authenticated cloud access path is supported.
- Add RTK and Superpowers support.
- Add a Git user name and email wizard.
