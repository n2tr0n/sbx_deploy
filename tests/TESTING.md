# Installer tests

Keep these tests in the source repository. Normal deployment needs only the
installer. Do not include Python caches in releases.

## Run the tests

Use Python 3.11 or later and TOMLKit (`tomlkit`). Without TOMLKit, Codex config
checks are skipped. The installer supplies TOMLKit in the sandbox.

Run from the repository root in sandbox Bash:

```bash
python3 -m unittest discover -s tests -v
```

On Windows, use `python` instead of `python3`.

The tests need both scripts and the `.py` files in this layout:

```text
sbx_local_opencode_deploy.sh
sbx_sandbox_validate.sh
tests/
  test_auth_preservation.py
  test_cloud_credentials.py
  test_config_ownership.py
  test_download_errors.py
  test_environment_profiles.py
  test_opencode_discovery.py
  test_package_timezone.py
  test_sandbox_validator.py
  test_shell_startup.py
  test_tmux_snapshot.py
```

Use a mounted repository or copy these files together. Pasting the installer
does not copy the tests into the sandbox.

## What the tests check

- `test_environment_profiles.py` checks explicit and automatic selection,
  unknown environments, cloud URL privacy, saved profile ownership, moved
  sandboxes, terminal selection input and cancellation, and wrapper and payload
  syntax. It checks the logo before the environment card, confirmation defaults,
  manual selection, and narrow terminals. It also checks cloud MCP discovery, JSONC precedence, URL privacy,
  and pending setup without an endpoint. It runs no deployment operations.
- `test_cloud_credentials.py` checks cloud startup OAuth, environment API keys,
  custom providers, private diagnostics, and cloud recovery instructions.
- `test_auth_preservation.py` checks saved authentication choices and reruns.
  It checks cloud OAuth imports without a bridge, fixed expiry, credential ID
  conflicts, and the local bridge requirement. It checks cloud service restart
  receipts, unchanged runs, failed restart recovery, and skipped imports.
  It checks local skipped imports and changed expiry failures. It preserves
  saved entries and models imports that skip existing IDs, as v2.3.0 does.
- `test_config_ownership.py` checks fresh configs, custom settings, MCP headers,
  other MCP servers, unchanged reruns, and interrupted config updates.
- `test_download_errors.py` checks local and cloud recovery commands, known
  redirect hosts, unrelated failures, concise output, narrow terminals, cleanup,
  and preserved exit codes. It uses synthetic logs and runs no host commands.
- `test_opencode_discovery.py` checks PATH selection, the user-local fallback,
  preservation of other installations, upgrade caching, and failure status.
- `test_package_timezone.py` checks new timezone answers, existing timezone
  preservation, APT input and progress, failure status, and unchanged reruns.
- `test_sandbox_validator.py` checks report privacy, requirement lists, and
  probe cleanup. Its paste checks use Windows Git Bash and skip if absent.
- `test_shell_startup.py` checks DHI startup order, login and non-login shells,
  user aliases and hooks, startup migration, and unchanged reruns. It also
  checks first-paste activation, failure status, child-shell behavior, and
  matching saved-installer refresh code.

The tests read code from the installer and use temporary files. They do not run
the full installer, make network requests, or change live configs or logins.

`test_tmux_snapshot.py` checks snapshot path diagnostics, warning counts,
failure exit codes, and saved snapshot preservation.

`OK` means all tests passed. A skipped check did not run. Read skip messages
before you report full coverage. The tests do not prove that authentication,
inference, or MCP tools work in either harness.

## Config ownership and recovery

The installer records the model and MCP settings that it manages. It updates a
setting only while its value matches the recorded value. It preserves later
user edits and deletions. It preserves matching unowned settings without
claiming ownership. It stops before changing a different unowned setting.

If deployment stops because ownership is unknown, keep the config, backups,
and ownership records. Follow the recovery paths in the error message. Create
managed defaults, then copy reviewed custom settings into the new config.
Do not copy credentials into ownership records. Do not restore a whole backup
over a newer config without review.

## Full sandbox checks

After these tests pass, the user must still check the full installer in
disposable sandboxes. Check fresh installation, an unchanged rerun, upgrades,
custom settings, and interruption recovery. Check authentication, inference,
and MCP tools in both harnesses. See [AGENTS.md](../AGENTS.md#validation) for the
checklist and [BACKLOG.md](../BACKLOG.md) for open work.
