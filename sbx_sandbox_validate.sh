#!/usr/bin/env bash
# Paste this complete file into sandbox Bash from any directory.
# Save a runnable copy and a private report in HOME. Show the report path.
# Use a Bash text report when Python 3 is absent. Otherwise, use JSON.
# Do not install tools, edit configuration, read credential files, or prompt for input.
# Optional probes: --versions runs tools; --network sends unauthenticated HEAD requests.
# Paste the complete file into sandbox Bash, or run: bash sbx_sandbox_validate.sh
{
(
set -euo pipefail
sbx_validate_args=()
# Ignore shell positional arguments during an interactive paste.
if [[ ${BASH_SOURCE[0]:-} == "$0" || $- != *i* ]]; then
    sbx_validate_args=("$@")
fi
sbx_validate_run() {
    local payload staged= report= saved="$HOME/sbx_sandbox_validate.sh" complete=false option
    IFS= read -r -d '' payload || :
    for option in "${sbx_validate_args[@]}"; do
        case $option in
            --versions|--network) ;;
            --help|-h) printf 'Usage: bash ~/sbx_sandbox_validate.sh [--versions] [--network]\n'; return 0 ;;
            *) printf 'Unknown validator option. Use --help.\n' >&2; return 2 ;;
        esac
    done
    umask 077
    trap '[[ -z $staged ]] || rm -f -- "$staged"; if ! "$complete" && [[ -n $report ]]; then rm -f -- "$report"; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    staged=$(mktemp -- "$HOME/sbx_sandbox_validate.XXXXXX.sh")
    {
        printf '%s\n' '#!/usr/bin/env bash' '# SBX sandbox validator. Save local facts. Preserve settings and logins.'
        printf '%s\n' '{' '(' 'set -euo pipefail' 'sbx_validate_args=("$@")'
        declare -f sbx_validate_run
        printf "%s\n" "sbx_validate_run <<'SBX_VALIDATE_PYTHON'"
        printf '%s' "$payload"
        printf '%s\n' 'SBX_VALIDATE_PYTHON' ')' '}'
    } > "$staged"
    if [[ -f $saved && ! -L $saved ]] && cmp -s -- "$staged" "$saved"; then
        rm -f -- "$staged"
    elif [[ ! -e $saved && ! -L $saved ]]; then
        ln -T -- "$staged" "$saved"
        rm -f -- "$staged"
    else
        # Keep a different saved copy. Never replace user edits or symlinks.
        saved=$staged
    fi
    staged=
    printf 'Validator copy: %s\n' "$saved" >&2
    if command -v python3 >/dev/null 2>&1; then
        report=$(mktemp -- "$HOME/sbx-sandbox-report.XXXXXX.json")
        printf '%s\n' "$payload" | python3 - "${sbx_validate_args[@]}" | tee -- "$report"
    else
        printf 'Python 3 is absent from PATH. Collecting a Bash text report.\n' >&2
        report=$(mktemp -- "$HOME/sbx-sandbox-report.XXXXXX.txt")
        {
            printf 'SBX sandbox report: Bash fallback\n'
            printf 'Python 3: unavailable in PATH\nBash: %s\nUID: %s\n' "$BASH_VERSION" "$EUID"
            printf 'No packages installed. No settings or credential files read.\n'
            local tool binary key value path status
            if [[ -r /etc/os-release ]]; then
                while IFS='=' read -r key value; do
                    case $key in
                        ID|VERSION_ID) printf 'OS %s: %s\n' "$key" "$value" ;;
                    esac
                done < /etc/os-release
            fi
            printf '\nExecutable paths:\n'
            for tool in bash python3 python python3.14 python3.13 python3.12 python3.11 sudo flock timeout dpkg-query apt-get apk rpm curl git node npm tmux opencode codex docker; do
                binary=$(type -P "$tool" || :)
                printf '%s: %s\n' "$tool" "${binary:-missing}"
            done
            printf '\nPaths (no file contents):\n'
            for path in /home/agent/.opencode/bin/opencode /usr/local/bin/opencode "$HOME/.local/bin/codex" /etc/bash.bashrc /etc/sandbox-persistent.sh /etc/tmux.conf /usr/local/bin /run /tmp; do
                status=missing
                if [[ -L $path ]]; then status=symlink
                elif [[ -f $path ]]; then status=file
                elif [[ -d $path ]]; then status=directory
                elif [[ -e $path ]]; then status=other
                fi
                printf '%s: %s; readable=%s writable=%s executable=%s\n' "$path" "$status" \
                    "$([[ -r $path ]] && printf yes || printf no)" \
                    "$([[ -w $path ]] && printf yes || printf no)" \
                    "$([[ -x $path ]] && printf yes || printf no)"
            done
            printf '\nCore package subset (local database only):\n'
            if command -v dpkg-query >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
                if timeout --kill-after=1s 5s dpkg-query -W -f='${Package}\t${db:Status-Status}\t${Version}\n' python3 sudo util-linux coreutils curl git tmux ca-certificates 2>/dev/null; then
                    :
                else
                    printf 'Package query incomplete. Missing packages or a query error remain possible.\n'
                fi
            else
                printf 'Not checked: dpkg-query or timeout is absent.\n'
            fi
            printf '\nPasswordless sudo:\n'
            if (( EUID == 0 )); then
                printf 'Running as root.\n'
            elif command -v sudo >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
                if timeout --kill-after=1s 5s sudo -n true >/dev/null 2>&1; then
                    printf 'Available.\n'
                else
                    printf 'Unavailable or timed out.\n'
                fi
            else
                printf 'Not checked: sudo or timeout is absent.\n'
            fi
            printf '\nPending: full package inventory, tool versions, network, authentication, inference, and MCP checks.\n'
            printf 'Optional version and network probes need Python 3 and were skipped.\n'
        } | tee -- "$report"
    fi
    complete=true
    printf '\nReport saved: %s\nRerun: bash %q --versions --network\n' "$report" "$saved" >&2
    trap - EXIT INT TERM
}
sbx_validate_run <<'SBX_VALIDATE_PYTHON'
import argparse
import datetime
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import stat
import subprocess
import sys


