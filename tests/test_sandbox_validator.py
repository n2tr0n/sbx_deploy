"""Check the collector payload without running deployment or network probes."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'sbx_sandbox_validate.sh').read_text(encoding='utf-8')
PAYLOAD = SOURCE.split("\nsbx_validate_run <<'SBX_VALIDATE_PYTHON'\n", 1)[1].split('\nSBX_VALIDATE_PYTHON\n', 1)[0]
validator = types.ModuleType('validator')
exec(compile(PAYLOAD, 'validator payload', 'exec'), validator.__dict__)


class ValidatorTests(unittest.TestCase):
    def test_startup_loader_check_returns_flags_without_file_content(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            path = Path(directory) / '.bashrc'
            path.write_bytes(b'OPENAI_API_KEY=PRIVATE-CREDENTIAL\n# SBX Deploy: PATH loader\nsource /usr/local/lib/sbx-deploy/path.bash\n')
            report = validator.shell_startup(path)
            self.assertFalse(report['user_shell_loader'])
            self.assertTrue(report['path_loader'])
            self.assertNotIn('PRIVATE-CREDENTIAL', json.dumps(report))
            prefix = b'# SBX Deploy: user shell loader\ncase $- in *i*) source /usr/local/lib/sbx-deploy/shell.bash ;; esac\n'
            path.write_bytes(prefix + path.read_bytes())
            self.assertTrue(validator.shell_startup(path)['user_shell_loader'])

    def test_paste_without_python_saves_text_report(self):
        bash = Path('C:/Program Files/Git/bin/bash.exe')
        if not bash.is_file():
            self.skipTest('Local Git Bash is required for the paste wrapper check')
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            home = Path(directory)
            environment = dict(validator.os.environ, HOME=home.as_posix(),
                               OPENAI_API_KEY='PRIVATE-CREDENTIAL-MUST-NOT-APPEAR')
            # Simulate missing Python. Keep host sudo and package queries out of this check.
            stub = '''command() {
                if [[ ${1-} == -v ]]; then
                    case ${2-} in python3|sudo|dpkg-query) return 1 ;; esac
                fi
                builtin command "$@"
            }
'''
            result = subprocess.run([str(bash), '--noprofile', '--norc'],
                                    input=stub + SOURCE + '\nprintf "PASTE_FINISHED\\n"\n',
                                    text=True, capture_output=True, env=environment, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('PASTE_FINISHED', result.stdout)
            self.assertIn('Report saved:', result.stderr)
            self.assertTrue((home / 'sbx_sandbox_validate.sh').is_file())
            reports = list(home.glob('sbx-sandbox-report.*.txt'))
            self.assertEqual(len(reports), 1)
            report = reports[0].read_text()
            self.assertIn('Python 3: unavailable in PATH', report)
            self.assertIn('Executable paths:', report)
            self.assertIn('were skipped', report)
            self.assertNotIn('PRIVATE-CREDENTIAL-MUST-NOT-APPEAR', report)
            self.assertEqual(list(home.glob('sbx-sandbox-report.*.json')), [])

    def test_paste_saves_report_and_preserves_saved_copy(self):
        # Run only the wrapper. Replace the collector with a local stub.
        bash = Path('C:/Program Files/Git/bin/bash.exe')
        if not bash.is_file():
            self.skipTest('Local Git Bash is required for the paste wrapper check')
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            home = Path(directory)
            environment = dict(validator.os.environ, HOME=home.as_posix())
            command = 'python3() { cat >/dev/null; printf \'{}\\n\'; };\n' + SOURCE + '\nprintf "PASTE_FINISHED\\n"\n'
            def paste():
                result = subprocess.run([str(bash), '--noprofile', '--norc'], input=command,
                                        text=True, capture_output=True, env=environment, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('PASTE_FINISHED', result.stdout)
                self.assertIn('Report saved:', result.stderr)
                return result
            paste()
            saved = home / 'sbx_sandbox_validate.sh'
            original = saved.read_bytes()
            modified = saved.stat().st_mtime_ns
            syntax = subprocess.run([str(bash), '-n', saved.as_posix()], capture_output=True, text=True)
            self.assertEqual(syntax.returncode, 0, syntax.stderr)
            rerun = subprocess.run([str(bash), '--noprofile', '--norc', '-c',
                'python3() { cat >/dev/null; printf \'{}\\n\'; }; export -f python3; bash "$HOME/sbx_sandbox_validate.sh" --versions --network'],
                text=True, capture_output=True, env=environment, timeout=15)
            self.assertEqual(rerun.returncode, 0, rerun.stderr)
            paste()
            self.assertEqual(saved.read_bytes(), original)
            self.assertEqual(saved.stat().st_mtime_ns, modified)
            self.assertEqual(len(list(home.glob('sbx_sandbox_validate*.sh'))), 1)
            failed = subprocess.run([str(bash), '--noprofile', '--norc', '-c',
                'python3() { cat >/dev/null; return 7; }; export -f python3; bash "$HOME/sbx_sandbox_validate.sh"'],
                text=True, capture_output=True, env=environment, timeout=15)
            self.assertEqual(failed.returncode, 7, failed.stderr)
            self.assertNotIn('unbound variable', failed.stderr)
            self.assertEqual(len(list(home.glob('sbx-sandbox-report.*.json'))), 3)
            saved.write_text('# user file\n')
            paste()
            self.assertEqual(saved.read_text(), '# user file\n')
            self.assertEqual(len(list(home.glob('sbx_sandbox_validate*.sh'))), 2)
            for report in home.glob('sbx-sandbox-report.*.json'):
                self.assertEqual(json.loads(report.read_text()), {})
            self.assertEqual(len(list(home.glob('sbx-sandbox-report.*.json'))), 4)

    def test_requirements_match_installer(self):
        source = (ROOT / 'sbx_local_opencode_deploy.sh').read_text(encoding='utf-8')
        packages = re.search(r'^required_packages=\(\n(.*?)\n\)', source, re.M | re.S)[1].split()
        self.assertEqual(set(validator.PACKAGES), set(packages + ['cmatrix']))
        self.assertIn('$HOME/' + validator.LEGACY_OPENCODE, source)
        self.assertIn('opencode_binary=$(find_opencode)', source)
        self.assertIn('MCP_GATEWAY_URL:-' + validator.GATEWAY, source)

    def test_default_report_has_no_secrets_or_optional_probes(self):
        secret = 'DO-NOT-PRINT-THIS-CREDENTIAL'
        def metadata(path):
            path = Path(path).as_posix()
            # Reproduce the reported image layout.
            present = path == '/usr/local/bin/opencode'
            return {'path': path, 'kind': 'file' if present else 'missing', 'executable': present}

        with patch.dict(validator.os.environ, {'OPENAI_API_KEY': secret, 'USERPROFILE': str(ROOT), 'HOME': str(ROOT),
                        'HTTPS_PROXY': 'https://user:' + secret + '@proxy.invalid',
                        'SBX_CRED_OPENAI_MODE': secret}, clear=True), \
                patch.object(validator.os, 'geteuid', return_value=0, create=True), \
                patch.object(validator.os, 'getegid', return_value=0, create=True), \
                patch.object(validator, 'metadata', side_effect=metadata), \
                patch.object(validator, 'packages', return_value={'status': 'unavailable', 'items': {}}), \
                patch.object(validator.shutil, 'which', side_effect=lambda name: '/usr/local/bin/opencode' if name == 'opencode' else None), \
                patch.object(validator.importlib.util, 'find_spec', return_value=None), \
                patch.object(validator, 'network') as network, \
                patch.object(validator, 'run') as run:
            report = validator.collect(argparse.Namespace(versions=False, network=False))
        network.assert_not_called()
        run.assert_not_called()
        encoded = json.dumps(report)
        self.assertNotIn(secret, encoded)
        self.assertTrue(report['environment']['present']['OPENAI_API_KEY'])
        self.assertEqual(report['environment']['credential_modes']['SBX_CRED_OPENAI_MODE'], 'other')
        self.assertFalse(any(item['kind'] == 'compatibility' for item in report['findings']))
        self.assertEqual(report['tools']['opencode']['candidates'][0]['path'], '/usr/local/bin/opencode')

    def test_package_partial_results_and_failure(self):
        with patch.object(validator.shutil, 'which', return_value='/usr/bin/dpkg-query'), \
                patch.object(validator, 'run', return_value=(1, 'tmux\tinstalled\t3.5a-2\n')):
            report = validator.packages()
        self.assertEqual(report['items']['tmux']['version'], '3.5a-2')
        self.assertEqual(report['items']['ansible']['status'], 'missing')
        with patch.object(validator.shutil, 'which', return_value='/usr/bin/dpkg-query'), \
                patch.object(validator, 'run', return_value=('timeout', '')):
            self.assertEqual(validator.packages(), {'status': 'timeout', 'items': {}})

    def test_network_never_returns_response_content(self):
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            return 0, 'secret response body'
        with patch.object(validator.shutil, 'which', return_value='/usr/bin/curl'), \
                patch.object(validator, 'run', side_effect=run):
            report = validator.network()
        self.assertNotIn('secret', json.dumps(report))
        self.assertEqual(len(calls), len(validator.ENDPOINTS))
        for args in calls:
            self.assertEqual(args[1], '-q')
            self.assertIn('--head', args)
            self.assertNotIn('--location', args)
            self.assertNotIn('--header', args)
            self.assertIn('--max-time', args)

    def test_cloud_network_probes_use_validated_endpoint_and_hide_urls(self):
        for gateway in ('https://gateway.example/mcp', '', 'https://user:PRIVATE@gateway.example/mcp'):
            calls = []
            def run(args, **kwargs):
                calls.append(args)
                return 0, '200'
            with patch.dict(validator.os.environ, {'SBX_ENV': 'cloud', 'SBX_MCP_GATEWAY_URL': gateway}, clear=True), \
                    patch.object(validator.shutil, 'which', return_value='/usr/bin/curl'), \
                    patch.object(validator, 'run', side_effect=run):
                report = validator.network()
            self.assertNotIn('PRIVATE', json.dumps(report))
            self.assertNotIn('gateway.example', json.dumps(report))
            if gateway == 'https://gateway.example/mcp':
                self.assertIn(gateway, [args[-1] for args in calls])
            else:
                self.assertNotIn('mcp_gateway', report)
            self.assertNotIn(validator.GATEWAY, [args[-1] for args in calls])

    def test_timeout_kills_process_group(self):
        process = types.SimpleNamespace(pid=123, communicate=unittest.mock.Mock(
            side_effect=[subprocess.TimeoutExpired('fixture', 1), (b'', b'')]))
        with patch.object(validator.subprocess, 'Popen', return_value=process), \
                patch.object(validator.signal, 'SIGKILL', 9, create=True), \
                patch.object(validator.os, 'killpg', create=True) as kill:
            self.assertEqual(validator.run(['fixture'], seconds=1), ('timeout', ''))
        kill.assert_called_once_with(123, 9)

    def test_interrupt_kills_child_and_preserves_status(self):
        for error in (KeyboardInterrupt(), SystemExit(143)):
            process = types.SimpleNamespace(pid=123, communicate=unittest.mock.Mock(
                side_effect=[error, (b'', b'')]))
            with patch.object(validator.subprocess, 'Popen', return_value=process), \
                    patch.object(validator.signal, 'SIGKILL', 9, create=True), \
                    patch.object(validator.os, 'killpg', create=True) as kill:
                with self.assertRaises(type(error)):
                    validator.run(['fixture'])
            kill.assert_called_once_with(123, 9)


if __name__ == '__main__':
    unittest.main()
