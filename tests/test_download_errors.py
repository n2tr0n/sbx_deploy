"""Check download recovery output with synthetic logs. Do not deploy or use SBX."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'sbx_local_opencode_deploy.sh').read_text(encoding='utf-8')
REPORT = ('record_issue() {' + SOURCE.split('record_issue() {', 1)[1].split('\n# Pad text separately', 1)[0] +
          'report_line() {' + SOURCE.split('report_line() {', 1)[1].split('# FIGlet Slant', 1)[0])
FAILURE = 'die() {' + SOURCE.split('die() {', 1)[1].split('\ncleanup_installer() {', 1)[0]
FINISH = 'finish_installer() {' + SOURCE.split('finish_installer() {', 1)[1].split('\ntrap finish_installer EXIT', 1)[0]
BASH = str(Path('C:/Program Files/Git/bin/bash.exe')) if os.name == 'nt' else shutil.which('bash')
CLOUD_HOST = 'sbx-001m7e4z4e3xjatm8nqcnwywz2m'
CLOUD_ID = 'sbx_001m7e4z4e3xjatm8nqcnwywz2m'


class DownloadErrors(unittest.TestCase):
    def setUp(self):
        if not BASH or not Path(BASH).is_file():
            self.skipTest('Bash is required')
        temporary = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.environment = dict(os.environ, HOME=self.home.as_posix(), HOSTNAME=CLOUD_HOST, COLUMNS='80')
        for name in ('SBX_ENV', 'SBX_NETWORK_SCOPE', 'SBX_SANDBOX_NAME', 'BASH_ENV'):
            self.environment.pop(name, None)

    def failure(self, host, *, status=6, service='vscode', columns='80', offset=False):
        work = self.home / 'work'
        work.mkdir(exist_ok=True)
        log = self.home / 'run.log'
        old = 'curl: (6) Could not resolve host: releases.openai.com\n' if offset else ''
        message = 'curl: (%d) %s\n' % (status, 'Could not resolve host: ' + host if status == 6 else
                                        'The requested URL returned error: 403')
        log.write_bytes((old + message).encode())
        self.environment['COLUMNS'] = columns
        self.environment['FIXTURE_ENVIRONMENT'] = self.environment.get('SBX_NETWORK_SCOPE', 'cloud' if self.environment['HOSTNAME'] == CLOUD_HOST else 'local')
        self.environment['FIXTURE_STATUS'] = str(status)
        self.environment['FIXTURE_SERVICE'] = service
        self.environment['FIXTURE_OFFSET'] = str(len(old.encode()))
        setup = '''
set -euo pipefail
exec 3>&1 4>&2
log_file="$HOME/run.log"
work_dir="$HOME/work"
operation_offset=$FIXTURE_OFFSET
sbx_environment=$FIXTURE_ENVIRONMENT
stage='VS Code'
operation='Downloading CLI'
started_at=$SECONDS
concise_failure=false
finishing=false
utf8=false
muted= reset= red= amber= green=
warning_count=0
declare -a issue_keys=() issue_titles=() issue_details=() issue_actions=()
stop_spinner() { :; }
drain_output() { :; }
cleanup_installer() { :; }
sbx() { printf 'UNEXPECTED HOST ACTION\\n' >&3; exit 99; }
'''
        body = '\n'.join((setup, REPORT, FAILURE, FINISH)) + '''
trap finish_installer EXIT
exec >> "$log_file" 2>&1
download_failure 'CLI download' "$FIXTURE_STATUS" "$FIXTURE_SERVICE"
'''
        result = subprocess.run([BASH, '--noprofile', '--norc'], input=body, text=True, encoding='utf-8',
                                capture_output=True, env=self.environment, timeout=15)
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        self.assertFalse(work.exists(), 'Failure cleanup did not remove the fixture workspace')
        self.assertNotIn('UNEXPECTED HOST ACTION', result.stdout)
        self.assertIn('Log:', result.stdout)
        return result.stdout, log.read_text()

    def test_cloud_update_failure_prints_both_hosts_and_correct_id(self):
        output, log = self.failure('update.code.visualstudio.com')
        command = ('sbx --cloud policy allow network "update.code.visualstudio.com:443,'
                   'vscode.download.prss.microsoft.com:443" --sandbox ' + CLOUD_ID)
        self.assertIn(command, output)
        self.assertIn('sbx --cloud policy ls ' + CLOUD_ID, output)
        self.assertNotIn('sbx --cloud policy check', output)
        self.assertIn('Keep intentional denies', output)
        self.assertIn('getent ahosts update.code.visualstudio.com', output)
        self.assertIn('bash ~/sbx_local_opencode_deploy.sh', output)
        self.assertEqual(output.count('Cannot resolve update.code.visualstudio.com (curl 6).'), 1)
        self.assertNotIn('curl: (6)', output)
        self.assertNotIn('SBX Deploy:', output)
        self.assertIn('curl: (6)', log)
        self.assertTrue(any(command in line for line in output.splitlines()))

    def test_cdn_and_codex_redirect_hosts_are_recognised(self):
        for host, service, resources in (
            ('vscode.download.prss.microsoft.com', 'vscode', 'update.code.visualstudio.com:443,vscode.download.prss.microsoft.com:443'),
            ('releases.openai.com', 'codex', 'chatgpt.com:443,releases.openai.com:443')):
            with self.subTest(host=host):
                output, _ = self.failure(host, service=service)
                self.assertIn('policy allow network "' + resources + '"', output)

    def test_local_policy_guidance_and_explicit_cloud_overrides(self):
        self.environment['HOSTNAME'] = 'opencode-local-test'
        output, _ = self.failure('releases.openai.com', service='codex')
        self.assertIn('sbx policy check network releases.openai.com:443 --sandbox opencode-local-test', output)
        self.assertNotIn('sbx --cloud', output)
        self.environment['SBX_NETWORK_SCOPE'] = 'cloud'
        self.environment['SBX_SANDBOX_NAME'] = 'my-cloud-sandbox'
        output, _ = self.failure('releases.openai.com', service='codex')
        self.assertIn('sbx --cloud policy ls my-cloud-sandbox', output)

    def test_unknown_host_or_non_dns_error_does_not_suggest_allow_rule(self):
        for host, status in (('unknown.example', 6), ('update.code.visualstudio.com', 22)):
            with self.subTest(status=status):
                output, _ = self.failure(host, status=status, offset=True)
                self.assertNotIn('policy allow', output)
                self.assertNotIn('SBX Deploy:', output)
                self.assertIn('curl: (' + str(status) + ')', output)

    def test_narrow_terminal_keeps_command_on_one_line(self):
        output, _ = self.failure('update.code.visualstudio.com', columns='40')
        self.assertNotIn('+---', output)
        command = next(line for line in output.splitlines() if 'policy allow network' in line)
        self.assertIn('vscode.download.prss.microsoft.com:443', command)
        self.assertIn('--sandbox ' + CLOUD_ID, command)

    def test_unsafe_target_is_not_inserted_in_host_commands(self):
        self.environment['SBX_SANDBOX_NAME'] = 'bad; unsafe-command'
        output, _ = self.failure('update.code.visualstudio.com')
        self.assertNotIn('unsafe-command', output)
        self.assertIn('$sandboxName = Read-Host', output)
        self.assertIn('--sandbox $sandboxName', output)

    def test_success_summary_uses_selected_environment(self):
        for environment in ('local', 'cloud'):
            work = self.home / 'summary-work'
            work.mkdir()
            setup = '''
set -euo pipefail
exec 3>&1 4>&2
log_file="$HOME/run.log"
work_dir="$HOME/summary-work"
started_at=$SECONDS
sbx_environment=''' + environment + '''
sbx_sandbox_target=cloud-project
sbx_child_shell=true
finishing=false
utf8=false
green= amber= red= muted= reset=
warning_count=0
changed_count=0 unchanged_count=1 verified_count=0
github_auth_status=verified openai_auth_status=verified webtop_status=
declare -a issue_keys=() issue_titles=() issue_details=() issue_actions=()
stop_spinner() { :; }
drain_output() { :; }
cleanup_installer() { :; }
'''
            result = subprocess.run([BASH, '--noprofile', '--norc'],
                                    input=setup + REPORT + '\n' + FINISH + '\ntrap finish_installer EXIT\ntrue\n',
                                    text=True, encoding='utf-8', capture_output=True,
                                    env=self.environment, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('SETUP COMPLETE', result.stdout)
            if environment == 'cloud':
                self.assertIn('sbx --cloud mcp ls cloud-project', result.stdout)
                self.assertNotIn('sbx daemon restart', result.stdout)
                self.assertNotIn('sbx kit add', result.stdout)
                self.assertNotIn('127.0.0.1', result.stdout)
            else:
                self.assertIn('sbx daemon restart', result.stdout)
                self.assertIn('sbx mcp load context7 --sandbox cloud-project', result.stdout)


if __name__ == '__main__':
    unittest.main()
