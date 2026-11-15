"""Check profiles and generated code. Do not deploy or contact services."""
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'sbx_local_opencode_deploy.sh').read_text(encoding='utf-8')
BASH = str(Path('C:/Program Files/Git/bin/bash.exe')) if os.name == 'nt' else shutil.which('bash')
PROFILES = '    sbx_local_profile() {' + SOURCE.split('    sbx_local_profile() {', 1)[1].split('# Prepare terminal output', 1)[0]
PRESENTATION = 'report_line() {' + SOURCE.split('report_line() {', 1)[1].split('# FIGlet Slant', 1)[0]
CLOUD_HOST = 'sbx-001m7e4z4e3xjatm8nqcnwywz2m'


class EnvironmentProfiles(unittest.TestCase):
    def setUp(self):
        if not BASH or not Path(BASH).is_file():
            self.skipTest('Bash is required')
        self.temp = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.environment = dict(os.environ, HOME=self.home.as_posix(), USERPROFILE=str(self.home), HOSTNAME='opencode-test',
                                FIXTURE_PYTHON=sys.executable)
        for name in ('SBX_ENV', 'SBX_NETWORK_SCOPE', 'SBX_SANDBOX_NAME', 'SBX_MCP_GATEWAY_URL',
                     'MCP_GATEWAY_URL', 'XDG_STATE_HOME', 'CODEX_HOME', 'BASH_ENV',
                     'SANDBOX_ID', 'SANDBOX_NAME', 'SANDBOX_VM_ID', 'SBX_AGENT',
                     'SBX_CRED_OPENAI_MODE', 'SBX_CRED_GITHUB_MODE'):
            self.environment.pop(name, None)

    def select(self, answer=''):
        self.environment['FIXTURE_ANSWER'] = answer
        setup = 'set -euo pipefail\nexec 3>&2\ngreen= amber= muted= reset= log_file=\nutf8=false\npython3() { "$FIXTURE_PYTHON" "$@"; }\n'
        return subprocess.run([BASH, '--noprofile', '--norc'], input=setup + PROFILES + PRESENTATION + '''
exec 6<<< "$FIXTURE_ANSWER"
sbx_select_environment 6
printf '%s\\n' "$sbx_environment" "$sbx_host_command" "$mcp_gateway_url" "$sbx_import_oauth_bridge" "$sbx_webtop_supported" "$sbx_sandbox_target"
''', text=True, encoding='utf-8', capture_output=True, env=self.environment, timeout=10)

    def save_profile(self, environment='cloud', host=CLOUD_HOST, gateway='https://gateway.example/mcp'):
        target = self.home / '.local/state/sbx-deploy/environment'
        target.parent.mkdir(parents=True)
        content = f'sbx-profile-v1\n{environment}\n{host}\n{gateway}\n'.encode()
        target.write_bytes(content)
        shell_path = target.as_posix()
        if os.name == 'nt':
            shell_path = '/' + shell_path[0].lower() + shell_path[2:]
        key = hashlib.sha256(shell_path.encode()).hexdigest()
        baseline = target.parent / 'managed' / key
        baseline.parent.mkdir()
        baseline.write_bytes(content)
        return target, baseline

    def test_unknown_and_conflicting_markers_stop_without_writes(self):
        for hostname in ('opencode-test', CLOUD_HOST):
            self.environment['HOSTNAME'] = hostname
            self.environment['SANDBOX_ID'] = 'partial-local-marker'
            result = self.select()
            self.assertEqual(result.returncode, 130, result.stderr)
            self.assertIn('unknown or conflict', result.stderr)
            self.assertEqual(list(self.home.iterdir()), [])

    def test_reported_local_markers_offer_local_default_without_writes(self):
        self.environment.update(SANDBOX_ID='local-id', SANDBOX_NAME='local-name',
                                SANDBOX_VM_ID='local-vm', SBX_AGENT='opencode',
                                SBX_CRED_OPENAI_MODE='oauth', SBX_CRED_GITHUB_MODE='apiKey')
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], 'local')
        self.assertIn('Default: local (detected)', result.stderr)
        self.assertIn('Environment [local]', result.stderr)
        self.assertEqual(list(self.home.iterdir()), [])
        self.environment['HOSTNAME'] = CLOUD_HOST
        self.assertEqual(self.select().returncode, 130)

    def test_reported_cloud_markers_offer_cloud_default_without_writes(self):
        self.environment['HOSTNAME'] = CLOUD_HOST
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], 'cloud')
        self.assertIn('Default: cloud (detected)', result.stderr)
        self.assertIn('Environment [cloud]', result.stderr)
        self.assertEqual(list(self.home.iterdir()), [])
        self.environment['SBX_CRED_OPENAI_MODE'] = 'none'
        self.assertEqual(self.select().returncode, 130)

    def test_explicit_override_wins_over_observed_markers(self):
        self.environment.update(HOSTNAME=CLOUD_HOST, SBX_ENV='local')
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], 'local')
        self.assertIn('Default: local (SBX_ENV)', result.stderr)
        self.assertIn('Environment [local]', result.stderr)

    def test_user_can_change_the_detected_default(self):
        self.environment['HOSTNAME'] = CLOUD_HOST
        result = self.select(answer='local')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Default: cloud (detected)', result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], 'local')

    def test_logo_precedes_environment_card_with_narrow_terminal_fallback(self):
        intro = SOURCE.split('# Prepare terminal output before any environment questions.\n', 1)[1].split(
            '    sbx_select_environment\n    command -v flock', 1)[0]
        self.environment.update(HOSTNAME=CLOUD_HOST, COLUMNS='40', TERM='dumb', LC_ALL='C')
        body = 'set -euo pipefail\n' + PROFILES + intro + '''
sbx_discover_gateway() { :; }
exec 6<<< ''
sbx_select_environment 6
'''
        result = subprocess.run([BASH, '--noprofile', '--norc'], input=body, text=True,
                                encoding='utf-8', capture_output=True, env=self.environment, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(result.stdout.index('P R E S E N T S'), result.stdout.index('SANDBOX ENVIRONMENT'))
        self.assertIn('Environment [cloud]', result.stdout)
        card = result.stdout.split('SANDBOX ENVIRONMENT', 1)[1]
        self.assertNotIn('+---', card)
        self.assertNotIn('\x1b[', result.stdout)

    def test_local_defaults_and_explicit_cloud_settings(self):
        self.environment['SBX_ENV'] = 'local'
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['local', 'sbx',
                         'http://mcp-gateway.docker.internal/mcp', 'true', 'true', 'opencode-test'])
        self.environment.update(SBX_ENV='cloud', MCP_GATEWAY_URL='https://gateway.example/mcp')
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['cloud', 'sbx --cloud',
                         'https://gateway.example/mcp', 'false', 'false', '$sandboxName'])

    def test_first_selection_reads_caller_input_and_preserves_payload(self):
        definitions = 'sbx_read_environment() {' + SOURCE.split('sbx_read_environment() {', 1)[1].split(
            '    sbx_select_environment() {', 1)[0]
        pending = self.home / 'pending-payload'
        pending.write_text('DO-NOT-READ-AS-AN-ANSWER\n')
        body = 'set -euo pipefail\n' + definitions + '''
exec 3>&2
exec 6<&0
exec 0< "$HOME/pending-payload"
sbx_read_environment 6 cloud
printf 'selected=%s\\n' "$sbx_environment"
IFS= read -r pending
printf 'payload=%s\\n' "$pending"
'''
        for answer, expected in (('\n', 'cloud'), ('wrong\nlocal\n', 'local')):
            result = subprocess.run([BASH, '--noprofile', '--norc', '-c', body], input=answer.encode(),
                                    capture_output=True, env=self.environment, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('selected=' + expected, result.stdout.decode())
            self.assertIn('payload=DO-NOT-READ-AS-AN-ANSWER', result.stdout.decode())
        result = subprocess.run([BASH, '--noprofile', '--norc', '-c', body], input='',
                                text=True, capture_output=True, env=self.environment, timeout=10)
        self.assertEqual(result.returncode, 130, result.stderr)
        self.assertNotIn('selected=', result.stdout)

    def test_cloud_id_and_hostname_must_match_for_first_auto_selection(self):
        self.environment.update(HOSTNAME=CLOUD_HOST, SBX_SANDBOX_NAME='sbx_' + CLOUD_HOST[4:],
                                MCP_GATEWAY_URL='http://gateway.internal/mcp')
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], 'cloud')
        self.assertEqual(result.stdout.splitlines()[-1], 'sbx_' + CLOUD_HOST[4:])
        self.environment['SBX_SANDBOX_NAME'] = 'sbx_wrong'
        self.assertEqual(self.select().returncode, 130)

    def test_cloud_needs_endpoint_and_rejects_credentials_without_printing_them(self):
        self.environment['SBX_ENV'] = 'cloud'
        for url in ('https://user:PRIVATE@gateway.example/mcp',
                    'https://gateway.example/mcp?token=PRIVATE', 'https://gateway.example/mcp#PRIVATE',
                    '$(touch unsafe)', 'https://gateway.example/mcp\nPRIVATE'):
            self.environment['SBX_MCP_GATEWAY_URL'] = url
            result = self.select()
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertNotIn('PRIVATE', result.stdout + result.stderr)
            self.assertEqual(list(self.home.iterdir()), [])

    def test_missing_cloud_gateway_allows_tools_without_guessing_endpoint(self):
        self.environment['SBX_ENV'] = 'cloud'
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[2], '')
        self.assertEqual(list(self.home.iterdir()), [])

    def test_discovers_effective_opencode_gateway_without_copying_headers(self):
        self.environment.update(SBX_ENV='cloud', XDG_CONFIG_HOME=self.home.as_posix())
        directory = self.home / 'opencode'
        directory.mkdir()
        (directory / 'opencode.json').write_text('{"mcp":{"mcp-gateway":{"url":"https://ignored.example/mcp"}}}')
        source = directory / 'opencode.jsonc'
        content = '''{ // Keep comments and credentials private.
"mcp": {"mcp-gateway": {"type": "remote", "url": "https://gateway.example/mcp",
"headers": {"Authorization": "Bearer PRIVATE-HEADER"},}},
}'''
        source.write_text(content)
        before = (source.read_bytes(), source.stat().st_mtime_ns)
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[2], 'https://gateway.example/mcp')
        self.assertNotIn('PRIVATE', result.stdout + result.stderr)
        self.assertEqual(before, (source.read_bytes(), source.stat().st_mtime_ns))
        self.environment['SBX_MCP_GATEWAY_URL'] = 'https://override.example/mcp'
        self.assertEqual(self.select().stdout.splitlines()[2], 'https://override.example/mcp')

    def test_discovers_codex_gateway_and_rejects_unsafe_config_without_diagnostics(self):
        self.environment.update(SBX_ENV='cloud', CODEX_HOME=self.home.as_posix())
        source = self.home / 'config.toml'
        source.write_text('[mcp_servers.mcp-gateway]\nurl="https://gateway.example/mcp"\n')
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[2], 'https://gateway.example/mcp')
        for text in ('[mcp_servers.mcp-gateway]\nurl="https://user:PRIVATE@gateway.example/mcp"\n',
                     'PRIVATE malformed config'):
            source.write_text(text)
            result = self.select()
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertNotIn('PRIVATE', result.stdout + result.stderr)
            self.assertNotIn('Traceback', result.stderr)

    def test_saved_selection_and_endpoint_are_read_only_and_bound_to_host(self):
        self.environment['HOSTNAME'] = CLOUD_HOST
        target, baseline = self.save_profile()
        before = [(p.read_bytes(), p.stat().st_mtime_ns) for p in (target, baseline)]
        for _ in range(2):
            result = self.select()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines()[:3], ['cloud', 'sbx --cloud', 'https://gateway.example/mcp'])
        self.assertEqual(before, [(p.read_bytes(), p.stat().st_mtime_ns) for p in (target, baseline)])
        self.environment['HOSTNAME'] = 'moved-sandbox'
        self.assertEqual(self.select().returncode, 130)

    def test_modified_or_unowned_selection_stops_and_preserves_files(self):
        target, baseline = self.save_profile()
        target.write_text('user data\n')
        result = self.select()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('ownership is unknown', result.stderr)
        self.assertEqual(target.read_text(), 'user data\n')
        baseline.unlink()
        self.assertEqual(self.select().returncode, 1)

    def test_environment_override_and_network_scope_conflict(self):
        self.environment.update(SBX_ENV='cloud', SBX_NETWORK_SCOPE='local',
                                MCP_GATEWAY_URL='https://gateway.example/mcp')
        result = self.select()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn('conflicts', result.stderr)

    def test_interrupted_profile_save_requires_matching_explicit_inputs(self):
        self.environment.update(HOSTNAME=CLOUD_HOST, SBX_ENV='cloud',
                                SBX_MCP_GATEWAY_URL='https://gateway.example/mcp')
        target, baseline = self.save_profile()
        baseline.unlink()
        result = self.select()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_text(), f'sbx-profile-v1\ncloud\n{CLOUD_HOST}\nhttps://gateway.example/mcp\n')
        self.environment['SBX_MCP_GATEWAY_URL'] = 'https://other.example/mcp'
        self.assertEqual(self.select().returncode, 1)


