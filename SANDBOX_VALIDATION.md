# Sandbox compatibility report

Copy the complete contents of `sbx_sandbox_validate.sh`. Paste them into
**sandbox Bash** and press Enter. You can paste from any directory. The file
does not need to exist in the sandbox first. Do not paste a command that refers
to a missing file. Do not add flags after the closing brace.

Use the same user that runs the installer. The default check uses local system
tools. If `python3` is absent from PATH, it collects a smaller Bash text report.
The fallback checks OS details, tool paths, path access, core packages, and sudo.
It does not install Python. Version and network probes are skipped in fallback mode.
It does not install packages, change settings, or read credential files.
It checks passwordless sudo with `sudo -n true`. System audit logs can record probes.
It prints JSON to stdout and a short summary to stderr. It saves a private
report at `~/sbx-sandbox-report.<random>.json` and shows the full path.
The Bash fallback uses `.txt` instead of `.json`.
It saves a runnable copy at `~/sbx_sandbox_validate.sh`. If a different file
already exists there, it keeps that file and saves a separate copy. It shows
the saved copy path. It has no prompts. Failed runs remove the partial report.

Each run saves a new report. No output redirection is needed.
A default run normally takes a few seconds. Missing tools do not
stop the remaining checks. Reports include paths and package versions. Review
these details before sharing. Do not add reports to the repository.

To run version commands and network probes, use:

```bash
bash ~/sbx_sandbox_validate.sh --versions --network
```

Use the printed rerun command if the saved copy has a different name.
Version commands can create caches through the tools they run. Each command
has a five-second limit. Network probes use fixed URLs and the current proxy.
Each request has a six-second limit. All network probes can take about one
minute. They use HEAD requests. They do not send login headers, follow
redirects, download response bodies, or run inference. The host proxy can
still apply its credential policy. Proxy values and response headers stay
out of the report.

An HTTP status proves that an HTTP response arrived. A 401, 403, 404, or 405
does not prove bad credentials or a failed service. Status `000` or a timeout
needs a separate network check. These probes do not validate MCP tools.

## Use the evidence

1. Collect a report from the affected image before deployment.
2. Record host details using [HOST_SETUP_WIN.md](HOST_SETUP_WIN.md#image-change-evidence).
3. Compare the report with a working sandbox, if available. Compare facts,
   not timestamps or the number of findings.
4. Confirm each mismatch before changing the installer. Missing deployment
   packages are expected on a fresh image. An unavailable hard-coded executable
   path is a separate compatibility gap.
5. Review and check the installer locally. Test it in a disposable sandbox.
   Collect a second report after deployment. Then check an unchanged rerun,
   preservation, interruption recovery, authentication, inference, and MCP tools.

The report is an inventory, not a deployment approval. Exit 0 means collection
completed. Findings remain in the JSON. Exit 2 means a usage or collection
error. Exit 130 means Ctrl+C. Exit 143 means termination. An interrupted
report can be incomplete.

The package list and expected OpenCode path describe the current installer.
Local tests check that these values stay aligned. The collector does not
check remote package candidates or upgrade permissions. It does not parse
user configuration or prove ownership. Keep saved logins and overrides.

Use a known working image version for repeatable tests when the host supports
it. Keep a separate disposable sandbox for new-image checks. Collect evidence
before changing the main installer.
