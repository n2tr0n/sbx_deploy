"""Check package timezone setup with local stubs. Never run real APT or sudo."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'sbx_local_opencode_deploy.sh').read_text(encoding='utf-8')
DEFAULT = next(line for line in SOURCE.splitlines() if line.startswith('package_timezone='))
SEED = 'seed_package_timezone() {' + SOURCE.split('seed_package_timezone() {', 1)[1].split('\nrequired_packages=(', 1)[0]
SEED = SEED.replace('/etc/timezone', '"$HOME/etc/timezone"').replace('/etc/localtime', '"$HOME/etc/localtime"')
APT = 'run_apt() {' + SOURCE.split('    run_apt() {', 1)[1].split('\n    }\n', 1)[0] + '\n}\n'
PACKAGES = "stage_begin 'Packages' 'Checking installed packages'" + SOURCE.split(
    "stage_begin 'Packages' 'Checking installed packages'", 1)[1].split("\nstage_begin 'Codex'", 1)[0]
BASH = str(Path('C:/Program Files/Git/bin/bash.exe')) if os.name == 'nt' else shutil.which('bash')


class PackageTimezone(unittest.TestCase):
    def setUp(self):
        if not BASH or not Path(BASH).is_file():
            self.skipTest('Bash is required')
        temporary = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        (self.home / 'etc').mkdir()
        (self.home / 'bin').mkdir()
        self.environment = dict(os.environ, HOME=self.home.as_posix())
        self.environment.pop('SBX_TIMEZONE', None)

    def shell(self, body, input_text=''):
        return subprocess.run([BASH, '--noprofile', '--norc', '-c', 'set -euo pipefail\n' + body],
                              input=input_text, env=self.environment, capture_output=True, text=True, timeout=15)

    def seed(self, prefix=''):
        return self.shell('''
exists() { [[ -e $1 || -L $1 ]]; }
die() { printf '%s\\n' "$1" >&2; exit 2; }
stage_operation() { :; }
run_as_root() { "$@"; }
debconf-set-selections() { cat > "$HOME/answers"; }
package_timezone_seeded=false
''' + prefix + '\n' + DEFAULT + '\n' + SEED + '\nseed_package_timezone\nprintf "seeded=%s\\n" "$package_timezone_seeded"\n')

    def test_new_setup_defaults_to_toronto(self):
        result = self.seed()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('seeded=true', result.stdout)
        self.assertEqual((self.home / 'answers').read_text(),
                         'tzdata tzdata/Areas select America\ntzdata tzdata/Zones/America select Toronto\n')
        self.assertEqual(list((self.home / 'etc').iterdir()), [])

    def test_existing_timezone_is_preserved(self):
        for name in ('timezone', 'localtime'):
            with self.subTest(name=name):
                path = self.home / 'etc' / name
                path.write_text('user timezone\n')
                result = self.seed()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('seeded=false', result.stdout)
                self.assertFalse((self.home / 'answers').exists())
                self.assertEqual(path.read_text(), 'user timezone\n')
                path.unlink()

    def test_explicit_new_timezone_and_invalid_input(self):
        result = self.seed('SBX_TIMEZONE=America/Argentina/Buenos_Aires')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('tzdata/Zones/America select Argentina/Buenos_Aires', (self.home / 'answers').read_text())
        (self.home / 'answers').unlink()
        result = self.seed("SBX_TIMEZONE='../bad timezone'")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse((self.home / 'answers').exists())

    def test_apt_gets_frontend_after_elevation_and_no_stdin(self):
        fake = self.home / 'bin/apt-get'
        fake.write_text('''#!/bin/sh
printf '%s\\n' "$DEBIAN_FRONTEND" > "$HOME/frontend"
printf '%s\\n' "$@" > "$HOME/apt-args"
if IFS= read -r unexpected; then exit 70; fi
printf 'apt progress\\n' >&5
printf 'apt output\\n'
exit "${FIXTURE_APT_EXIT:-0}"
''')
        fake.chmod(0o700)
        body = '''
PATH="$HOME/bin:$PATH"
apt_status_file="$HOME/apt-status"
apt_output_file="$HOME/apt-output"
stop_spinner() { :; }
stage_operation() { :; }
run_as_root() { printf '%s\\n' "$@" > "$HOME/root-args"; "$@"; }
''' + APT + '\nrun_apt "Fixture" install -y tzdata\n'
        result = self.shell(body, input_text='pending pasted script text\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / 'frontend').read_text(), 'noninteractive\n')
        self.assertTrue((self.home / 'root-args').read_text().startswith('env\nDEBIAN_FRONTEND=noninteractive\nsh\n'))
        self.assertEqual((self.home / 'apt-status').read_text(), 'apt progress\n')
        self.assertEqual((self.home / 'apt-output').read_text(), 'apt output\n')
        self.environment['FIXTURE_APT_EXIT'] = '42'
        result = self.shell(body)
        self.assertEqual(result.returncode, 42, result.stderr)

    def test_unchanged_packages_skip_timezone_writes_and_apt(self):
        result = self.shell('''
stage_begin() { :; }
stage_done() { printf '%s\\n' "$2"; }
dpkg-query() { printf installed; }
run_as_root() { exit 98; }
debconf-set-selections() { exit 99; }
''' + DEFAULT + '\n' + PACKAGES)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Already installed', result.stdout)
        self.assertEqual(list((self.home / 'etc').iterdir()), [])


if __name__ == '__main__':
    unittest.main()
