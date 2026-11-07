#!/usr/bin/env bash
# Features and sections, in execution order (keep this list current):
#  1. Isolate shell options and traps so the whole script can be pasted into Bash.
#  2. Display the SBX Deploy banner.
#  3. Define paths and helpers; select root or passwordless sudo for system changes.
#  4. Check existing plugin paths and the tmux config before making changes.
#  5. Install missing sandbox packages; omit recommended packages for cmatrix only.
#  6. Download missing TPM and tmux-resurrect checkouts using staged shallow clones.
#  7. Prepare temporary-file/session cleanup and atomic config replacement helpers.
#  8. Install the supplied system tmux config, backing up differing existing content.
#  9. Load plugins into the current/default tmux server and verify their key bindings.
# 10. Install or verify the user-local UTF-8 tmux wrapper without replacing user files.
# 11. Add the wrapper to PATH in interactive and login Bash startup files, once each.
# 12. Add system Bash aliases for Ansible, permissions, hashing, configcat, and netstat.
# 13. Print shell reload, tmux startup, and locale verification instructions.
# 14. On exit, remove temporary files and the installer's temporary tmux session.
#
# Paste this entire block into Bash, then press Enter, or run: bash sbx_deploy.sh
# The subshell is parsed before execution: child commands cannot consume the
# remaining pasted script, and strict mode/traps never leak into your shell.
(
set -euo pipefail

# FIGlet Slant by Glenn Chappell, pre-rendered at full width.
cat <<'SBX_BANNER'

  .-----------------------------------------------------------------------.
 /__________  N I T R O N   P R E S E N T S  ______________________________\
 \_  _                                                                   _/
   \/     _______   _______  ___   ___                                   \/
   /\    /  _____/ /  __   \ \  \ /  /                                   /\
  /  \   \____  \ /  __   <   \  V  /       .:: S B X   D E P L O Y ::. /  \
  \  /  /_______//________/   /_/ \_\                                   \  /
   \/  _______________________________________________________________  \/
   /\  \__  Nitron's Deployment Script for SBX vAlpha-0.1          __/  /\
 _/  \____\_______________________________________________________/____/  \_
 \_________________________________________________________________________/

SBX_BANNER

conf=/etc/tmux.conf
plugin_dir="$HOME/.tmux/plugins"
tpm_dir="$plugin_dir/tpm"
resurrect_dir="$plugin_dir/tmux-resurrect"
resurrect_plugin="$resurrect_dir/resurrect.tmux"

die() { printf 'SBX Deploy: %s\n' "$*" >&2; exit 1; }
exists() { [[ -e "$1" || -L "$1" ]]; }

# Passwordless sudo is expected for a non-root sandbox user.
root=()
if (( EUID != 0 )); then
    command -v sudo >/dev/null 2>&1 || die 'sudo is required; install it as root first.'
    root=(sudo -n)
fi
run_as_root() { "${root[@]}" "$@"; }

tpm_ready() {
    [[ -f "$tpm_dir/tpm" && -x "$tpm_dir/tpm" &&
       -f "$tpm_dir/bin/install_plugins" && -x "$tpm_dir/bin/install_plugins" ]]
}
resurrect_ready() {
    [[ -f "$resurrect_plugin" && -r "$resurrect_plugin" && -x "$resurrect_plugin" ]]
}

# Refuse to overwrite user-owned or incomplete checkouts. New clones are staged
# below, so an interrupted download cannot leave a partial final checkout.
if exists "$tpm_dir"; then
    tpm_ready || die "Existing TPM path is unusable: $tpm_dir"
fi
if exists "$resurrect_dir"; then
    resurrect_ready || die "Existing tmux-resurrect path is unusable: $resurrect_dir"
fi
if exists "$conf" && [[ ! -f "$conf" ]]; then
    die "Configuration does not point to a regular file: $conf"
fi

# Check local dpkg state before doing any network work. Keep cmatrix separate
# because only that package should omit recommended dependencies. Python 3 and
# passlib support the makepass alias installed below.
package_installed() {
    [[ $(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) == installed ]]
}
required_packages=(
    ansible strace ltrace plocate atop htop nmon nmap git net-tools
    unzip bind9-utils rsync curl lynx tcpdump vim whois sudo tmux mtr
    libaa-bin python3 python3-passlib
)
missing_packages=()
for package in "${required_packages[@]}"; do
    if ! package_installed "$package"; then
        missing_packages+=("$package")
    fi
done
missing_cmatrix=false
package_installed cmatrix || missing_cmatrix=true
if (( ${#missing_packages[@]} )) || "$missing_cmatrix"; then
    run_as_root apt-get update
    if (( ${#missing_packages[@]} )); then
        run_as_root apt-get install -y "${missing_packages[@]}"
    fi
    if "$missing_cmatrix"; then
        run_as_root apt-get install -y --no-install-recommends cmatrix
    fi
fi

clone_plugin() (
    local repository=$1 destination=$2 staging_dir
    exists "$destination" && return 0
    mkdir -p -- "$plugin_dir"
    staging_dir=$(mktemp -d -- "$plugin_dir/.plugin-stage.XXXXXX")
    trap 'rm -rf -- "$staging_dir"' EXIT
    # Same-filesystem publication; never merge into or replace an existing path.
    git clone --depth 1 "https://github.com/tmux-plugins/$repository" "$staging_dir/checkout"
    mv -nT -- "$staging_dir/checkout" "$destination"
)
clone_plugin tpm "$tpm_dir"
clone_plugin tmux-resurrect "$resurrect_dir"
tpm_ready || die "TPM checkout is unusable: $tpm_dir"
resurrect_ready || die "tmux-resurrect checkout is unusable: $resurrect_dir"

# One private workspace holds generated files, never user data. Each publishing
# helper owns a separate EXIT trap for its same-directory staging file.
work_dir=$(mktemp -d)
setup_session=
cleanup_installer() {
    rm -rf -- "$work_dir"
    if [[ -n "$setup_session" ]] &&
       /usr/bin/tmux has-session -t "=$setup_session" 2>/dev/null; then
        /usr/bin/tmux kill-session -t "=$setup_session" ||
            printf 'Could not remove temporary tmux session: %s\n' "$setup_session" >&2
    fi
}
trap cleanup_installer EXIT

# Shared atomic replacement for system configuration. A matching file is a no-op;
# changed files get a metadata-preserving backup before the rename. Symlinks may
# match, but are never replaced. Reuse an identical backup after an interrupted run.
replace_system_file() (
    local source=$1 target=$2 mode=${3-} staged= backup compare_status
    trap 'if [[ -n "$staged" ]]; then run_as_root rm -f -- "$staged"; fi' EXIT
    if exists "$target"; then
        [[ -f "$target" ]] || die "Not a regular file: $target"
        if run_as_root cmp -s -- "$target" "$source"; then
            return 0
        else
            compare_status=$?
        fi
        (( compare_status == 1 )) || die "Cannot compare configuration: $target"
        [[ ! -L "$target" ]] || die "Configuration differs; update its symlink target: $target"
    fi

    staged=$(run_as_root mktemp -- "$target.tmp.XXXXXX")
    if exists "$target"; then
        run_as_root cp -p -- "$target" "$staged"
    fi
    run_as_root tee "$staged" < "$source" >/dev/null
    if [[ -n "$mode" ]]; then
        run_as_root chmod "$mode" -- "$staged"
    fi

    if exists "$target"; then
        backup=
        for candidate in "$target".bak.*; do
            if [[ -f "$candidate" && ! -L "$candidate" ]] &&
               run_as_root cmp -s -- "$target" "$candidate"; then
                backup=$candidate
                break
            fi
        done
        if [[ -z "$backup" ]]; then
            backup=$(run_as_root mktemp -- "$target.bak.XXXXXX")
            if ! run_as_root cp -p -- "$target" "$backup"; then
                run_as_root rm -f -- "$backup"
                die "Cannot back up configuration: $target"
            fi
            printf 'Saved previous configuration to %s\n' "$backup"
        fi
    fi
    run_as_root mv -fT -- "$staged" "$target"
    staged=
)

# Keep the supplied tmux configuration verbatim. Its quoted heredoc defers HOME
# and tmux format expansion until tmux reads the installed configuration.
new_conf="$work_dir/tmux.conf"
cat > "$new_conf" <<'TMUX_CONF'
set -g mouse on

set-option -g history-limit 1000000000

#set -g pane-border-format "#{pane_index}"
set -g pane-border-format "#[fg=colour6]#{pane_index} #[fg=yellow]#{pane_title}"
set -g pane-border-status top

setw -g window-status-format "#[fg=colour6][#I]#[fg=white]#W"
setw -g window-status-current-format "#[fg=#000000,bold,bg=yellow]#I [#W]#[default]"
set-window-option -g status-position top

set -g status-fg white
set -g status-bg black
set -g status-left-length 100
set -g status-right-length 60
set-option -g status-interval 5
set-option -g automatic-rename on
set-option -g automatic-rename-format '#{b:pane_current_path}'

set -g status-right "#[fg=green]%a %Y-%m-%d %k:%M:%S (#(date -u | awk '{print $4}') UTC)"
set -g status-left "#[fg=yellow]Remote #[fg=green]#h >>"
set-option -g renumber-windows on

#tmux plugins
set-environment -g TMUX_PLUGIN_MANAGER_PATH "~/.tmux/plugins/"
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
# set -g @resurrect-capture-pane-contents 'on'

# This line must be at the very bottom of /etc/tmux.conf:
run-shell -b 'if [ -x "$HOME/.tmux/plugins/tpm/tpm" ] && [ -x "$HOME/.tmux/plugins/tmux-resurrect/resurrect.tmux" ]; then "$HOME/.tmux/plugins/tpm/tpm"; fi'
TMUX_CONF
replace_system_file "$new_conf" "$conf" 644

# Use the current/default server so existing sessions gain the plugin bindings.
# Cloning both known plugins above avoids TPM's non-atomic installation path.
candidate_session="sbx-deploy-plugin-setup-$$-$RANDOM"
/usr/bin/tmux new-session -d -s "$candidate_session" || die 'Cannot start tmux plugin setup.'
setup_session=$candidate_session
/usr/bin/tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$plugin_dir/" ||
    die 'Cannot set the tmux plugin path.'
# run-shell parses a shell command; quote HOME there to support spaces in paths.
/usr/bin/tmux run-shell '"$HOME/.tmux/plugins/tpm/tpm"' || die 'Cannot load TPM plugins.'
all_bindings=$(/usr/bin/tmux list-keys -T prefix) || die 'Cannot inspect tmux bindings.'
for binding in /tpm/bindings/install_plugins /tmux-resurrect/scripts/{save,restore}.sh; do
    [[ "$all_bindings" == *"$binding"* ]] || die "Plugin binding did not load: $binding"
done

tmux_wrapper="$HOME/.local/bin/tmux"
wrapper_contents() {
    cat <<'TMUX_WRAPPER'
#!/bin/sh
LC_ALL=C.utf8 exec /usr/bin/tmux -u "$@"
TMUX_WRAPPER
}

# Never replace an existing wrapper. A hard link publishes the complete executable
# atomically and fails if another process creates the destination first.
if exists "$tmux_wrapper"; then
    [[ -f "$tmux_wrapper" && -x "$tmux_wrapper" ]] &&
        cmp -s -- "$tmux_wrapper" <(wrapper_contents) ||
        die "Existing tmux wrapper differs or is unusable: $tmux_wrapper"
else
    (
        mkdir -p -- "${tmux_wrapper%/*}"
        staged=$(mktemp -- "$tmux_wrapper.tmp.XXXXXX")
        trap 'rm -f -- "$staged"' EXIT
        wrapper_contents > "$staged"
        chmod 755 -- "$staged"
        ln -T -- "$staged" "$tmux_wrapper"
    )
fi

ensure_bash_path() (
    local startup_file=$1 staged= marker='# SBX Deploy: put the tmux wrapper on PATH'
    trap 'if [[ -n "$staged" ]]; then rm -f -- "$staged"; fi' EXIT
    if exists "$startup_file"; then
        [[ -f "$startup_file" && -r "$startup_file" ]] || die "Cannot read: $startup_file"
        grep -Fxq -- "$marker" "$startup_file" && return 0
        [[ ! -L "$startup_file" ]] || die "Update the startup file symlink target: $startup_file"
    fi
    # Stage the entire append so interruption cannot leave a marker without its
    # code. Preserve existing contents, permissions, and ownership when present.
    staged=$(mktemp -- "$startup_file.tmp.XXXXXX")
    if exists "$startup_file"; then
        cp -p -- "$startup_file" "$staged"
    fi
    cat >> "$staged" <<'SBX_BASH_PATH'

# SBX Deploy: put the tmux wrapper on PATH
case $- in
    *i*)
        case ${PATH-} in
            "$HOME/.local/bin"|"$HOME/.local/bin:"*) ;;
            *) export PATH="$HOME/.local/bin${PATH:+:$PATH}" ;;
        esac
        ;;
esac
SBX_BASH_PATH
    mv -fT -- "$staged" "$startup_file"
    staged=
)
ensure_bash_path "$HOME/.bashrc"
# Bash login shells read only the first readable login startup file.
login_file="$HOME/.profile"
for candidate in "$HOME/.bash_profile" "$HOME/.bash_login"; do
    if [[ -f "$candidate" && -r "$candidate" ]]; then
        login_file=$candidate
        break
    fi
done
ensure_bash_path "$login_file"

# Preserve all existing system aliases and add the managed block only once.
global_bashrc=/etc/bash.bashrc
[[ -f "$global_bashrc" && -r "$global_bashrc" ]] || die "Cannot read: $global_bashrc"
if ! grep -Fxq -- '# SBX Deploy: custom system aliases' "$global_bashrc"; then
    cat -- "$global_bashrc" > "$work_dir/bash.bashrc"
    cat >> "$work_dir/bash.bashrc" <<'SBX_ALIASES'

# SBX Deploy: custom system aliases
# Custom aliases for ansible control
alias playbook='ansible-playbook'
alias playtest='ansible-playbook -C'
alias playsyntax='ansible-playbook --syntax-check'

# List active permissions on a file or folder
alias lperms='stat -c "%a %n"'

# Make a password hash
alias makepass='python3 -c "from passlib.hash import sha512_crypt; import getpass; print(sha512_crypt.using(rounds=5000).hash(getpass.getpass()))"'

# Strip comments and blank lines from a configuration file
alias configcat='grep -Ev "^$|^#"'

# Netstat aliases
alias netstat-numeric='netstat -tulpn'
alias netstat-names='netstat -tulp'
SBX_ALIASES
    replace_system_file "$work_dir/bash.bashrc" "$global_bashrc"
fi

cat <<'SBX_NEXT_STEPS'

Setup complete. tmux-resurrect and the UTF-8 tmux wrapper are installed.

New interactive Bash shells pick up the wrapper and system aliases
automatically. In an already-open Bash shell, run this before starting tmux:
    export PATH="$HOME/.local/bin:$PATH"; hash -r
    source /etc/bash.bashrc

Start tmux by running: tmux
To reload the configuration in an existing session:
    tmux source-file /etc/tmux.conf
To verify the locale, start a fresh tmux server and run locale charmap
inside it. Expected output: UTF-8.
SBX_NEXT_STEPS
)