# These requirements describe the current installer, not an upstream image contract.
PACKAGES = '''ansible strace ltrace plocate atop htop btop nmon nmap git net-tools
unzip bind9-utils rsync curl lynx tcpdump vim whois sudo tmux mtr libaa-bin
python3 python3-passlib python3-tomlkit rsyslog logrotate procps util-linux tzdata cmatrix'''.split()
LEGACY_OPENCODE = '.opencode/bin/opencode'
GATEWAY = 'http://mcp-gateway.docker.internal/mcp'
TOOLS = 'bash sudo flock timeout dpkg-query apt-get curl git python3 node npm tmux opencode codex docker code rsyslogd logrotate'.split()
ENDPOINTS = {
    'github': 'https://api.github.com/',
    'opencode_download': 'https://opencode.ai/install',
    'codex_download': 'https://chatgpt.com/codex/install.sh',
    'codex_releases': 'https://releases.openai.com/',
    'openai_oauth': 'https://auth.openai.com/',
    'openai_backend': 'https://chatgpt.com/backend-api/codex/models',
    'vscode_download': 'https://update.code.visualstudio.com/',
    'vscode_cdn': 'https://vscode.download.prss.microsoft.com/',
    'webtop_registry': 'https://lscr.io/v2/',
    'mcp_gateway': GATEWAY,
}


def run(args, seconds=5):
    """Keep raw output private. Stop the process group when a probe times out."""
    try:
        process = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return 'unavailable', ''
    try:
        output, _ = process.communicate(timeout=seconds)
    except (subprocess.TimeoutExpired, KeyboardInterrupt, SystemExit) as error:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.communicate()
        if not isinstance(error, subprocess.TimeoutExpired):
            raise
        return 'timeout', ''
    return process.returncode, output.decode('utf-8', errors='replace')