class InstallerSyntax(unittest.TestCase):
    def test_wrapper_and_literal_payload_have_valid_bash_syntax(self):
        if not BASH or not Path(BASH).is_file():
            self.skipTest('Bash is required')
        body = SOURCE.split("\nsbx_save_and_run <<'SBX_DEPLOY_PAYLOAD'\n", 1)[1].rsplit('\nSBX_DEPLOY_PAYLOAD\n', 1)[0]
        for name, text in (('wrapper', SOURCE), ('literal payload', body)):
            result = subprocess.run([BASH, '-n'], input=text, text=True, encoding='utf-8', capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, name + ': ' + result.stderr)

    def test_complete_python_payloads_compile(self):
        for name in ('SBX_DISCOVER_GATEWAY', 'SBX_PYTHON_VALUES', 'SBX_CREDENTIAL_CHECK', 'SBX_MCP_CHECK', 'SBX_VSCODE_STATUS',
                     'SBX_PROXY_OAUTH', 'SBX_CONFIG_OWNERSHIP', 'SBX_MIGRATE_SHELL', 'SBX_OPENCODE_MODEL',
                     'SBX_CODEX_MODEL', 'SBX_WEBTOP_INSPECT'):
            body = re.search(r"<<'" + name + r"'\n(.*?)\n" + name + r'\n', SOURCE, re.S)[1]
            compile(body, name, 'exec')

    def test_generated_authentication_helpers_compile(self):
        if not BASH or not Path(BASH).is_file():
            self.skipTest('Bash is required')
        generator = 'openai_auth_contents() {' + SOURCE.split('openai_auth_contents() {', 1)[1].split(
            '\n# Use a new managed path', 1)[0]
        for mode in ('', 'codex', 'vscode'):
            # Generate source only. Do not run a login helper or installer.
            result = subprocess.run([BASH, '--noprofile', '--norc'],
                                    input='set -euo pipefail\npython_settings() { :; }\n' + generator +
                                    '\nopenai_auth_contents ' + mode + '\n',
                                    text=True, encoding='utf-8', capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            compile(result.stdout, mode or 'opencode', 'exec')


if __name__ == '__main__':
    unittest.main()
