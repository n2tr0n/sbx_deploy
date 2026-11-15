"""Check OpenCode selection and upgrade policy. Do not run the installer."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'sbx_local_opencode_deploy.sh').read_text(encoding='utf-8')
DISCOVERY = 'find_opencode() {' + SOURCE.split('find_opencode() {', 1)[1].split(
    '\nopencode_binary=$(find_opencode)', 1)[0] + '\nopencode_binary=$(find_opencode)\n'
UPGRADE = "stage_begin 'OpenCode' 'Checking upgrade'" + SOURCE.split(
    "stage_begin 'OpenCode' 'Checking upgrade'", 1)[1].split('\n# Shared deployment defaults;', 1)[0]
BASH = str(Path('C:/Program Files/Git/bin/bash.exe')) if os.name == 'nt' else shutil.which('bash')


class OpenCodeDiscovery(unittest.TestCase):
    def setUp(self):
        if not BASH or not Path(BASH).is_file():
            self.skipTest('Bash is required')
        temporary = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        for directory in ('image/bin', '.opencode/bin', 'state', 'work', 'work2', 'empty'):
            (self.home / directory).mkdir(parents=True, exist_ok=True)
        self.environment = dict(os.environ, HOME=self.home.as_posix())

    def binary(self, relative):
        path = self.home / relative
        path.write_text('#!/bin/sh\nexit 0\n')
        path.chmod(0o700)
        return path

    def shell(self, body):
        return subprocess.run([BASH, '--noprofile', '--norc'], input='set -euo pipefail\n' + body,
                              env=self.environment, capture_output=True, text=True, timeout=15)

    def stage(self, path, *, work='work', failure=False):
        # No real version, upgrade, package, or network operation is allowed.
        stub = '''
stage_begin() { :; }
stage_done() { printf '%s: %s\\n' "$1" "$2"; }
die() { printf '%s\\n' "$1" >&2; exit 1; }
exists() { [[ -e $1 || -L $1 ]]; }
kill_seconds=1
install_seconds=5
log_dir="$HOME/state"
'''
        stub += 'work_dir="$HOME/' + work + '"\n'
        stub += 'opencode_binary="$HOME/' + path + '"\n'
        stub += 'timeout() { printf "upgrade\\n" >> "$HOME/calls"; return ' + ('42' if failure else '0') + '; }\n'
        return self.shell(stub + UPGRADE)

    def test_path_choice_precedes_legacy_installation(self):
        self.binary('image/bin/opencode')
        self.binary('.opencode/bin/opencode')
        result = self.shell('PATH="$HOME/image/bin:$PATH"\n' + DISCOVERY +
                            '[[ $opencode_binary == "$HOME/image/bin/opencode" ]]\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_legacy_fallback_without_path_entry(self):
        self.binary('.opencode/bin/opencode')
        result = self.shell('PATH="$HOME/empty"\n' + DISCOVERY +
                            '[[ $opencode_binary == "$HOME/.opencode/bin/opencode" ]]\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_other_installation_is_preserved_without_upgrade_calls(self):
        binary = self.binary('image/bin/opencode')
        original = binary.read_bytes()
        result = self.stage('image/bin/opencode')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('automatic upgrade skipped', result.stdout)
        self.assertEqual(binary.read_bytes(), original)
        self.assertFalse((self.home / 'calls').exists())
        self.assertEqual(list((self.home / 'state').iterdir()), [])
        self.assertEqual(list((self.home / 'work').iterdir()), [])

    def test_legacy_upgrade_success_is_cached(self):
        self.binary('.opencode/bin/opencode')
        first = self.stage('.opencode/bin/opencode')
        self.assertEqual(first.returncode, 0, first.stderr)
        state = self.home / 'state/opencode-upgrade.sha256'
        modified = state.stat().st_mtime_ns
        second = self.stage('.opencode/bin/opencode', work='work2')
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn('Upgrade already completed', second.stdout)
        self.assertEqual((self.home / 'calls').read_text(), 'upgrade\n')
        self.assertEqual(state.stat().st_mtime_ns, modified)
        self.assertEqual(list((self.home / 'work2').iterdir()), [])

    def test_failed_upgrade_preserves_exit_status_and_has_no_success_cache(self):
        self.binary('.opencode/bin/opencode')
        result = self.stage('.opencode/bin/opencode', failure=True)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(list((self.home / 'state').iterdir()), [])


if __name__ == '__main__':
    unittest.main()