def metadata(path):
    """Inspect paths without opening configuration or credential files."""
    path = Path(path)
    result = {'path': str(path)}
    try:
        info = path.lstat()
        result.update(kind=('symlink' if stat.S_ISLNK(info.st_mode) else
                            'file' if stat.S_ISREG(info.st_mode) else
                            'directory' if stat.S_ISDIR(info.st_mode) else 'other'),
                      uid=info.st_uid, gid=info.st_gid, mode=oct(stat.S_IMODE(info.st_mode)),
                      readable=os.access(path, os.R_OK), writable=os.access(path, os.W_OK),
                      executable=os.access(path, os.X_OK))
    except FileNotFoundError:
        result['kind'] = 'missing'
    except OSError:
        result['kind'] = 'unavailable'
    return result


def shell_startup(path):
    """Return loader flags, never startup text. Do not execute the file."""
    if metadata(path)['kind'] != 'file':
        return {'status': 'unavailable'}
    try:
        flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0)
        with os.fdopen(os.open(path, flags), 'rb') as handle:
            if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
                return {'status': 'unavailable'}
            content = handle.read(262145)
        if len(content) > 262144:
            return {'status': 'too large'}
    except OSError:
        return {'status': 'unavailable'}
    text = content.decode('utf-8', errors='replace')
    shell_loader = '# SBX Deploy: user shell loader\ncase $- in *i*) source /usr/local/lib/sbx-deploy/shell.bash ;; esac\n'
    path_loader = '# SBX Deploy: PATH loader\nsource /usr/local/lib/sbx-deploy/path.bash\n'
    return {'status': 'checked', 'user_shell_loader': text.startswith(shell_loader),
            'path_loader': path_loader in text}


def candidates(name, search_path, home):
    paths = [Path(directory) / name for directory in search_path.split(os.pathsep) if directory]
    if name == 'opencode':
        paths.extend([home / LEGACY_OPENCODE, Path('/usr/local/bin/opencode')])
    if name == 'codex':
        paths.append(home / '.local/bin/codex')
    found = []
    for path in dict.fromkeys(paths):
        item = metadata(path)
        if item['kind'] != 'missing':
            found.append(item)
    return found


def packages():
    binary = shutil.which('dpkg-query')
    if not binary:
        return {'status': 'unavailable', 'items': {}}
    code, output = run([binary, '-W', '-f=${Package}\t${db:Status-Status}\t${Version}\n', *PACKAGES])
    items = {name: {'status': 'missing'} for name in PACKAGES}
    for line in output.splitlines():
        parts = line.split('\t')
        if len(parts) != 3 or parts[0] not in items:
            continue
        name, status, version = parts
        if status == 'installed' and re.fullmatch(r'[A-Za-z0-9.+:~_-]+', version):
            items[name] = {'status': 'installed', 'version': version}
    if code not in (0, 1):
        return {'status': str(code), 'items': {}}
    return {'status': 'checked', 'items': items}


def network():
    binary = shutil.which('curl')
    if not binary:
        return {'status': 'unavailable'}
    results = {}
    for name, url in ENDPOINTS.items():
        # -q must be first. Do not read curlrc, follow redirects, or print headers.
        code, output = run([binary, '-q', '--head', '--silent', '--output', '/dev/null',
                            '--connect-timeout', '3', '--max-time', '6', '--retry', '0',
                            '--write-out', '%{http_code}', url], seconds=8)
        results[name] = {'exit': code, 'http_status': output if re.fullmatch(r'\d{3}', output) else None}
    return results


