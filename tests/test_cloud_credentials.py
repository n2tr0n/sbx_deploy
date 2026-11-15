"""Check cloud credential probes with local fixtures. Make no network requests."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import types
import unittest
from unittest.mock import patch

from test_auth_preservation import payload


class CloudCredentials(unittest.TestCase):
    def check(self, *, api_key=False, custom=False, github_failure=False):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = ('model_provider = "custom"\n' if custom else
                      'model_provider = "sandboxd"\n[model_providers.sandboxd]\n'
                      'base_url = "https://chatgpt.com/backend-api/codex"\n'
                      'experimental_bearer_token = "masked-access"\n')
            if api_key:
                config = 'model = "example"\n'
            source = home / 'config.toml'
            source.write_text(config)
            before = (source.read_bytes(), source.stat().st_mtime_ns)
            calls = []

            def run(args, **kwargs):
                command = args[3:]
                calls.append((command, kwargs.get('input')))
                if '--version' in command:
                    return subprocess.CompletedProcess(args, 0, 'codex 1.2.3', '')
                if command[0] == 'curl':
                    return subprocess.CompletedProcess(args, 0, '200', '')
                if command[0] == 'gh':
                    return subprocess.CompletedProcess(args, 1, '', 'HTTP 401 PRIVATE-DIAGNOSTIC')
                if command[1:3] == ['auth', 'export']:
                    records = [] if api_key else [{'integrationID': 'openai', 'active': True,
                                                   'value': {'type': 'oauth', 'access': 'masked-access'}}]
                    return subprocess.CompletedProcess(args, 0, json.dumps(records), '')
                self.fail('Unexpected probe: ' + str(command))

            variables = dict(oauth_access='masked-access', oauth_provider='sbx-chatgpt',
                             oauth_base_url='https://chatgpt.com/backend-api/codex',
                             api_base_url='https://api.openai.com/v1', opencode_binary='opencode',
                             credential_seconds=30, version_seconds=15, kill_seconds=5,
                             sbx_environment='cloud', sbx_host_doc='HOST_SETUP_CLOUD.md')
            environment = dict(CODEX_HOME=directory, OPENAI_API_KEY='PRIVATE-API-KEY' if api_key else '',
                               GH_TOKEN='', GITHUB_TOKEN='', GH_CONFIG_DIR=str(home / 'gh'))
            output = io.StringIO()
            argv = ['check_credentials'] if github_failure else ['check_credentials', '--openai']
            with patch.dict(os.environ, environment), patch.object(Path, 'home', return_value=home), \
                    patch.object(sys, 'argv', argv), patch('subprocess.run', side_effect=run), \
                    patch.dict(sys.modules, tomlkit=types.SimpleNamespace(parse=tomllib.loads)), \
                    contextlib.redirect_stdout(output):
                with self.assertRaises(SystemExit) as result:
                    exec(compile(payload('SBX_CREDENTIAL_CHECK'), 'credential helper', 'exec'), variables)
            self.assertEqual(before, (source.read_bytes(), source.stat().st_mtime_ns))
            self.assertNotIn('PRIVATE-', output.getvalue())
            return result.exception.code, output.getvalue(), calls

    def test_cloud_startup_oauth_provider_is_preserved_and_checked(self):
        status, output, calls = self.check()
        self.assertEqual(status, 0, output)
        self.assertIn('2/2 passed', output)
        self.assertEqual(sum(command[0] == 'curl' for command, _ in calls), 2)
        self.assertFalse(any(command[0] == 'gh' for command, _ in calls))

    def test_api_key_environment_checks_both_harnesses_without_exposing_key(self):
        status, output, calls = self.check(api_key=True)
        self.assertEqual(status, 0, output)
        requests = [command for command, _ in calls if command[0] == 'curl']
        self.assertEqual(len(requests), 2)
        self.assertTrue(all(command[-1] == 'https://api.openai.com/v1/models' for command in requests))

    def test_custom_provider_requires_harness_check(self):
        status, output, _ = self.check(custom=True)
        self.assertEqual(status, 1)
        self.assertIn('custom provider', output)

    def test_cloud_github_failure_does_not_suggest_local_daemon(self):
        status, output, _ = self.check(github_failure=True)
        self.assertEqual(status, 1)
        self.assertIn('sbx --cloud secret ls', output)
        self.assertNotIn('sbx daemon restart', output)


if __name__ == '__main__':
    unittest.main()
