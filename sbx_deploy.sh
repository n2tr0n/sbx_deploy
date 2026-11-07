#!/usr/bin/env bash
# Features, in execution order (keep current):
# 1. Save ~/sbx_deploy.sh with owner execute permission; back up differing copies.
# 2. Show the SBX banner and verbose-mode command.
# 3. Align stage/result/details columns; show APT names and retain five private logs.
# 4. Validate paths; install missing packages (cmatrix alone omits recommends).
# 5. Download missing TPM and tmux-resurrect checkouts atomically.
# 6. Back up/update tmux configuration; load plugins and verify bindings.
# 7. Install UTF-8 tmux/btop wrappers, Bash PATH entries, and system aliases once.
# 8. Install abbreviated-path Bash prompts: red root, green other users.
# 9. Upgrade existing /home/agent/.opencode/bin/opencode once per binary checksum.
# 10. Clean up and summarize; refresh pasted/sourced interactive shells on success.
#    Child-shell runs show manual reload instructions.
#
# Paste the ENTIRE file into Bash; rerun with: bash ~/sbx_deploy.sh
# Save before starting the installer, including when this entire file is pasted
# into Bash. The quoted payload is data until the complete outer block is parsed.
{
(
set -euo pipefail
exec 6<&0
# Capture invocation before entering a function/eval, which changes BASH_SOURCE.
sbx_child_shell=false
if [[ ${BASH_SOURCE[0]:-} == "$0" || ( -z ${BASH_SOURCE[0]:-} && $- != *i* ) ]]; then
    sbx_child_shell=true
fi
sbx_save_and_run() {
    local payload target="$HOME/sbx_deploy.sh" staged= backup= candidate compare_status mode
    IFS= read -r -d '' payload || :
    if [[ -L $target || ( -e $target && ! -f $target ) ]]; then
        printf 'SBX Deploy: cannot save installer over a symlink or non-regular file: %s\n' "$target" >&2
        exit 1
    fi
    staged=$(umask 077; mktemp -- "$target.tmp.XXXXXX")
    trap 'if [[ -n $staged ]]; then rm -f -- "$staged"; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    # Recreate this wrapper around the literal payload. declare -f gives the
    # saved copy the same save-first behavior without relying on shell history,
    # a source filename, or an exported variable from the calling shell.
    {
        # The saved copy needs only a brief operational header.
        cat <<'SBX_SAVED_HEADER'
#!/usr/bin/env bash
# Install sandbox tools, tmux plugins/configuration, shell helpers, and prompts;
# upgrade existing OpenCode; skip completed work and retain five run logs.
# Paste the ENTIRE file into Bash; rerun with: bash ~/sbx_deploy.sh
SBX_SAVED_HEADER
        printf '{\n(\nset -euo pipefail\nexec 6<&0\n'
        printf '%s\n' 'sbx_child_shell=false' \
            'if [[ ${BASH_SOURCE[0]:-} == "$0" || ( -z ${BASH_SOURCE[0]:-} && $- != *i* ) ]]; then' \
            '    sbx_child_shell=true' 'fi'
        declare -f sbx_save_and_run
        printf "sbx_save_and_run <<'SBX_DEPLOY_PAYLOAD'\n"
        printf '%s' "$payload"
        printf 'SBX_DEPLOY_PAYLOAD\n'
        cat <<'SBX_CALLER_REFRESH'
)
# Keep the installer unguarded: an if/&& around it would disable errexit inside.
# This enclosing brace is parsed before execution, preserving pasted input.
case $? in
    0)
        if [[ $- == *i* && ${BASH_SOURCE[0]:-} != "$0" ]]; then
            case ${PATH-} in
                "$HOME/.local/bin"|"$HOME/.local/bin:"*) ;;
                *) export PATH="$HOME/.local/bin${PATH:+:$PATH}" ;;
            esac
            hash -r
            if source /etc/bash.bashrc; then
                printf '\nShell refreshed.\n\n'
            else
                printf '\nWARN Could not reload shell setup; run: source /etc/bash.bashrc\n' >&2
            fi
        fi
        ;;
    *) (exit "$?") ;; # Preserve failure status without exiting a pasted shell.
