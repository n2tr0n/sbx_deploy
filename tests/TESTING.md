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

The tests need the installer and both `.py` files in this layout:

```text
sbx_local_opencode_deploy.sh
tests/
  test_auth_preservation.py
  test_config_ownership.py
```

Use a mounted repository or copy these files together. Pasting the installer
does not copy the tests into the sandbox.

## What the tests check

- `test_auth_preservation.py` checks saved authentication choices and reruns.
- `test_config_ownership.py` checks fresh configs, custom settings, MCP headers,
  other MCP servers, unchanged reruns, and interrupted config updates.

The tests read code from the installer and use temporary files. They do not run
the full installer, make network requests, or change live configs or logins.

`OK` means all tests passed. A skipped check did not run. Read skip messages
before you report full coverage. The tests do not prove that authentication,
inference, or MCP tools work in either harness.

## Config ownership and recovery

The installer records the model and MCP settings that it manages. It updates a
setting only while its value matches the recorded value. It preserves later
user edits and deletions. It stops if an existing setting has no ownership
record, even if that setting matches a deployment default.

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
