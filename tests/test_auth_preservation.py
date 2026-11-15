"""Check embedded authentication logic without running the installer or network calls."""
import copy
import contextlib
import io
import hashlib
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
    def opencode(self, entries, expiry=100, environment='local', bridge=True,
                 status=0, import_status=0, receipt=None, restart_status=0, import_noop=False):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / 'opencode'
            directory.mkdir()
            bridge_path = directory / 'auth.json'
            if bridge:
                bridge_path.write_text(json.dumps({'openai': {
                    'type': 'oauth', 'access': 'masked-access',
                    'refresh': 'masked-refresh', 'expires': expiry}}))
            before = bridge_path.read_bytes() if bridge_path.exists() else None
            changed = Path(root) / 'changed'
            mutations = []
            restarts = []
            stored = copy.deepcopy(entries)
            service_receipt = Path(root) / 'service.sha256'
            if receipt == 'verified':
                value = self.managed()['value']
                value['expires'] = 4102444800000
                service_receipt.write_text('sbx-opencode-oauth-service-v1\n' +
                                          hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest() + '\n')
            elif receipt is not None:
                service_receipt.write_text(receipt)
            receipt_before = ((service_receipt.read_bytes(), service_receipt.stat().st_mtime_ns)
                              if service_receipt.exists() else None)

            def run(args, **kwargs):
                if args[0] == 'flock':
                    return subprocess.CompletedProcess(args, 0)
                if args[4:6] == ['service', 'restart']:
                    restarts.append(True)
                    return subprocess.CompletedProcess(args, restart_status)
                operation = args[5]
                if operation == 'export':
                    return subprocess.CompletedProcess(args, 0, json.dumps(stored))
                if import_status:
                    return subprocess.CompletedProcess(args, import_status, '', 'private diagnostic')
                mutations.append((operation, json.loads(kwargs['input'])))
                if not import_noop:
                    # Match OpenCode: import adds missing IDs and skips existing IDs.
                    stored.extend(item for item in mutations[-1][1]
                                  if not any(row['id'] == item['id'] for row in stored))
                return subprocess.CompletedProcess(args, 0, '')

            argv = ['fixture', 'opencode', 'masked-access', 'masked-refresh',
                    str(changed), '30', '5', environment, str(service_receipt)]
            diagnostics = io.StringIO()
            with patch.dict(os.environ, XDG_DATA_HOME=root), patch.object(sys, 'argv', argv), \
                    patch.dict(sys.modules, fcntl=types.ModuleType('fcntl')), \
                    patch.object(os, 'O_NOFOLLOW', 0, create=True), \
                    patch('subprocess.run', side_effect=run), contextlib.redirect_stderr(diagnostics), \
                    contextlib.redirect_stdout(io.StringIO()):
                try:
                    exec(compile(payload('SBX_PROXY_OAUTH'), 'OpenCode payload', 'exec'), {})
                except SystemExit as result:
                    if status == 0:
                        self.assertEqual(result.code, 0)
                    elif status > 1:
                        self.assertEqual(result.code, status)
                    else:
                        self.assertNotEqual(result.code, 0)
                else:
                    self.assertEqual(status, 0)
            self.assertEqual(changed.exists(), bool(mutations or (restarts and not restart_status)))
            self.restarts = len(restarts)
            self.receipt_written = service_receipt.exists()
            if not restarts or restart_status:
                self.assertEqual((service_receipt.read_bytes(), service_receipt.stat().st_mtime_ns)
                                 if service_receipt.exists() else None, receipt_before)
            self.assertNotIn('private diagnostic', diagnostics.getvalue())
            self.assertEqual(bridge_path.read_bytes() if bridge_path.exists() else None, before)
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

    def test_cloud_opencode_without_bridge_and_unchanged_retry(self):
        mutations = self.opencode([], environment='cloud', bridge=False)
        self.assertEqual(len(mutations), 1)
        record = mutations[0][1][0]
        self.assertEqual(record['value']['expires'], 4102444800000)
        self.assertEqual(record['value']['access'], 'masked-access')
        self.assertEqual(record['value']['refresh'], 'masked-refresh')
        self.assertEqual(self.restarts, 1)
        self.assertTrue(self.receipt_written)
        self.assertEqual(self.opencode([record], environment='cloud', bridge=False, receipt='verified'), [])
        self.assertEqual(self.restarts, 0)

    def test_cloud_opencode_preserves_saved_selection(self):
        local = {'id': 'local', 'integrationID': 'openai', 'active': True}
        for entries in ([local], [self.managed(False)], [self.managed(False), local]):
            self.assertEqual(self.opencode(entries, environment='cloud', bridge=False), [])

    def test_cloud_opencode_rejects_managed_id_with_private_tokens(self):
        record = self.managed()
        record['value']['access'] = 'private-local-token'
        self.assertEqual(self.opencode([record], environment='cloud', bridge=False, status=1), [])

    def test_local_opencode_still_requires_bridge(self):
        self.assertEqual(self.opencode([], bridge=False, status=1), [])

    def test_cloud_opencode_failed_import_and_retry(self):
        self.assertEqual(self.opencode([], environment='cloud', bridge=False,
                                       status=17, import_status=17), [])
        self.assertEqual(len(self.opencode([], environment='cloud', bridge=False)), 1)

    def test_cloud_existing_import_gets_service_restart_without_reimport(self):
        record = self.managed()
        record['value']['expires'] = 4102444800000
        self.assertEqual(self.opencode([record], environment='cloud', bridge=False), [])
        self.assertEqual(self.restarts, 1)
        self.assertTrue(self.receipt_written)

    def test_cloud_restart_failure_preserves_status_and_retries(self):
        imported = self.opencode([], environment='cloud', bridge=False, status=19, restart_status=19)
        self.assertFalse(self.receipt_written)
        self.assertEqual(self.opencode(imported[0][1], environment='cloud', bridge=False), [])
        self.assertEqual(self.restarts, 1)
        self.assertTrue(self.receipt_written)

    def test_cloud_unknown_receipt_stops_before_import_or_restart(self):
        self.assertEqual(self.opencode([], environment='cloud', bridge=False,
                                       receipt='user data', status=1), [])
        self.assertEqual(self.restarts, 0)

    def test_cloud_skipped_import_is_not_recorded_as_complete(self):
        self.opencode([], environment='cloud', bridge=False, import_noop=True, status=1)
        self.assertEqual(self.restarts, 0)
        self.assertFalse(self.receipt_written)

    def test_cloud_existing_different_value_stops_before_import(self):
        self.assertEqual(self.opencode([self.managed()], environment='cloud', bridge=False, status=1), [])
        self.assertEqual(self.restarts, 0)

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
            ownership_module = types.ModuleType('config_ownership')
            exec(compile(payload('SBX_CONFIG_OWNERSHIP'), 'Ownership payload', 'exec'), ownership_module.__dict__)
            state = Path(root) / 'ownership'
            state.mkdir()
            baseline = state / (ownership_module.digest(str(source).encode()) + '.json')
            baseline.write_text(json.dumps({'version': 1, 'settings': {
                'model': 'main', 'agents.enabled': True, 'agents.default_subagent_model': 'sub',
                'mcp_servers.mcp-gateway.url': 'gateway', 'mcp_servers.mcp-gateway.enabled': True}}))
            class Document(dict):
                def unwrap(self):
                    return dict(self)
            tomlkit.parse = lambda text: Document(tomllib.loads(text))
            if local_auth:
                (Path(root) / 'auth.json').write_text('private fixture; do not read')
            argv = ['fixture', str(source), str(staged), 'main', 'sub',
                    str(host).lower(), 'sbx-chatgpt', 'base', 'masked-access', 'gateway', str(state)]
            with patch.dict(sys.modules, tomlkit=tomlkit, config_ownership=ownership_module), \
                    patch.object(os, 'getuid', getattr(os, 'getuid', lambda: 0), create=True), patch.object(sys, 'argv', argv):
                exec(compile(payload('SBX_CODEX_MODEL'), 'Codex payload', 'exec'), {})
                self.assertEqual(source.read_text(), original)
                first = copy.deepcopy(written)
                # Feed the generated configuration back to check an unchanged rerun.
                if written:
                    tomlkit.parse = lambda text: Document(copy.deepcopy(first[0]))
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