esac
}
SBX_CALLER_REFRESH
    } > "$staged"
    if [[ -f $target ]]; then
        if cmp -s -- "$target" "$staged"; then
            # Avoid a metadata write when the owner execute bit is already set.
            mode=$(stat -c '%a' -- "$target")
            (( (8#$mode & 0100) != 0 )) || chmod u+x -- "$target"
            rm -f -- "$staged"
            staged=
        else
            compare_status=$?
            if (( compare_status != 1 )); then
                printf 'SBX Deploy: cannot compare saved installer: %s\n' "$target" >&2
                exit "$compare_status"
            fi
            # Reuse an identical backup if an earlier save was interrupted.
            for candidate in "$target".bak.*; do
                if [[ -f $candidate && ! -L $candidate ]] && cmp -s -- "$target" "$candidate"; then
                    backup=$candidate
                    break
                fi
            done
            if [[ -z $backup ]]; then
                backup=$(umask 077; mktemp -- "$target.bak.XXXXXX")
                if cp -p -- "$target" "$backup"; then
                    printf 'Saved previous installer to %s\n' "$backup" >&2
                else
                    compare_status=$?
                    rm -f -- "$backup" || :
                    exit "$compare_status"
                fi
            fi
        fi
    fi
    if [[ -n $staged ]]; then
        chmod u+x -- "$staged"
        mv -fT -- "$staged" "$target"
        staged=
    fi
    trap - EXIT INT TERM
    # Execute only the literal installer payload, avoiding recursive execution
    # of the saved wrapper. The payload keeps its own isolated subshell/traps.
    eval "$payload" <&6 6<&-
}
sbx_save_and_run <<'SBX_DEPLOY_PAYLOAD'
(
set -euo pipefail

# FIGlet Slant by Glenn Chappell, pre-rendered at full width.
cat <<'SBX_BANNER'

  .-----------------------------------------------------------------------.
 /__________  N I T R O N   P R E S E N T S  ______________________________\
 \_  _                                                                 _  _/
   \/     _______   _______  ___   ___                                  \/
   /\    /  _____/ /  __   \ \  \ /  /                                  /\
  /  \   \____  \ /   _   <   \  V  /      .:: S B X   D E P L O Y ::. /  \
  \  /  /————/  //  /_/   /   / / \ \                                  \  /
   \/  /_______//________/___/_/___\_\________________________________  \/
   /\  \__  Nitron's Deployment Script for SBX v-0.1a              __/  /\
 _/  \____\_______________________________________________________/____/  \_
 \_________________________________________________________________________/

SBX_BANNER

printf 'To run in verbose mode, SBX_VERBOSE=1 bash ~/sbx_deploy.sh\n\n'

conf=/etc/tmux.conf
plugin_dir="$HOME/.tmux/plugins"
tpm_dir="$plugin_dir/tpm"
resurrect_dir="$plugin_dir/tmux-resurrect"
resurrect_plugin="$resurrect_dir/resurrect.tmux"

exists() { [[ -e "$1" || -L "$1" ]]; }

# Reporting uses separate terminal descriptors so command output stays in the
# log. Everything remains inside the pasted subshell, including these redirects.
exec 3>&1 4>&2
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/sbx-deploy"
if ! (umask 077; mkdir -p -m 700 -- "$log_dir") ||
   [[ -L "$log_dir" || ! -O "$log_dir" ]] ||
   [[ $(stat -c '%a' -- "$log_dir") != 700 ]]; then
    printf 'SBX Deploy: cannot initialize private log directory: %s\n' "$log_dir" >&4
    exit 1
fi
if ! log_file=$(umask 077; mktemp -- "$log_dir/run-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX.log"); then
    printf 'SBX Deploy: cannot create a log in %s\n' "$log_dir" >&4
    exit 1
fi
if ! work_dir=$(umask 077; mktemp -d); then
    printf 'SBX Deploy: cannot create a temporary workspace. Log: %s\n' "$log_file" >&4
    exit 1
fi

verbose=${SBX_VERBOSE:-0}
animated=false
green= amber= red= muted= reset=
separator=' | '
spinner_frames=('|' '/' '-' '\')
locale_name=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ ${locale_name,,} == *utf-8* || ${locale_name,,} == *utf8* ]]; then
    separator=' · '
    spinner_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
fi
if [[ -t 3 && ${TERM:-dumb} != dumb ]]; then
    [[ $verbose == 1 ]] || animated=true
    if [[ -z ${NO_COLOR+x} ]]; then
        green=$'\033[32m' amber=$'\033[33m' red=$'\033[31m'
        muted=$'\033[2m' reset=$'\033[0m'
    fi
fi
started_at=$SECONDS
stage= operation= spinner_pid= tee_pid= setup_session=
apt_status_file= apt_output_file=
stage_started=$SECONDS
operation_offset=0
changed_count=0 unchanged_count=0 verified_count=0 warning_count=0
finishing=false

# Pad plain text separately from ANSI colors so all terminal modes share the
# same columns. Callers choose a newline or an in-place spinner refresh.
report_row() {
    printf '  %-18s | %s%-7s%s | %s' "$1" "${4-}" "$2" "$reset" "$3" >&3
}
stop_spinner() {
    if [[ -n $spinner_pid ]]; then
        kill "$spinner_pid" 2>/dev/null || :
        wait "$spinner_pid" 2>/dev/null || :
        spinner_pid=
        printf '\r\033[2K' >&3
    fi
}
# Drain verbose output at operation boundaries so log offsets and result rows
# cannot overtake output still buffered in tee. These are never guarded calls to
# installation functions: errexit remains active in the actual work below.
drain_output() {
    if [[ -n $tee_pid ]]; then
        exec >> "$log_file" 2>&1
        if ! wait "$tee_pid"; then
            warn 'Live output logging did not finish successfully.'
        fi
        tee_pid=
    fi
}
capture_output() {
    if [[ $verbose == 1 ]]; then
        exec > >(tee -a -- "$log_file" >&3) 2>&1
        tee_pid=$!
    else
        exec >> "$log_file" 2>&1
    fi
}
start_spinner() {
    if "$animated" && ! "$finishing"; then
        (
            trap - EXIT
            trap 'exit 0' INT TERM
            frame=0
            progress_text=$operation
            while :; do
                if [[ -n $apt_status_file && -r $apt_status_file ]]; then
                    # Status-Fd reports download counts, not package names.
                    # APT's Get: rows identify the latest transfer started;
                    # downloads from different mirrors can overlap.
                    download_item=
                    if [[ -n $apt_output_file && -r $apt_output_file ]]; then
                        download_item=$(tail -n 80 -- "$apt_output_file" | awk '
                            /^Get:[0-9]+ / {
                                sub(/[[:space:]]+\[[^]]*\][[:space:]]*$/, "")
                                # Archive rows end in package, arch, version.
                                # Index rows end in e.g. Packages or InRelease.
                                if (NF >= 7) name = $(NF - 2)
                                else name = $NF
                            }
                            END { print name }
                        ')
                    fi
                    # APT writes structured progress separately from its normal
                    # output. Ignore partial/unknown records and retain the last
                    # valid update until the next one arrives.
                    while IFS=: read -r kind item percent description; do
                        # Multiarch package names can contain an extra colon.
                        if [[ $kind == pmstatus && $percent == [a-z]* && $description == *:* ]]; then
                            item="$item:$percent"
                            percent=${description%%:*}
                            description=${description#*:}
                        fi
                        [[ $percent =~ ^[0-9]+([.][0-9]+)?$ ]] || continue
                        case $kind in
                            dlstatus) progress_text="${percent%%.*}% Download ${download_item:-files}" ;;
                            # Put the package before the description so it stays
                            # visible when the compact progress row is clipped.
                            pmstatus) progress_text="${percent%%.*}% Install $item - $description" ;;
                        esac
                    done < <(tail -n 8 -- "$apt_status_file")
                fi
                printf '\r\033[2K' >&3
                report_row "$stage" RUNNING \
                    "${progress_text:0:45} (${spinner_frames[frame]} $((SECONDS - stage_started))s)" "$muted"
                frame=$(( (frame + 1) % ${#spinner_frames[@]} ))
                sleep 0.15
            done
        ) &
        spinner_pid=$!
    fi
}
stage_operation() {
    stop_spinner
    drain_output
    operation=$1
    printf '\nOperation: %s\n' "$operation" >> "$log_file"
    operation_offset=$(wc -c < "$log_file")
    if ! "$animated"; then
        report_row "$stage" RUNNING "$operation" "$muted"
        printf '\n' >&3
    fi
    capture_output
    start_spinner
}
stage_begin() {
    stage=$1
    stage_started=$SECONDS
    rm -f -- "$work_dir/changed" "$work_dir/backup" "$work_dir/reason"
    printf '\nStage: %s\n' "$stage" >> "$log_file"
    stage_operation "$2"
}
stage_done() {
    local outcome=$1 message=$2 result=UPDATED color=$green
    stop_spinner
    drain_output
    case $outcome in
        changed) changed_count=$((changed_count + 1)) ;;
        unchanged)
            unchanged_count=$((unchanged_count + 1))
            result=SKIPPED color=$muted ;;
        verified)
            verified_count=$((verified_count + 1))
            result=CHECKED ;;
    esac
    report_row "$stage" "$result" "$message" "$color"
    printf '\n' >&3
    printf 'Result: %s - %s\n' "$outcome" "$message" >> "$log_file"
    stage=
    capture_output
}
warn() {
    stop_spinner
    warning_count=$((warning_count + 1))
    report_row "${stage:-Setup}" WARNING "$*" "$amber"
    printf '\n' >&3
    printf 'Warning: %s\n' "$*" >> "$log_file"
    [[ -z $stage ]] || start_spinner
}
die() {
    local status=$?
    status=${2:-$status}
    (( status != 0 )) || status=1
    printf '%s\n' "$1" > "$work_dir/reason"
    printf 'SBX Deploy: %s\n' "$1" >&2
    exit "$status"
}
cleanup_installer() {
    if [[ -n $setup_session ]] &&
       /usr/bin/tmux has-session -t "=$setup_session" 2>/dev/null; then
        /usr/bin/tmux kill-session -t "=$setup_session" ||
            warn "Could not remove temporary tmux session: $setup_session"
    fi
}
finish_installer() {
    local status=$? reason
    trap - EXIT INT TERM
    set +e
    finishing=true
    stop_spinner
    drain_output
    if (( status != 0 )); then
        reason="${operation:-Setup} failed (exit $status)"
        [[ ! -s $work_dir/reason ]] || reason=$(< "$work_dir/reason")
        case $status in
            130|143) reason="Interrupted during ${stage:-setup}" ;;
        esac
        # Snapshot only the failed operation, before cleanup adds more output.
        tail -c "+$((operation_offset + 1))" -- "$log_file" | tail -n 8 > "$work_dir/excerpt"
    fi
    cleanup_installer
    exec 1>&3 2>&4
    if (( status != 0 )); then
        report_row "${stage:-Setup}" FAILED "$reason" "$red"
        printf '\n' >&3
        printf 'Failed: %s\n' "$reason" >> "$log_file"
        printf '\n' >&3
        cat -- "$work_dir/excerpt" >&3
    fi
    rm -rf -- "$work_dir" || warn 'Could not remove the installer temporary workspace.'
    if (( status == 0 )); then
        printf '\nComplete%s%s stages changed%s%s unchanged%s%s verified%s%ss\n' \
            "$separator" "$changed_count" "$separator" "$unchanged_count" \
            "$separator" "$verified_count" "$separator" "$((SECONDS - started_at))" | tee -a -- "$log_file" >&3
        if "$sbx_child_shell" || [[ $- != *i* ]]; then
            warn 'Child-shell run: reload your calling shell or open a new shell to use wrappers, aliases, and prompts.'
            cat >&3 <<'SBX_NEXT_STEPS'

Reload your shell (installer changes ran in a subshell):
  export PATH="$HOME/.local/bin:$PATH"; hash -r
  source /etc/bash.bashrc

SBX_NEXT_STEPS
        fi
    fi
    if (( warning_count )); then
        printf '\n%s warning(s); see the log for details.\n' "$warning_count" >&3
    fi
    printf '\nLog: %s\n' "$log_file" >&3
    exit "$status"
}
trap finish_installer EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
report_row Stage Result Details "$muted"
printf '\n  -------------------+---------+------------------------------------------\n' >&3
capture_output