def collect(args):
    home = Path.home()
    search_path = os.environ.get('PATH', '')
    config = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config')))
    data = Path(os.environ.get('XDG_DATA_HOME', str(home / '.local/share')))
    state = Path(os.environ.get('XDG_STATE_HOME', str(home / '.local/state')))
    codex = Path(os.environ.get('CODEX_HOME', str(home / '.codex')))
    report = {'schema_version': 2, 'collected_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'scope': 'Local facts only. No authentication or inference checks.',
              'system': {'os': platform.system(), 'architecture': platform.machine(),
                         'kernel': platform.release(), 'python': platform.python_version(),
                         'uid': os.geteuid(), 'gid': os.getegid(),
                         'stdin_tty': sys.stdin.isatty(), 'stdout_tty': sys.stdout.isatty()}}
    try:
        release = platform.freedesktop_os_release()
        report['system']['distribution'] = {key: release[key] for key in ('ID', 'VERSION_ID') if key in release}
    except (OSError, AttributeError):
        report['system']['distribution'] = {'status': 'unavailable'}
    report['tools'] = {name: {'selected': shutil.which(name), 'candidates': candidates(name, search_path, home)} for name in TOOLS}
    report['packages'] = packages()
    selected_opencode = report['tools']['opencode']['selected'] or str(home / LEGACY_OPENCODE)
    paths = {'selected_opencode': Path(selected_opencode), 'opencode_json': config / 'opencode/opencode.json',
             'opencode_jsonc': config / 'opencode/opencode.jsonc', 'opencode_auth': data / 'opencode/auth.json',
             'codex_config': codex / 'config.toml', 'codex_auth': codex / 'auth.json',
             'ownership': state / 'sbx-deploy/config-ownership',
             'global_bashrc': Path('/etc/bash.bashrc'), 'user_bashrc': home / '.bashrc',
             'managed_shell': Path('/usr/local/lib/sbx-deploy/shell.bash'),
             'managed_path': Path('/usr/local/lib/sbx-deploy/path.bash'),
             'profile': home / '.profile', 'persistent_hook': Path('/etc/sandbox-persistent.sh'),
             'tmux_config': Path('/etc/tmux.conf'), 'tpm': home / '.tmux/plugins/tpm/tpm',
             'resurrect': home / '.tmux/plugins/tmux-resurrect/resurrect.tmux',
             'vscode_cli': home / '.local/lib/sbx-deploy/vscode-code',
             'logrotate_config': Path('/etc/logrotate.conf'), 'rsyslog_rotation': Path('/etc/logrotate.d/rsyslog'),
             'usr_local_bin': Path('/usr/local/bin'), 'run': Path('/run'), 'tmp': Path('/tmp')}
    report['paths'] = {name: metadata(path) for name, path in paths.items()}
    report['shell_startup'] = shell_startup(home / '.bashrc')
    report['environment'] = {'present': {name: bool(os.environ.get(name)) for name in (
        'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy',
        'SSL_CERT_FILE', 'SSL_CERT_DIR', 'CURL_CA_BUNDLE', 'REQUESTS_CA_BUNDLE', 'BASH_ENV',
        'OPENAI_API_KEY', 'GITHUB_TOKEN', 'GH_TOKEN')},
        'credential_modes': {name: os.environ.get(name) if os.environ.get(name) in ('oauth', 'apiKey', 'none')
                             else 'other' if os.environ.get(name) else 'unset'
                             for name in ('SBX_CRED_OPENAI_MODE', 'SBX_CRED_GITHUB_MODE')}}
    report['python_modules'] = {name: importlib.util.find_spec(name) is not None for name in ('passlib', 'tomlkit')}
    if os.geteuid() == 0:
        report['sudo'] = {'status': 'root'}
    else:
        binary = shutil.which('sudo')
        code, _ = run([binary, '-n', 'true']) if binary else ('unavailable', '')
        report['sudo'] = {'status': 'available' if code == 0 else str(code)}
    report['versions'] = {'status': 'not requested'}
    if args.versions:
        report['versions'] = {}
        for name in ('opencode', 'codex', 'node', 'npm', 'tmux', 'docker'):
            binary = report['tools'][name]['selected']
            code, output = run([binary, '-V' if name == 'tmux' else '--version']) if binary else ('unavailable', '')
            # Return only a numeric version. Never return raw command output.
            match = re.search(r'(?<![\w.])v?(\d{1,4}\.\d{1,4}(?:\.\d{1,4})?)(?![\w.])', output) if code == 0 else None
            report['versions'][name] = {'exit': code, 'version': match[1] if match else None}
    report['network'] = network() if args.network else {'status': 'not requested'}
    findings = []
    def finding(kind, message):
        findings.append({'kind': kind, 'message': message})
    if report['system']['os'] != 'Linux':
        finding('blocker', 'Run this tool inside sandbox Linux.')
    if report['sudo']['status'] not in ('root', 'available'):
        finding('blocker', 'Passwordless sudo is unavailable. Installer elevation will fail.')
    expected = report['paths']['selected_opencode']
    if expected['kind'] not in ('file', 'symlink') or not expected.get('executable'):
        finding('compatibility', 'No usable OpenCode executable was selected. Compare discovered candidates before repair.')
    for name in ('bash', 'flock', 'timeout', 'dpkg-query', 'apt-get'):
        if not report['tools'][name]['selected']:
            finding('blocker', name + ' is absent from PATH.')
    if report['packages']['status'] == 'checked':
        missing = [name for name, item in report['packages']['items'].items() if item['status'] != 'installed']
        if missing:
            finding('install_needed', 'Installer packages absent: ' + ', '.join(missing))
    if report['environment']['credential_modes']['SBX_CRED_OPENAI_MODE'] != 'oauth':
        finding('check_host', 'Host OpenAI OAuth mode is not advertised. This does not prove login failure.')
    for name in ('opencode_json', 'opencode_jsonc', 'codex_config'):
        if report['paths'][name]['kind'] in ('symlink', 'directory', 'other', 'unavailable'):
            finding('ownership', name + ' needs review before installer configuration changes.')
    startup = report['shell_startup']
    if startup['status'] != 'checked' or not startup.get('user_shell_loader') or not startup.get('path_loader'):
        finding('shell_setup', 'User Bash loaders are absent or unverified. Reconnect can miss aliases or the prompt hook.')
    if any(report['paths'][name]['kind'] != 'file' for name in ('managed_shell', 'managed_path')):
        finding('shell_setup', 'Managed shell files are absent or unavailable.')
    report['findings'] = findings
    report['unverified'] = ['Package repository availability and upgrade permissions.',
                            'Saved logins, host token substitution, model inference, and MCP tools.',
                            'Host image identity, kit composition, network policy, and port bindings.',
                            'Live aliases and prompt hooks after reconnect, login Bash, and a new tmux pane.',
                            'Installer preservation, unchanged rerun, and interruption recovery.']
    return report


def main():
    parser = argparse.ArgumentParser(description='Collect sandbox requirements without deployment. JSON goes to stdout.')
    parser.add_argument('--versions', action='store_true', help='Run tool version commands. Tools can create their own cache files.')
    parser.add_argument('--network', action='store_true', help='Probe fixed endpoints through the current proxy. No login or inference.')
    args = parser.parse_args()
    report = collect(args)
    print(json.dumps(report, indent=2, sort_keys=True))
    print('Sandbox report complete: %d findings. JSON is on stdout.' % len(report['findings']), file=sys.stderr)
    for item in report['findings']:
        print('[%s] %s' % (item['kind'], item['message']), file=sys.stderr)


if __name__ == '__main__':
    def terminate(signum, frame):
        sys.exit(143)
    signal.signal(signal.SIGTERM, terminate)
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception:
        # Exception text can contain environment values. Do not print it.
        print('Validator failed. Report is incomplete. No deployment was attempted.', file=sys.stderr)
        sys.exit(2)
SBX_VALIDATE_PYTHON
)
}
