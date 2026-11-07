# SBX Deploy

`sbx_deploy.sh` installs the Debian/Ubuntu sandbox tools, supplied tmux
configuration, TPM, tmux-resurrect, UTF-8 tmux wrapper, and Bash aliases.

Paste the **entire script** into Bash and press Enter, or save it and run:

```bash
bash sbx_deploy.sh
```

Run as the sandbox user whose home directory should receive the plugins and
wrapper. System changes use passwordless `sudo -n`; running as root instead
installs the home-directory files for root.

## Refactor notes

- A subshell contains strict mode and cleanup traps when pasted into a live shell.
- Shared error handling and system-file replacement remove repeated code.
- Local package checks skip APT entirely once all required packages are installed.
- Both plugin checkouts use shallow clones staged beside their destinations.
  Completed reruns skip cloning; interrupted downloads leave final paths untouched.
- Config replacements and startup-file appends are staged before publication.
  Existing content is preserved, matching files are skipped, and identical
  system-file backups are reused after an interrupted run.
- The banner, tmux config, wrapper contents, and PATH block are unchanged.
- Newly installed `makepass` aliases use Python 3, with `python3-passlib` included
  in the package list. Previously marked alias blocks are preserved as supplied.

Existing unusable plugin paths and differing wrappers require manual attention;
the installer never deletes them. Symlinks that need configuration changes are
also left untouched. Existing SBX markers are trusted to identify complete blocks.

The supplied tmux config retains its one-billion-line history limit, which can
allow substantial memory use. Existing tmux servers gain plugin bindings during
setup; reload the full config explicitly using the printed instructions.

## Verification

Changes are reviewed statically. Bash syntax is checked with `bash -n`; the
installer is not executed locally. Installation and rerun behavior must be tested
in the sandbox.