stage_begin 'Checks' 'Checking existing setup'
# Only our exact log filename format is eligible for retention. Always keep this
# run plus the four newest other logs, even when timestamps happen to tie.
retained=0
if find "$log_dir" -maxdepth 1 -type f -printf '%T@ %f\0' |
   sort -z -nr > "$work_dir/logs"; then
    while IFS= read -r -d '' entry; do
        log_name=${entry#* }
        [[ $log_name =~ ^run-[0-9]{8}T[0-9]{6}Z-[[:alnum:]]{6}\.log$ ]] || continue
        [[ $log_dir/$log_name != "$log_file" ]] || continue
        retained=$((retained + 1))
        if (( retained > 4 )); then
            rm -f -- "$log_dir/$log_name" || warn "Could not remove old log: $log_name"
        fi
    done < "$work_dir/logs"
else
    warn 'Could not list previous logs; log retention skipped.'
fi

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
stage_done verified 'Paths validated'

# Check local dpkg state before doing any network work. Keep cmatrix separate
# because only that package should omit recommended dependencies. Python 3 and
# passlib support the makepass alias installed below.
stage_begin 'Packages' 'Checking installed packages'
package_installed() {
    [[ $(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) == installed ]]
}
required_packages=(
    ansible strace ltrace plocate atop htop btop nmon nmap git net-tools
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
    package_count=${#missing_packages[@]}
    if "$missing_cmatrix"; then package_count=$((package_count + 1)); fi
    apt_status_file="$work_dir/apt-status"
    apt_output_file="$work_dir/apt-output"
    run_apt() {
        local message=$1
        shift
        stop_spinner
        (umask 077; : > "$apt_status_file"; : > "$apt_output_file")
        stage_operation "$message"
        # sudo normally closes extra descriptors. Open the progress descriptor
        # after elevation, using positional arguments to preserve path quoting.
        # Call this helper directly so errexit propagates an apt failure.
        run_as_root sh -c '
            exec 5> "$1"
            shift
            exec apt-get -o APT::Status-Fd=5 "$@"
        ' sbx-apt "$apt_status_file" "$@" | tee -- "$apt_output_file"
    }
    run_apt 'Refreshing package lists' update
    if (( ${#missing_packages[@]} )); then
        run_apt "Installing ${#missing_packages[@]} missing packages" install -y "${missing_packages[@]}"
    fi
    if "$missing_cmatrix"; then
        run_apt 'Installing cmatrix' install -y --no-install-recommends cmatrix
    fi
    stage_done changed "Installed $package_count missing packages"
    apt_status_file= apt_output_file=
else
    stage_done unchanged 'Already installed'
fi

stage_begin 'Plugins' 'Checking TPM and tmux-resurrect'
clone_plugin() (
    local repository=$1 destination=$2 staging_dir
    exists "$destination" && return 0
    mkdir -p -- "$plugin_dir"
    staging_dir=$(mktemp -d -- "$plugin_dir/.plugin-stage.XXXXXX")
    trap 'rm -rf -- "$staging_dir"' EXIT
    # Same-filesystem publication; never merge into or replace an existing path.
    git clone --depth 1 "https://github.com/tmux-plugins/$repository" "$staging_dir/checkout"
    mv -nT -- "$staging_dir/checkout" "$destination"
    # mv -n can succeed without publishing if another run created the target.
    if [[ ! -e $staging_dir/checkout ]]; then
        touch -- "$work_dir/changed"
    fi
)
if ! tpm_ready; then
    stage_operation 'Downloading TPM'
    clone_plugin tpm "$tpm_dir"
fi
if ! resurrect_ready; then
    stage_operation 'Downloading tmux-resurrect'
    clone_plugin tmux-resurrect "$resurrect_dir"
fi
tpm_ready || die "TPM checkout is unusable: $tpm_dir"
resurrect_ready || die "tmux-resurrect checkout is unusable: $resurrect_dir"
if [[ -e $work_dir/changed ]]; then
    stage_done changed 'Installed missing plugins'
else
    stage_done unchanged 'Already installed'
fi

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
        (( compare_status == 1 )) || die "Cannot compare configuration: $target" "$compare_status"
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
            if run_as_root cp -p -- "$target" "$backup"; then
                :
            else
                compare_status=$?
                run_as_root rm -f -- "$backup" || :
                die "Cannot back up configuration: $target" "$compare_status"
            fi
            printf 'Saved previous configuration to %s\n' "$backup"
        fi
        touch -- "$work_dir/backup"
    fi
    run_as_root mv -fT -- "$staged" "$target"
    staged=
    touch -- "$work_dir/changed"
)

stage_begin 'tmux configuration' 'Checking supplied configuration'
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
if [[ -e $work_dir/changed ]]; then
    if [[ -e $work_dir/backup ]]; then
        stage_done changed 'Updated; backup saved'
    else
        stage_done changed 'Installed'
    fi
else
    stage_done unchanged 'Configuration matches'
fi

# Use the current/default server so existing sessions gain the plugin bindings.
# Cloning both known plugins above avoids TPM's non-atomic installation path.
stage_begin 'Plugin activation' 'Loading plugins and verifying bindings'
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
stage_done verified 'Plugin bindings loaded'

stage_begin 'Shell setup' 'Checking wrappers, PATH, and aliases'
tmux_wrapper="$HOME/.local/bin/tmux"
wrapper_contents() {
    cat <<'TMUX_WRAPPER'
#!/bin/sh
LC_ALL=C.utf8 exec /usr/bin/tmux -u "$@"
TMUX_WRAPPER
}
btop_wrapper_contents() {
    cat <<'BTOP_WRAPPER'
#!/bin/sh
LC_ALL=C.UTF-8 exec /usr/bin/btop "$@"
BTOP_WRAPPER
}

# Never replace an existing wrapper. A hard link publishes the complete executable
# atomically and fails if another process creates the destination first.
ensure_wrapper() (
    local target=$1 contents=$2 staged=
    trap 'if [[ -n "$staged" ]]; then rm -f -- "$staged"; fi' EXIT
    if exists "$target"; then
        [[ -f "$target" && -x "$target" ]] &&
            cmp -s -- "$target" <("$contents") ||
            die "Existing wrapper differs or is unusable: $target"
    else
        mkdir -p -- "${target%/*}"
        staged=$(mktemp -- "$target.tmp.XXXXXX")
        "$contents" > "$staged"
        chmod 755 -- "$staged"
        ln -T -- "$staged" "$target"
        touch -- "$work_dir/changed"
    fi
)
ensure_wrapper "$tmux_wrapper" wrapper_contents
ensure_wrapper "$HOME/.local/bin/btop" btop_wrapper_contents

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
    touch -- "$work_dir/changed"
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

if [[ -e $work_dir/changed ]]; then
    stage_done changed 'Updated wrappers, PATH, or aliases'
else
    stage_done unchanged 'Wrappers, PATH, and aliases match'
fi

stage_begin 'Custom prompts' 'Checking global Bash prompts'
if ! grep -Fxq -- '# SBX Deploy: custom system prompts' "$global_bashrc"; then
    cat -- "$global_bashrc" > "$work_dir/bash-prompts.bashrc"
    cat >> "$work_dir/bash-prompts.bashrc" <<'SBX_PROMPTS'

# SBX Deploy: custom system prompts
case $- in
    *i*)
        # Abbreviate every parent to its first character; keep the last name.
        # Bash string operations preserve spaces/globs and avoid external tools.
        short_path() {
            local path=${PWD#/} component result=
            while [[ $path == */* ]]; do
                component=${path%%/*}
                path=${path#*/}
                [[ -z $component ]] || result+="/${component:0:1}"
            done
            printf '%s/%s' "$result" "$path"
        }
        _sbx_prompt() {
            local status=$?
            if (( EUID == 0 )); then
                PS1='${debian_chroot:+($debian_chroot)}\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]$(short_path)\[\033[00m\]\$ '
            else
                PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]$(short_path)\[\033[00m\]\$ '
            fi
            return "$status"
        }
        # Personal .bashrc defaults run after /etc/bash.bashrc. Set PS1 just
        # before display, preserving existing command hooks and their status.
        _sbx_register_prompt() {
            local command
            for command in "${PROMPT_COMMAND[@]}"; do
                [[ $command != _sbx_prompt ]] || return 0
            done
            PROMPT_COMMAND=("${PROMPT_COMMAND[@]}" _sbx_prompt)
        }
        _sbx_register_prompt
        unset -f _sbx_register_prompt
        ;;
esac
SBX_PROMPTS
    replace_system_file "$work_dir/bash-prompts.bashrc" "$global_bashrc"
fi
if [[ -e $work_dir/changed ]]; then
    stage_done changed 'Installed root and global prompts'
else
    stage_done unchanged 'Prompts already installed'
fi

stage_begin 'OpenCode' 'Checking or upgrading existing installation'
opencode_binary=/home/agent/.opencode/bin/opencode
upgrade_opencode() (
    local state_file="$log_dir/opencode-upgrade.sha256" before after staged=
    trap 'if [[ -n $staged ]]; then rm -f -- "$staged"; fi' EXIT
    [[ -f $opencode_binary && -x $opencode_binary ]] ||
        die "OpenCode is not an executable regular file: $opencode_binary"
    if exists "$state_file"; then
        [[ -f $state_file && ! -L $state_file && -r $state_file ]] ||
            die "Cannot read OpenCode upgrade state: $state_file"
    fi
    before=$(sha256sum -- "$opencode_binary")
    # A completed upgrade is remembered locally, avoiding network checks on an
    # identical rerun. A changed binary or missing state triggers another check.
    if [[ -f $state_file && $(< "$state_file") == "$before" ]]; then
        return 0
    fi
    "$opencode_binary" upgrade --method curl
    [[ -f $opencode_binary && -x $opencode_binary ]] ||
        die "OpenCode upgrade left no usable executable: $opencode_binary"
    after=$(sha256sum -- "$opencode_binary")
    # Publish completion only after success. Interrupted/failed upgrades remain
    # eligible for retry; the marker itself is replaced atomically.
    staged=$(umask 077; mktemp -- "$state_file.tmp.XXXXXX")
    printf '%s\n' "$after" > "$staged"
    mv -fT -- "$staged" "$state_file"
    staged=
    touch -- "$work_dir/opencode-checked"
    if [[ $before != "$after" ]]; then
        touch -- "$work_dir/changed"
    fi
)
if ! exists "$opencode_binary"; then
    stage_done unchanged 'Not installed'
else
    upgrade_opencode
    if [[ -e $work_dir/changed ]]; then
        stage_done changed 'Upgraded existing installation'
    elif [[ -e $work_dir/opencode-checked ]]; then
        stage_done verified 'Already up to date'
    else
        stage_done unchanged 'Upgrade already completed for this binary'
    fi
fi
)
SBX_DEPLOY_PAYLOAD
)
# Keep the installer unguarded: an if/&& around it would disable errexit inside.
# This enclosing brace is parsed before execution, preserving pasted input.
case $? in
    0)
        if [[ $- == *i* && ${BASH_SOURCE[0]:-} != "$0" ]]; then
            case ${PATH-} in
                "$HOME/.local/bin"|"$HOME/.local/bin:"*) ;;
                *) export PATH="$HOME/.local/bin${PATH:+:$PATH}" ;;
            esac
            hash -r
            if source /etc/bash.bashrc; then
                printf '\nShell refreshed.\n\n'
            else
                printf '\nWARN Could not reload shell setup; run: source /etc/bash.bashrc\n' >&2
            fi
        fi
        ;;
    *) (exit "$?") ;; # Preserve failure status without exiting a pasted shell.
esac
}
