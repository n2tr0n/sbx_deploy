"""Test public plugin downloads with fake commands. Do not run Git or the installer."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'sbx_local_opencode_deploy.sh').read_text(encoding='utf-8')
BASH = str(Path('C:/Program Files/Git/bin/bash.exe')) if os.name == 'nt' else shutil.which('bash')
CLONE = 'clone_plugin() (' + SOURCE.split('clone_plugin() (', 1)[1].split('\nif ! tpm_ready;', 1)[0]


class PluginClone(unittest.TestCase):
    def setUp(self):
        if not BASH or not Path(BASH).is_file():
            self.skipTest('Bash is required')
        self.temp = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_clone(self, status=0, twice=False):
        # Fake Git checks the invocation and creates only disposable fixture files.
        fixture = r'''
set -euo pipefail
cd -- "$FIXTURE_ROOT"
plugin_dir=$PWD/plugins
work_dir=$PWD/work
mkdir -p "$work_dir" "$plugin_dir"
printf keep > "$plugin_dir/user-data"
kill_seconds=5 install_seconds=300
exists() { [[ -e $1 || -L $1 ]]; }
die() { printf '%s\n' "$1" >&2; exit "$2"; }
timeout() { shift 2; "$@"; }
git() {
    [[ ${GIT_TERMINAL_PROMPT-} == 0 && ${GIT_ASKPASS-} == /bin/false && ${SSH_ASKPASS-} == /bin/false ]] || return 91
    [[ $1 == -c && $2 == credential.helper= && $3 == -c && $4 == core.askPass=/bin/false && $5 == -c && $6 == credential.interactive=false ]] || return 92
    shift 6
    [[ $1 == clone && $2 == --depth && $3 == 1 && $4 == https://github.com/tmux-plugins/tpm ]] || return 93
    if IFS= read -r pending; then return 94; fi
    printf call >> "$work_dir/calls"
    mkdir -p -- "$5"
    printf partial > "$5/fixture"
    if (( FIXTURE_STATUS != 0 )); then
        printf 'Simulated public clone failure\n' >&2
        return "$FIXTURE_STATUS"
    fi
}
'''
        commands = '\nclone_plugin tpm "$plugin_dir/tpm"\n'
        if twice:
            commands += 'clone_plugin tpm "$plugin_dir/tpm"\n'
        return subprocess.run(
            [BASH, '--noprofile', '--norc'], input=fixture + CLONE + commands,
            text=True, encoding='utf-8', capture_output=True, timeout=10,
            env={**os.environ, 'FIXTURE_ROOT': self.root.as_posix(), 'FIXTURE_STATUS': str(status)})

    def assert_clean(self):
        self.assertEqual(list((self.root / 'plugins').glob('.plugin-stage.*')), [])
        self.assertEqual((self.root / 'plugins/user-data').read_text(), 'keep')

    def test_public_clone_is_noninteractive_and_unchanged_rerun_skips_git(self):
        result = self.run_clone(twice=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'work/calls').read_text(), 'call')
        self.assertTrue((self.root / 'plugins/tpm/fixture').exists())
        self.assert_clean()

    def test_failure_preserves_status_and_removes_partial_clone(self):
        result = self.run_clone(status=128)
        self.assertEqual(result.returncode, 128, result.stderr)
        self.assertIn('Public plugin download failed', result.stderr)
        self.assertFalse((self.root / 'plugins/tpm').exists())
        self.assert_clean()

    def test_timeout_preserves_status_and_removes_partial_clone(self):
        result = self.run_clone(status=124)
        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn('Public plugin download timed out', result.stderr)
        self.assertFalse((self.root / 'plugins/tpm').exists())
        self.assert_clean()

    def test_interruption_preserves_status_and_removes_partial_clone(self):
        result = self.run_clone(status=130)
        self.assertEqual(result.returncode, 130, result.stderr)
        self.assertFalse((self.root / 'plugins/tpm').exists())
        self.assert_clean()


if __name__ == '__main__':
    unittest.main()
