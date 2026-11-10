# Open work

Check each report against current code before changing behavior. Keep real
credentials out of logs and shared output.

- [Pending host check] VS Code startup kit: confirm the published Git URL works
  from a host directory without this repository. The host rejected the source
  with only `docker.io/` and `dhi.io/` allowed. Check the documented publisher
  allowlist change and plain URL command. The next attachment failed because
  the sandbox uses v3 and the tunnel kit used v2. The local kit now uses v3
  lifecycle configuration. Publish it, then check validation, inspection,
  attachment, and tunnel startup after a sandbox restart.
  Local SBX recognizes the v3 source, but offline validation has no kit builder.

- [Unreproduced] Codex "broken pipe" during selection or copying. Investigate if
  it recurs. Record the steps, versions, and relevant output.

# Feature roadmap

- enable a module system
- add RTK and Superpowers support
