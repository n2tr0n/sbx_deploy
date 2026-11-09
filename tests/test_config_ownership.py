"""Run embedded config payloads. Do not run the installer or network checks."""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

from test_auth_preservation import payload

try:
    import tomlkit
except ImportError:
    tomlkit = None


class ConfigOwnership(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.module = types.ModuleType('config_ownership')
        exec(compile(payload('SBX_CONFIG_OWNERSHIP'), 'Ownership payload', 'exec'), self.module.__dict__)
        self.uid = patch.object(os, 'getuid', lambda: 0, create=True) if not hasattr(os, 'getuid') else None
        if self.uid:
            self.uid.start()
            self.addCleanup(self.uid.stop)
        self.modules = patch.dict(sys.modules, config_ownership=self.module)
        self.modules.start()
        self.addCleanup(self.modules.stop)

    def run_config(self, harness, main='main', sub='sub', gateway='gateway', publish=True, commit=True):
        source = self.root / ('config.jsonc' if harness == 'opencode' else 'config.toml')
        staged = self.root / 'staged'
        staged.unlink(missing_ok=True)
        state = self.root / 'state'
        args = [str(source), str(staged), main, sub]
        args += [gateway, str(state)] if harness == 'opencode' else [
            'false', 'sbx-chatgpt', 'base', 'masked-access', gateway, str(state)]
        with patch.object(sys, 'argv', ['fixture'] + args):
            exec(compile(payload('SBX_' + harness.upper() + '_MODEL'), harness, 'exec'), {})
        changed = staged.exists()
        if publish and changed:
            source.write_bytes(staged.read_bytes())
        if commit:
            self.module.Ownership(source, state).commit()
        return source, changed

    def read(self, harness, source):
        if harness == 'codex':
            return tomlkit.parse(source.read_text()).unwrap()
        # Fresh payload output is JSON. Comment fixtures use separate checks.
        return json.loads(source.read_text())

    def write(self, harness, source, data):
        source.write_text(json.dumps(data) if harness == 'opencode' else tomlkit.dumps(data))

    def check_lifecycle(self, harness):
        source, changed = self.run_config(harness)
        self.assertTrue(changed)
        state_file = next((self.root / 'state').glob('*.json'))
        before = (source.read_bytes(), source.stat().st_mtime_ns,
                  state_file.read_bytes(), state_file.stat().st_mtime_ns)
        self.assertFalse(self.run_config(harness)[1])
        self.assertEqual(before, (source.read_bytes(), source.stat().st_mtime_ns,
                                 state_file.read_bytes(), state_file.stat().st_mtime_ns))
        data = self.read(harness, source)
        data['model'] = 'custom'
        data['unrelated'] = 'keep'
        agents = data['agents']
        if harness == 'opencode':
            agents['build']['model'] = 'custom-build'
            del agents['explore']['model']
            mcp = data['mcp']['mcp-gateway']
        else:
            del agents['default_subagent_model']
            agents['enabled'] = False
            mcp = data['mcp_servers']['mcp-gateway']
        mcp['url'] = 'custom-url'
        mcp['enabled'] = False
        self.write(harness, source, data)
        self.run_config(harness, main='new-main', sub='new-sub', gateway='new-gateway')
        result = self.read(harness, source)
        self.assertEqual(result['model'], 'custom')
        self.assertEqual(result['unrelated'], 'keep')
        if harness == 'opencode':
            self.assertEqual(result['agents']['build']['model'], 'custom-build')
            self.assertEqual(result['agents']['plan']['model'], 'openai/new-main')
            self.assertEqual(result['agents']['general']['model'], 'openai/new-sub')
            self.assertNotIn('model', result['agents']['explore'])
            self.assertEqual(result['mcp']['mcp-gateway'], mcp)
        else:
            self.assertNotIn('default_subagent_model', result['agents'])
            self.assertFalse(result['agents']['enabled'])
            self.assertEqual(result['mcp_servers']['mcp-gateway'], mcp)
        self.assertFalse(self.run_config(harness, main='new-main', sub='new-sub', gateway='new-gateway')[1])

    def test_opencode_lifecycle(self):
        self.check_lifecycle('opencode')

    @unittest.skipIf(tomlkit is None, 'TOMLKit is required for real Codex config checks')
    def test_codex_lifecycle(self):
        self.check_lifecycle('codex')

    def check_interruption(self, harness):
        # Interrupt before config publication, then retry.
        self.run_config(harness, publish=False, commit=False)
        source, _ = self.run_config(harness)
        # Interrupt after config publication, then retry with newer defaults.
        self.run_config(harness, main='second', commit=False)
        self.run_config(harness, main='third')
        model = 'openai/third' if harness == 'opencode' else 'third'
        self.assertEqual(self.read(harness, source)['model'], model)
        self.assertEqual(list((self.root / 'state').glob('*.pending')), [])

    def test_opencode_interruption(self):
        self.check_interruption('opencode')

    @unittest.skipIf(tomlkit is None, 'TOMLKit is required for real Codex config checks')
    def test_codex_interruption(self):
        self.check_interruption('codex')

    def test_unknown_values_even_matching_defaults(self):
        for harness in ('opencode', 'codex'):
            if harness == 'codex' and tomlkit is None:
                continue
            source = self.root / ('config.jsonc' if harness == 'opencode' else 'config.toml')
            source.write_text('{"model":"openai/main"}' if harness == 'opencode' else 'model = "main"\n')
            before = source.read_bytes()
            with self.assertRaisesRegex(SystemExit, 'Unknown deployment ownership'):
                self.run_config(harness)
            self.assertEqual(source.read_bytes(), before)
            self.assertFalse((self.root / 'state').exists())

    def test_comments_and_duplicate_keys(self):
        source = self.root / 'config.jsonc'
        source.write_text('{ // keep comment\n "unrelated": "keep",\n}\n')
        self.run_config('opencode')
        self.assertIn('// keep comment', source.read_text())
        source.write_text('{"model":"one", "model":"two"}')
        with self.assertRaisesRegex(SystemExit, 'Duplicate configuration key'):
            self.run_config('opencode')

    def test_changed_pending_file_stops(self):
        source, _ = self.run_config('opencode', commit=False)
        source.write_text('{"model":"custom"}')
        with self.assertRaisesRegex(SystemExit, 'interrupted update'):
            self.run_config('opencode')

    def test_transport_override(self):
        for harness in ('opencode', 'codex'):
            if harness == 'codex' and tomlkit is None:
                continue
            source, _ = self.run_config(harness)
            data = self.read(harness, source)
            servers = data['mcp' if harness == 'opencode' else 'mcp_servers']
            servers['mcp-gateway'] = {'command': ['custom']} if harness == 'opencode' else {'command': 'custom'}
            expected = copy.deepcopy(servers['mcp-gateway'])
            self.write(harness, source, data)
            self.run_config(harness, gateway='new-url')
            result = self.read(harness, source)
            self.assertEqual(result['mcp' if harness == 'opencode' else 'mcp_servers']['mcp-gateway'], expected)


if __name__ == '__main__':
    unittest.main()
