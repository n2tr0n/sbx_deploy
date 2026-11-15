# Sandbox validation

## Compare local and cloud detection

Paste the complete `sbx_sandbox_type_report.sh` into Bash in each sandbox type.
Label the outputs `LOCAL` and `CLOUD`, then share both. Use the same agent
image if possible. State whether the installer ran in each sandbox.

This report needs only Bash and standard tools. It installs nothing, writes
no files, reads no credentials, and makes no network requests. It prints
selected environment variable names, fixed machine categories, path presence,
and filesystem types. It prints no variable values, sandbox IDs, or mount sources.
Do not set `SBX_ENV` for this comparison. Leave existing settings unchanged.
An installer choice is not evidence of the underlying sandbox type.
The report collects clues. It does not select a sandbox type or validate deployment.

## Run

Paste the complete `sbx_sandbox_validate.sh` into **sandbox Bash**, from any
directory, as the installer user. Do not append flags to the paste.

The tool saves a private report and runnable copy under HOME and prints their
paths. It keeps any different existing copy. Review paths and versions before
sharing reports; keep reports out of the repository. No output redirection is needed.

Default checks install nothing, change no settings, and read no credential
files. They test sudo with `sudo -n true`; system audit logs can record probes.
Python 3 produces JSON. Without it, a smaller Bash text report is collected.

For optional probes, use the printed rerun command or:

```bash
bash ~/sbx_sandbox_validate.sh --versions --network
```

These probes require Python. Version commands can create tool caches and have
five-second limits. Network checks use fixed URLs, HEAD requests, and the current
proxy, with six-second request limits; allow about one minute. They send no login
headers, follow no redirects, and download no bodies. Host proxy policy still
applies. Proxy values and response headers stay out of reports.
For cloud checks, export `SBX_ENV=cloud` first. Set `SBX_MCP_GATEWAY_URL` if
the sandbox does not export `MCP_GATEWAY_URL`. Unknown or unsafe gateway URLs
are not probed. Reports show variable presence and fixed environment categories,
not URLs, cloud IDs, or credential values. See [cloud setup](HOST_SETUP_CLOUD.md).

## Interpret results

- Exit 0 means collection completed, not that deployment passed. Exit 2 means
  an error; 130 or 143 means interruption. Failed runs remove partial report files.
- Missing deployment packages can be normal before installation.
- HTTP 401/403/404/405 alone does not prove bad credentials or service failure.
  Status 000 or a timeout needs a network check.
- Shell checks return loader flags without printing or executing startup text.
  Check live aliases and prompts after reconnect and in a new tmux pane.
- The report cannot prove repository access, upgrade permissions, configuration
  ownership, authentication, inference, or MCP operation. Preserve logins and overrides.

## Check deployment changes

1. Collect a report before deployment and compare with a working sandbox if
   available. Compare facts, not timestamps or finding counts. Record
   [host details](HOST_SETUP_WIN.md#image-change-evidence).
2. Confirm each mismatch against the installer before changing behavior.
   Run local syntax checks and [tests](tests/TESTING.md).
3. Test in a disposable sandbox and collect an after-report. Complete the
   remaining [sandbox checks](AGENTS.md#validation): fresh install, unchanged
   rerun, upgrades and preservation, interruption recovery, and both harnesses.
