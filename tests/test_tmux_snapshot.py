"""Check snapshot diagnostics and saved state with local helper fixtures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'sbx_local_opencode_deploy.sh').read_text(encoding='utf-8')
STAGE = "stage_begin 'tmux snapshot'" + SOURCE.split("stage_begin 'tmux snapshot'", 1)[1].split("\nstage_begin 'Shell setup'", 1)[0]
RECORD = 'record_issue() {' + SOURCE.split('record_issue() {', 1)[1].split('\n}\n', 1)[0] + '\n}\n'
WARN = 'warn() {' + SOURCE.split('warn() {', 1)[1].split('\n}\n', 1)[0] + '\n}\n'
BASH = str(Path('C:/Program Files/Git/bin/bash.exe')) if os.name == 'nt' else shutil.which('bash')


class TmuxSnapshot(unittest.TestCase):
    def setUp(self):
        if not BASH or not Path(BASH).is_file():
            self.skipTest('Bash is required')
        temporary = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        (self.home / 'plugin/scripts').mkdir(parents=True)
        (self.home / 'work').mkdir()

    def run_stage(self, helper):
        (self.home / 'plugin/scripts/helpers.sh').write_text(helper, encoding='utf-8')
        body = '''set -euo pipefail
work_dir="$HOME/work"
resurrect_dir="$HOME/plugin"
log_file="$HOME/run.log"
warning_count=0
amber=
declare -a issue_keys=() issue_titles=() issue_details=() issue_actions=()
stage_begin() { stage=$1; rm -f -- "$work_dir/changed"; }
stage_done() { printf '%s: %s\\n' "$1" "$2"; }
stop_spinner() { :; }
start_spinner() { :; }
report_row() { printf '%s\\n' "$*"; }
exists() { [[ -e $1 || -L $1 ]]; }
die() { printf '%s\\n' "$1" >&2; exit "${2:-1}"; }
exec 3>&1
''' + RECORD + WARN + STAGE + '\nprintf "Warnings: %s\\n" "$warning_count"\n'
        return subprocess.run([BASH, '--noprofile', '--norc', '-c', body],
                              env=dict(os.environ, HOME=self.home.as_posix()),
                              capture_output=True, text=True, timeout=15)

    def test_masked_helper_error_counts_warning_and_skips_seed(self):
        # Match upstream: a failed substitution inside a successful command.
        result = self.run_stage('''hostname() { printf 'hostname: command not found\\n' >&2; return 127; }
resurrect_dir() { printf '%s%s\\n' "$HOME/saves/" "$(hostname)"; }
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('hostname: command not found', result.stderr)
        self.assertIn('Warnings: 1', result.stdout)
        self.assertIn('attention: Snapshot seed skipped', result.stdout)
        self.assertFalse((self.home / 'saves').exists())
        self.assertIn('snapshot seed skipped', (self.home / 'run.log').read_text())

    def test_helper_failure_preserves_exit_code(self):
        result = self.run_stage('resurrect_dir() { printf "path check failed\\n" >&2; return 42; }\n')
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertIn('path check failed', result.stderr)
        self.assertFalse((self.home / 'saves').exists())

    def test_saved_snapshot_is_unchanged(self):
        saves = self.home / 'saves'
        saves.mkdir()
        saved = saves / 'tmux_resurrect_user.txt'
        saved.write_text('user snapshot\n')
        before = saved.stat().st_mtime_ns
        result = self.run_stage('resurrect_dir() { printf "%s/saves\\n" "$HOME"; }\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        self.assertIn('Warnings: 0', result.stdout)
        self.assertIn('Existing resurrect state preserved', result.stdout)
        self.assertEqual(saved.read_text(), 'user snapshot\n')
        self.assertEqual(saved.stat().st_mtime_ns, before)
        self.assertEqual(list(saves.iterdir()), [saved])


if __name__ == '__main__':
    unittest.main()
