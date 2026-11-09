"""Check embedded authentication logic without running the installer or network calls."""
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib
import types
import unittest
from unittest.mock import patch


SOURCE = (Path(__file__).resolve().parents[1] / 'sbx_local_opencode_deploy.sh').read_text(encoding='utf-8')


def payload(name):
    return re.search(r"<<'" + name + r"'\n(.*?)\n" + name + r'\n', SOURCE, re.S)[1]


class AuthenticationSelection(unittest.TestCase):
    def opencode(self, entries, expiry=100):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / 'opencode'
            directory.mkdir()
            (directory / 'auth.json').write_text(json.dumps({'openai': {
                'type': 'oauth', 'access': 'masked-access',
                'refresh': 'masked-refresh', 'expires': expiry}}))
            changed = Path(root) / 'changed'
            mutations = []

            def run(args, **kwargs):
                if args[0] == 'flock':
                    return subprocess.CompletedProcess(args, 0)
                operation = args[5]
                if operation == 'export':
                    return subprocess.CompletedProcess(args, 0, json.dumps(entries))
                mutations.append((operation, json.loads(kwargs['input'])))
                return subprocess.CompletedProcess(args, 0, '')

            argv = ['fixture', 'opencode', 'masked-access', 'masked-refresh',
                    str(changed), '30', '5']
            with patch.dict(os.environ, XDG_DATA_HOME=root), patch.object(sys, 'argv', argv), \
                    patch.dict(sys.modules, fcntl=types.ModuleType('fcntl')), \
                    patch.object(os, 'O_NOFOLLOW', 0, create=True), \
                    patch('subprocess.run', side_effect=run):
                try:
                    exec(compile(payload('SBX_PROXY_OAUTH'), 'OpenCode payload', 'exec'), {})
                except SystemExit as result:
                    self.assertEqual(result.code, 0)
            self.assertEqual(changed.exists(), bool(mutations))
            return mutations

    @staticmethod
    def managed(active=True):
        return {'id': 'sbx-openai', 'integrationID': 'openai', 'active': active,
                'value': {'type': 'oauth', 'methodID': 'chatgpt-browser',
                          'access': 'masked-access', 'refresh': 'masked-refresh',
                          'expires': 100}}

    def test_opencode_fresh_and_retry(self):
        mutations = self.opencode([])
        self.assertEqual(mutations[0][0], 'import')
        self.assertTrue(mutations[0][1][0]['active'])
        self.assertEqual(self.opencode(mutations[0][1]), [])

    def test_opencode_local_selection(self):
        local = {'id': 'local', 'integrationID': 'openai', 'active': True}
        for entries in ([local], [self.managed(False), local]):
            self.assertEqual(self.opencode(entries, expiry=200), [])

    def test_opencode_inactive_selection(self):
        self.assertEqual(self.opencode([self.managed(False)]), [])

    def test_opencode_selected_host_refresh_and_retry(self):
        mutations = self.opencode([self.managed()], expiry=200)
        self.assertTrue(mutations[0][1][0]['active'])
        self.assertEqual(self.opencode(mutations[0][1], expiry=200), [])

    def codex(self, provider=None, local_auth=False, host=True):
        # Use real TOML parsing. Stub TOMLKit tables and serialization so these
        # routing checks need no third-party packages. This does not test formatting.
        written = []
        tomlkit = types.SimpleNamespace(
            parse=tomllib.loads, table=dict,
            items=types.SimpleNamespace(Table=dict, InlineTable=dict),
            exceptions=types.SimpleNamespace(ParseError=tomllib.TOMLDecodeError),
            dumps=lambda value: written.append(copy.deepcopy(value)) or 'fixture output')
        with tempfile.TemporaryDirectory() as root:
            source, staged = Path(root) / 'config.toml', Path(root) / 'staged'
            original = 'model = "main"\n'
            if provider is not None:
                original += f'model_provider = "{provider}"\n'
            original += ('[agents]\nenabled = true\ndefault_subagent_model = "sub"\n'
                         '[mcp_servers.mcp-gateway]\nurl = "gateway"\nenabled = true\n')
            source.write_text(original)
            if local_auth:
                (Path(root) / 'auth.json').write_text('private fixture; do not read')
            argv = ['fixture', str(source), str(staged), 'main', 'sub',
                    str(host).lower(), 'sbx-chatgpt', 'base', 'masked-access', 'gateway']
            with patch.dict(sys.modules, tomlkit=tomlkit), patch.object(sys, 'argv', argv):
                exec(compile(payload('SBX_CODEX_MODEL'), 'Codex payload', 'exec'), {})
                self.assertEqual(source.read_text(), original)
                first = copy.deepcopy(written)
                # Feed the generated configuration back to check an unchanged rerun.
                if written:
                    tomlkit.parse = lambda text: copy.deepcopy(first[0])
                    written.clear()
                    staged.unlink()
                    exec(compile(payload('SBX_CODEX_MODEL'), 'Codex payload', 'exec'), {})
                    self.assertEqual(written, [])
                    self.assertFalse(staged.exists())
            return first[0] if first else tomllib.loads(original)

    def test_codex_fresh(self):
        self.assertEqual(self.codex()['model_provider'], 'sbx-chatgpt')

    def test_codex_explicit_choices(self):
        for provider in ('openai', 'sbx-chatgpt', 'custom'):
            with self.subTest(provider=provider):
                self.assertEqual(self.codex(provider)['model_provider'], provider)

    def test_codex_implicit_local_login(self):
        self.assertNotIn('model_provider', self.codex(local_auth=True))

    def test_codex_without_host(self):
        self.assertNotIn('model_provider', self.codex(host=False))


if __name__ == '__main__':
    unittest.main()
