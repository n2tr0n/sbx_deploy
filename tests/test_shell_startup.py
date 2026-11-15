"""Check generated shell files with the DHI startup order. Do not deploy."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from test_auth_preservation import payload


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'sbx_local_opencode_deploy.sh').read_text(encoding='utf-8')
BASH = str(Path('C:/Program Files/Git/bin/bash.exe')) if os.name == 'nt' else shutil.which('bash')
USER_LOADER = '# SBX Deploy: user shell loader\ncase $- in *i*) source /usr/local/lib/sbx-deploy/shell.bash ;; esac\n'
PATH_LOADER = '# SBX Deploy: PATH loader\nsource /usr/local/lib/sbx-deploy/path.bash\n'
DHI = '''# Image startup settings.
export BASH_ENV="$HOME/persistent.sh"
__dhi_set_prompt() { local rc=$?; PS1="dhi:$rc "; }
PROMPT_COMMAND=__dhi_set_prompt
'''
CALLER_REFRESH = SOURCE.rsplit('\nSBX_DEPLOY_PAYLOAD\n', 1)[1]


class ShellStartup(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(dir=ROOT)
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        (self.home / 'managed').mkdir()
        (self.home / 'persistent.sh').write_text('# Image hook retained.\n')
        self.environment = dict(os.environ, HOME=self.home.as_posix(), TERM='xterm')
        self.environment.pop('BASH_ENV', None)

    def migrate(self, text, name='.bashrc'):
        source = self.home / name
        staged = self.home / 'staged'
        source.write_bytes(text.encode('utf-8'))
        with patch.object(sys, 'argv', ['migrate', str(source), str(staged), 'user']):
            exec(compile(payload('SBX_MIGRATE_SHELL'), 'startup migration', 'exec'), {})
        return staged.read_text(encoding='utf-8')

    def prepare(self, text=DHI):
        # Generate only the managed shell source. No installer code is executed.
        if not BASH or not Path(BASH).is_file():
            self.skipTest('Bash is required')
        settings = '''# Load definitions once per shell.
if [[ ${_sbx_shell_pid:-} != "$BASHPID" ]]; then
sbx_opencode_binary=/usr/local/bin/opencode
sbx_credential_seconds=5
sbx_kill_seconds=1
''' + payload('SBX_SHELL_SETTINGS')
        (self.home / 'managed/shell.bash').write_text(settings, encoding='utf-8')
        (self.home / 'managed/path.bash').write_text(self.local_paths(payload('SBX_PATH_SETTINGS')), encoding='utf-8')
        migrated = self.migrate(text)
        (self.home / '.bashrc').write_text(self.local_paths(migrated), encoding='utf-8')

    @staticmethod
    def local_paths(text):
        return text.replace('/usr/local/lib/sbx-deploy/shell.bash', '"$HOME/managed/shell.bash"').replace(
            '/usr/local/lib/sbx-deploy/path.bash', '"$HOME/managed/path.bash"')

    def interactive(self, command, *, login=False):
        args = [BASH, '--noprofile', '--norc']
        if login:
            args.append('--login')
        return subprocess.run([*args, '-ic', command], env=self.environment,
                              capture_output=True, text=True, timeout=15)

    def test_migration_preserves_image_text_and_is_unchanged_on_rerun(self):
        original = DHI + PATH_LOADER
        migrated = self.migrate(original)
        self.assertEqual(migrated, USER_LOADER + original)
        self.assertEqual(self.migrate(migrated), migrated)
        self.assertEqual(migrated.count(USER_LOADER), 1)
        self.assertEqual(migrated.count(PATH_LOADER), 1)

    def caller_refresh(self, status):
        self.prepare()
        # Simulate a global rc that returns before the deployment loader.
        (self.home / 'global.bashrc').write_text('return 0\n')
        footer = self.local_paths(CALLER_REFRESH).replace('source /etc/bash.bashrc', 'source "$HOME/global.bashrc"')
        return '{\n(\nexit ' + str(status) + '\n' + footer

    def test_first_paste_activates_current_interactive_shell(self):
        footer = self.caller_refresh(0)
        result = self.interactive(footer + '''
alias configcat
declare -F auth_all short_path _sbx_prompt
[[ ${PROMPT_COMMAND[*]} == *'_sbx_prompt'* ]] || exit 78
[[ $PATH == "$HOME/.local/bin:"* ]] || exit 79
_sbx_prompt
[[ $PS1 == *'$(short_path)'* ]] || exit 80
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('configcat=', result.stdout)
        self.assertIn('short_path', result.stdout)

    def test_failed_paste_preserves_status_without_refresh(self):
        footer = self.caller_refresh(42)
        result = self.interactive(footer + '''
status=$?
[[ $status == 42 ]] || exit 81
if alias configcat >/dev/null 2>&1; then exit 82; fi
if declare -F _sbx_prompt >/dev/null; then exit 83; fi
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_noninteractive_child_does_not_attempt_caller_refresh(self):
        footer = self.caller_refresh(0)
        result = subprocess.run([BASH, '--noprofile', '--norc', '-c', footer + '''
if alias configcat >/dev/null 2>&1; then exit 84; fi
'''], env=self.environment, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_saved_installer_has_the_same_caller_refresh(self):
        self.assertEqual(payload('SBX_CALLER_REFRESH').strip(), CALLER_REFRESH.strip())

    def test_edited_or_duplicate_managed_loader_stops(self):
        for text in (DHI + PATH_LOADER * 2, DHI + USER_LOADER.replace('case $-', 'case "changed"')):
            with self.subTest(text=text), self.assertRaises(SystemExit):
                self.migrate(text)

    def test_reconnect_without_global_bashrc_loads_aliases_and_prompt(self):
        self.prepare()
        for _ in range(2):
            result = self.interactive('''source "$HOME/.bashrc"
alias configcat
declare -F auth_all short_path _sbx_prompt
[[ ${PROMPT_COMMAND[*]} == '__dhi_set_prompt _sbx_prompt' ]] || exit 71
_sbx_prompt
[[ $PS1 == *'$(short_path)'* ]] || exit 72
''')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('configcat=', result.stdout)
            self.assertIn('auth_all', result.stdout)

    def test_global_then_user_loading_keeps_user_aliases_and_prompt_hooks(self):
        self.prepare(DHI + "alias configcat='user-configcat'\nuser_hook() { :; }\nPROMPT_COMMAND+='; user_hook'\n")
        result = self.interactive('''source "$HOME/managed/shell.bash"
source "$HOME/.bashrc"
source "$HOME/managed/path.bash"
[[ $(alias configcat) == *user-configcat* ]] || exit 73
[[ ${PROMPT_COMMAND[*]} == '__dhi_set_prompt; user_hook _sbx_prompt' ]] || exit 74
[[ ${#PROMPT_COMMAND[@]} == 2 ]] || exit 75
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_login_startup_loads_shell_without_sourcing_bashrc(self):
        self.prepare()
        profile = self.migrate(DHI, name='.bash_profile')
        (self.home / '.bash_profile').write_text(self.local_paths(profile), encoding='utf-8')
        result = self.interactive('source "$HOME/.bash_profile"; alias configcat; declare -F short_path', login=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('configcat=', result.stdout)
        self.assertIn('short_path', result.stdout)

    def test_noninteractive_startup_does_not_load_managed_aliases(self):
        self.prepare()
        result = subprocess.run([BASH, '--noprofile', '--norc', '-c', '''source "$HOME/.bashrc"
if alias configcat >/dev/null 2>&1; then exit 76; fi
if declare -F _sbx_prompt >/dev/null; then exit 77; fi
'''], env=self.environment, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
