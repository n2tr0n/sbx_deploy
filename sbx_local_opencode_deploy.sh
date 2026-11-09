#!/usr/bin/env bash
# Target: local Docker Sandboxes (sbx) of type opencode.
# Install tools. Configure OpenCode, Codex, shell, and tmux. Preserve user edits and logins.
# Paste the entire file into sandbox Bash with passwordless sudo. Confirm the hostname.
# Rerun: bash ~/sbx_local_opencode_deploy.sh
# --tmux-redeploy restores supplied tmux settings. SBX_CHECK_AUTH=1 rechecks authentication.
# SBX_VERBOSE=1 shows live output. Stop on errors; clean up after interruption.
{
(
set -euo pipefail
exec 6<&0
sbx_script_args=("$@")
# Record the invocation before a function or eval changes BASH_SOURCE.
sbx_child_shell=false
if [[ ${BASH_SOURCE[0]:-} == "$0" || ( -z ${BASH_SOURCE[0]:-} && $- != *i* ) ]]; then
    sbx_child_shell=true
fi
sbx_save_and_run() {
    local payload target="$HOME/sbx_local_opencode_deploy.sh" staged= backup= candidate compare_status mode original= was_present=false
    local tmux_redeploy=false option
    if "$sbx_child_shell"; then
        for option in "${sbx_script_args[@]}"; do
            case $option in
                --tmux-redeploy) tmux_redeploy=true ;;
                *) printf 'Usage: bash ~/sbx_local_opencode_deploy.sh [--tmux-redeploy]\n' >&2; exit 2 ;;
            esac
        done
    fi
    IFS= read -r -d '' payload || :
    command -v flock >/dev/null 2>&1 || {
        printf 'SBX Deploy: flock is required (install util-linux first).\n' >&2
        exit 1
    }
    local deploy_lock=/run/sbx-deploy.lock
    local -a lock_root=()
    (( EUID == 0 )) || lock_root=(sudo -n)
    # /run is root-owned. Create without overwriting. Never follow a symlink.
    "${lock_root[@]}" sh -c '
        if [ ! -e "$1" ] && [ ! -L "$1" ]; then
            (umask 022; set -C; : > "$1")
        fi
        test -f "$1" && test ! -L "$1" && test "$(stat -c %u "$1")" = 0
    ' sbx-deploy-lock "$deploy_lock" || { printf 'SBX Deploy: cannot prepare root-owned /run/sbx-deploy.lock.\n' >&2; exit 1; }
    exec 9<"$deploy_lock"
    if ! flock -n 9; then
        printf 'SBX Deploy: another deployment or local Codex configuration update is running; retry after it finishes.\n' >&2
        exit 1
    fi
    if [[ -L $target || ( -e $target && ! -f $target ) ]]; then
        printf 'SBX Deploy: cannot save installer over a symlink or non-regular file: %s\n' "$target" >&2
        exit 1
    fi
    trap 'if [[ -n $staged ]]; then rm -f -- "$staged"; fi; if [[ -n $original ]]; then rm -f -- "$original"; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    original=$(umask 077; mktemp -- "$target.input.XXXXXX")
    if [[ -f $target ]]; then cp -p -- "$target" "$original"; was_present=true; fi
    staged=$(umask 077; mktemp -- "$target.tmp.XXXXXX")
    # Recreate the wrapper around the literal payload with declare -f.
    # The saved copy needs no shell history, source filename, or exported variable.
    {
        # The saved copy needs only a brief operational header.
        cat <<'SBX_SAVED_HEADER'
#!/usr/bin/env bash
# Target: local Docker Sandboxes (sbx) of type opencode.
# Install tools. Configure OpenCode, Codex, shell, and tmux. Preserve user edits and logins.
# Paste the entire file into sandbox Bash with passwordless sudo. Confirm the hostname.
# Rerun: bash ~/sbx_local_opencode_deploy.sh
# --tmux-redeploy restores supplied tmux settings. SBX_CHECK_AUTH=1 rechecks authentication.
# SBX_VERBOSE=1 shows live output. Stop on errors; clean up after interruption.
SBX_SAVED_HEADER
        printf '{\n(\nset -euo pipefail\nexec 6<&0\nsbx_script_args=("$@")\n'
        printf '%s\n' 'sbx_child_shell=false' \
            'if [[ ${BASH_SOURCE[0]:-} == "$0" || ( -z ${BASH_SOURCE[0]:-} && $- != *i* ) ]]; then' \
            '    sbx_child_shell=true' 'fi'
        declare -f sbx_save_and_run
        printf "sbx_save_and_run <<'SBX_DEPLOY_PAYLOAD'\n"
        printf '%s' "$payload"
        printf 'SBX_DEPLOY_PAYLOAD\n'
        cat <<'SBX_CALLER_REFRESH'
)
# Do not guard the installer with if or &&. That disables errexit inside.
# Bash parses the outer brace before execution to protect pasted input.
case $? in
    0)
        if [[ $- == *i* && ${BASH_SOURCE[0]:-} != "$0" ]]; then
            case ${PATH-} in
                "$HOME/.local/bin"|"$HOME/.local/bin:"*) ;;
                *) export PATH="$HOME/.local/bin${PATH:+:$PATH}" ;;
            esac
            hash -r
            if source /etc/bash.bashrc; then
                :
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
        if "$was_present"; then
            [[ ! -L $target ]] && cmp -s -- "$target" "$original" || {
                printf 'SBX Deploy: saved installer changed concurrently: %s\n' "$target" >&2; exit 1;
            }
            mv -fT -- "$staged" "$target"
        else
            ln -T -- "$staged" "$target"
            rm -f -- "$staged"
        fi
        staged=
    fi
    rm -f -- "$original"
    original=
    # Keep traps and the lock through child cleanup, including after interruption.
    # Run only the literal payload. It has its own subshell and traps.
    # Only this parent holds the lock. Close its descriptor in all descendants.
    (exec 9>&-; eval "$payload" <&6 6<&-)
    trap - EXIT INT TERM
}
sbx_save_and_run <<'SBX_DEPLOY_PAYLOAD'
(
set -euo pipefail

# Define shared values before generating helpers. Installed helpers contain a copy.
main_model=gpt-6.1-sol
subagent_model=gpt-6-luna
oauth_access=oai-oat01-proxy-managed
oauth_refresh=oai-ort01-proxy-managed
oauth_provider=sbx-chatgpt
oauth_base_url=https://chatgpt.com/backend-api/codex
api_base_url=https://api.openai.com/v1
mcp_gateway_url=http://mcp-gateway.docker.internal/mcp
opencode_binary=/home/agent/.opencode/bin/opencode
codex_install_url=https://chatgpt.com/codex/install.sh
codex_device_url=https://auth.openai.com/codex/device
download_seconds=60
install_seconds=300
credential_seconds=30
version_seconds=15
kill_seconds=5

# Keep terminal presentation independent from captured command output.
exec 3>&1 4>&2
verbose=${SBX_VERBOSE:-0}
animated=false
green= amber= red= muted= reset= bold_amber= bold_red= banner_white= banner_bright_green= banner_dark_green= banner_grey=
utf8=false
spinner_frames=('|' '/' '-' '\')
locale_name=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ ${locale_name,,} == *utf-8* || ${locale_name,,} == *utf8* ]]; then
    utf8=true
    spinner_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
fi
if [[ -t 3 && ${TERM:-dumb} != dumb ]]; then
    [[ $verbose == 1 ]] || animated=true
    if [[ -z ${NO_COLOR+x} ]]; then
        green=$'\033[32m' amber=$'\033[33m' red=$'\033[31m'
        muted=$'\033[90m' reset=$'\033[0m'
        bold_amber=$'\033[1;93m' bold_red=$'\033[1;91m'
        banner_grey=$'\033[38;5;245m'
        banner_white=$'\033[1;37m'
        banner_bright_green=$'\033[1;92m'
        banner_dark_green=$'\033[38;5;22m'
    fi
fi

# FIGlet Slant by Glenn Chappell, pre-rendered at full width.
banner_line=0
while IFS= read -r line; do
    case $banner_line in
        2)
            label='N i T R O N   P R E S E N T S'
            line=${line/"$label"/"$banner_bright_green$label$banner_grey"}
            ;;
        7)
            # Non-UTF-8 locales can count em dashes as bytes.
            # Use the X to locate the color boundary without splitting this row.
            logo_tail='  /  \  \'
            line="${line:0:6}$green${line:6}"
            line=${line/"$logo_tail"/"$logo_tail$banner_grey"}
            ;;
        4|5|6|8)
            line="${line:0:6}$green${line:6:31}$banner_grey${line:37}"
            if (( banner_line == 6 )); then
                label='.:: S B X   D E P L O Y ::.'
                accent="$green.:: $banner_white"'S B X   D E P L O Y'"$green ::.$banner_grey"
                line=${line/"$label"/"$accent"}
            fi
            ;;
        9)
            label="Nitron's Deployment Script for SBX v0.4a"
            line=${line/"$label"/"$banner_dark_green$label$banner_grey"}
            ;;
    esac
    printf '%s%s%s\n' "$banner_grey" "$line" "$reset" >&3
    banner_line=$((banner_line + 1))
done <<'SBX_BANNER'

  .-----------------------------------------------------------------------.
 /__________  N i T R O N   P R E S E N T S  ______________________________\
 \_  _                                                                 _  _/
   \/     _______   _______ ___   ___                                   \/
   /\    /  _____/ /  __   \\  \ /  /                                   /\
  /  \   \____  \ /  /_/  <  \  V  /    .:: S B X   D E P L O Y ::.    /  \
  \  /  —————/  //  /_/   /  /  \  \                                   \  /
   \/  /_______//________/__/__/_\__\_________________________________  \/
   /\  \__  Nitron's Deployment Script for SBX v0.4a               __/  /\
 _/  \____\_______________________________________________________/____/  \_
 \_________________________________________________________________________/

SBX_BANNER

# Read from the terminal, never from a pasted payload or piped shell commands.
# Save before confirmation. A refusal skips deployment and returns 130.
# The outer wrapper then skips the calling shell refresh.
confirmation_fd=
if [[ -t 0 ]]; then
    confirmation_fd=0
elif { exec 7</dev/tty; } 2>/dev/null; then
    confirmation_fd=7
fi
if [[ -z $confirmation_fd ]]; then
    printf 'No terminal input; deployment cancelled.\n' >&3
    exit 130
fi
confirmation_warning='[!]'
if "$utf8"; then confirmation_warning='⚠️'; fi
while :; do
    printf '%s%s Are you sure you want to run this script on %s%s%s? [y/N]%s ' \
        "$bold_amber" "$confirmation_warning" "$bold_red" "${HOSTNAME:-unknown}" "$bold_amber" "$reset" >&3
    if ! IFS= read -r -u "$confirmation_fd" confirmation; then
        printf '\nDeployment cancelled.\n' >&3
        exit 130
    fi
    case ${confirmation,,} in
        y|yes) break ;;
        n|no|'') printf 'Deployment cancelled.\n' >&3; exit 130 ;;
        *) printf 'Please enter y or n.\n' >&3 ;;
    esac
done
[[ $confirmation_fd != 7 ]] || exec 7<&-
printf '\n' >&3

conf=/etc/tmux.conf
plugin_dir="$HOME/.tmux/plugins"
tpm_dir="$plugin_dir/tpm"
resurrect_dir="$plugin_dir/tmux-resurrect"
resurrect_plugin="$resurrect_dir/resurrect.tmux"

exists() { [[ -e "$1" || -L "$1" ]]; }

# Use separate terminal descriptors to keep command output in the log.
# Keep redirects inside the pasted subshell.
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

started_at=$SECONDS
stage= operation= spinner_pid= tee_pid= setup_session= auth_cache_staged=
apt_status_file= apt_output_file=
webtop_status=
stage_started=$SECONDS
operation_offset=0
changed_count=0 unchanged_count=0 verified_count=0 warning_count=0
finishing=false
github_auth_status='not checked'
openai_auth_status='not checked'
declare -a issue_keys=() issue_titles=() issue_details=() issue_actions=()

# Count each issue once, regardless of its recovery steps.
record_issue() {
    local key=$1 title=$2 detail=$3 actions=${4-} i
    for ((i=0; i<${#issue_keys[@]}; i++)); do
        [[ ${issue_keys[i]} != "$key" ]] || return 0
    done
    issue_keys+=("$key") issue_titles+=("$title")
    issue_details+=("$detail") issue_actions+=("$actions")
    warning_count=${#issue_keys[@]}
    printf 'Warning: %s - %s\n%s\n' "$title" "$detail" "$actions" >> "$log_file"
}

# Write plain text to the private log. Apply styling only to terminal output.
report_line() {
    printf '%s%s%s\n' "${2-}" "$1" "$reset" >&3
    printf '%s\n' "$1" >> "$log_file"
}
summary_layout() {
    summary_width=${COLUMNS:-}
    if [[ -t 3 && ${TERM:-dumb} != dumb && ! $summary_width =~ ^[0-9]+$ ]]; then
        summary_width=$(tput cols 2>/dev/null) || summary_width=80
    fi
    [[ $summary_width =~ ^[0-9]{1,3}$ ]] || summary_width=80
    summary_width=$((10#$summary_width))
    (( summary_width > 0 )) || summary_width=80
    (( summary_width <= 80 )) || summary_width=80
    box_open=false
    box_vertical='|' box_horizontal='-' box_tl='+' box_tr='+' box_bl='+' box_br='+'
    command_bullet='-'
    if "$utf8"; then
        box_vertical='│' box_horizontal='─' box_tl='┌' box_tr='┐' box_bl='└' box_br='┘'
        command_bullet='•'
    fi
}
summary_layout
box_rule() {
    local rule
    printf -v rule '%*s' "$((summary_width - 2))" ''
    rule=${rule// /$box_horizontal}
    report_line "$1$rule$2" "$muted"
}
summary_begin() {
    report_line ''
    box_open=false
    if (( summary_width >= 60 )); then
        box_rule "$box_tl" "$box_tr"
        box_open=true
    fi
    summary_text "$1" "${2:-$muted}"
}
summary_end() {
    if "$box_open"; then box_rule "$box_bl" "$box_br"; fi
    box_open=false
}
summary_text() {
    local text=$1 color=${2-} kind=${3:-prose} width=$((summary_width - 4)) word line='' padding
    # Commands, paths and diagnostic excerpts must remain intact and copyable.
    if [[ $kind == literal ]]; then
        if "$box_open" && (( ${#text} <= width )); then
            printf -v padding '%*s' "$((width - ${#text}))" ''
            printf '%s%s%s %s%s%s%s %s%s%s\n' "$muted" "$box_vertical" "$reset" "$color" "$text" "$reset" "$padding" "$muted" "$box_vertical" "$reset" >&3
            if [[ -n ${log_file-} ]]; then printf '%s\n' "$text" >> "$log_file"; fi
        else
            report_line "  $text" "$color"
        fi
        return
    fi
    # Split prose on spaces using read, never pathname expansion.
    local -a words=()
    read -r -a words <<< "$text"
    for word in "${words[@]}"; do
        if [[ -n $line ]] && (( ${#line} + ${#word} + 1 > width )); then
            summary_text "$line" "$color" literal
            line=''
        fi
        line+="${line:+ }$word"
    done
    summary_text "$line" "$color" literal
}
summary_command() {
    local command="$command_bullet $1" description=${2-}
    if [[ -z $description ]]; then
        summary_text "$command" '' literal
    elif (( ${#command} + ${#description} + 4 <= summary_width - 4 )); then
        summary_text "$command    $description" '' literal
    else
        summary_text "$command" '' literal
        summary_text "$description" "$muted"
    fi
}

# Pad text separately from ANSI colors to align columns in all terminal modes.
# Callers select a newline or an in-place spinner update.
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
# Flush tee output between operations to keep log offsets and result rows aligned.
# These calls do not guard installation functions. errexit stays active below.
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
                    # APT writes structured progress separately from normal output.
                    # Ignore incomplete or unknown records. Keep the last valid update.
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
        attention) result=ACTION color=$amber ;;
    esac
    report_row "$stage" "$result" "$message" "$color"
    printf '\n' >&3
    printf 'Result: %s - %s\n' "$outcome" "$message" >> "$log_file"
    stage=
    capture_output
}
warn() {
    stop_spinner
    record_issue "warning:$*" "${stage:-Setup}" "$*"
    report_row "${stage:-Setup}" WARNING "$*" "$amber"
    printf '\n' >&3
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
    if [[ -n $auth_cache_staged ]]; then
        rm -f -- "$auth_cache_staged" || warn 'Could not remove temporary credential-check cache.'
    fi
    if [[ -n $setup_session ]] &&
       /usr/bin/tmux has-session -t "=$setup_session" 2>/dev/null; then
        /usr/bin/tmux kill-session -t "=$setup_session" ||
            warn "Could not remove temporary tmux session: $setup_session"
    fi
}
finish_installer() {
    local status=$? reason host_sandbox_arg line i action heading desktop_color
    trap - EXIT INT TERM
    set +e
    finishing=true
    stop_spinner
    drain_output
    if (( status != 0 )); then
        reason="${operation:-Setup} failed (exit $status)"
        [[ ! -s $work_dir/reason ]] || reason=$(< "$work_dir/reason")
        case $status in
            124) reason="${operation:-Setup} exceeded its unattended deadline (exit 124)" ;;
            137) reason="${operation:-Setup} was forcibly terminated (exit 137)" ;;
            130|143) reason="Interrupted during ${stage:-setup}" ;;
        esac
        # Snapshot only the failed operation, before cleanup adds more output.
        tail -c "+$((operation_offset + 1))" -- "$log_file" | tail -n 8 > "$work_dir/excerpt"
    fi
    cleanup_installer
    exec 1>&3 2>&4
    if (( status != 0 )); then
        heading="SETUP FAILED (exit $status)"
        case $status in
            130|143) heading="SETUP INTERRUPTED (exit $status)" ;;
        esac
        summary_begin "$heading" "$red"
        summary_text "${stage:-Setup}: $reason"
        summary_end
        while IFS= read -r line || [[ -n $line ]]; do
            summary_text "$line" '' literal
        done < "$work_dir/excerpt"
    fi
    rm -rf -- "$work_dir" || warn 'Could not remove the installer temporary workspace.'
    if (( status == 0 )); then
        heading='SETUP COMPLETE'
        if (( warning_count )); then
            heading='SETUP COMPLETE - ATTENTION NEEDED'
        fi
        summary_begin "$heading" "$green"
        summary_text ''
        summary_text "Stages: $changed_count changed | $unchanged_count unchanged | $verified_count verified"
        summary_text "Warnings: $warning_count | Elapsed: $((SECONDS - started_at))s"
        summary_text "GitHub: $github_auth_status"
        summary_text "OpenAI: $openai_auth_status"
        summary_text ''
        summary_text 'OpenAI verification covers model-list access, not inference.' "$muted"
        summary_end
    fi
    if (( warning_count )); then
        heading='ACTION NEEDED'
        if (( warning_count > 1 )); then heading="ACTION NEEDED - $warning_count issues"; fi
        summary_begin "$heading" "$amber"
        for ((i=0; i<${#issue_keys[@]}; i++)); do
            summary_text ''
            heading=${issue_titles[i]}
            if (( warning_count > 1 )); then heading="$((i + 1)). $heading"; fi
            summary_text "$heading" "$amber"
            summary_text "${issue_details[i]}"
            while IFS= read -r action; do
                if [[ $action == '  '* ]]; then
                    # Do not wrap commands. Keep box padding out of commands wider than the box.
                    summary_command "${action#  }"
                elif [[ -n $action ]]; then
                    summary_text ''
                    if [[ $action == *: ]]; then
                        summary_text "$action" "$amber"
                    else
                        summary_text "$action" "$muted"
                    fi
                fi
            done <<< "${issue_actions[i]}"
        done
        summary_text ''
        summary_end
    fi
    if (( status == 0 )); then
        host_sandbox_arg=${HOSTNAME:-}
        if [[ ! $host_sandbox_arg =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
            host_sandbox_arg='$sandboxName'
        fi
        if [[ -n $webtop_status ]]; then
            desktop_color=$green
            [[ $webtop_status != stopped ]] || desktop_color=$amber
            summary_begin "WEBTOP - $webtop_status" "$desktop_color"
            summary_text ''
            summary_text 'Open in your browser:'
            summary_command 'https://127.0.0.1:3001/'
            summary_text 'Accept the self-signed certificate.' "$muted"
            summary_text 'Use your mapped host port if different.' "$muted"
            if [[ $webtop_status == stopped ]]; then
                summary_text ''
                summary_text 'Sandbox Bash - start the desktop:'
                summary_command 'docker start webtop'
            fi
            summary_text ''
            summary_text 'Windows PowerShell - check sandbox and ports:'
            summary_command 'sbx ls'
            if [[ $host_sandbox_arg == '$sandboxName' ]]; then
                summary_command '$sandboxName = Read-Host "Sandbox name"'
            fi
            summary_command "sbx ports $host_sandbox_arg"
            summary_text ''
            summary_text 'Publish only if the mapping is absent:'
            summary_command "sbx ports $host_sandbox_arg --publish 127.0.0.1:3001:3001"
            summary_text ''
            summary_end
        fi
        summary_begin 'SANDBOX BASH - QUICK REFERENCE' "$green"
        summary_text ''
        if "$sbx_child_shell" || [[ $- != *i* ]]; then
            summary_text 'Reload your calling shell, or open a new shell, before using helpers:'
            summary_text 'export PATH="$HOME/.local/bin:$PATH"; hash -r' '' literal
            summary_text 'source /etc/bash.bashrc' '' literal
        fi
        summary_command check_credentials 'Live authentication and credential sources'
        summary_command check_mcp 'Discover gateway servers and tools'
        if [[ -n $webtop_status ]]; then
            summary_command desktop 'Desktop status and reconnection help'
        fi
        summary_text ''
        summary_end
        summary_begin 'VS CODE TUNNEL' "$green"
        summary_text ''
        summary_text 'Sandbox Bash - set up remote access:'
        summary_command vscode_tunnel
        summary_text 'Accepts the server license terms. Complete browser sign-in if requested.' "$muted"
        summary_text 'Copies the device code and opens the sign-in page on the host.' "$muted"
        summary_text 'Enables the background tunnel with its saved VS Code login.' "$muted"
        summary_command vscode_status 'Check the connection'
        summary_command vscode_disable 'Stop and disable automatic startup'
        summary_text ''
        summary_text 'Windows PowerShell - attach the startup kit once:'
        summary_command "sbx kit add $host_sandbox_arg ./kits/vscode-tunnel"
        summary_text 'Run from the SBX Deploy repository. Kit attachment restarts the sandbox.' "$muted"
        summary_text 'Attach before tunnel setup. See HOST_SETUP_WIN.md for checks.' "$muted"
        if (( EUID != 1000 )); then
            summary_text "For this caller, add --kit-arg user=$EUID to the host command." "$amber"
        fi
        summary_text ''
        summary_text 'Connect from Windows VS Code:'
        summary_text 'VS Code > Remote Tunnels: Connect to Tunnel' "$muted"
        summary_text ''
        summary_end
        summary_begin 'POST DEPLOYMENT COMMANDS' "$green"
        summary_text ''
        summary_text 'Windows PowerShell: run in this order for a new sandbox.'
        summary_command 'sbx daemon restart'
        if [[ $host_sandbox_arg == '$sandboxName' && -z $webtop_status ]]; then
            summary_text '$sandboxName = Read-Host "Sandbox name"' '' literal
        fi
        summary_command "sbx mcp load context7 --sandbox $host_sandbox_arg"
        summary_text ''
        summary_text 'Restart may interrupt sessions.' "$muted"
        summary_end
    fi
    report_line ''
    report_line "Log: $log_file"
    report_line ''
    exit "$status"
}
trap finish_installer EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
report_line 'To run in verbose mode, SBX_VERBOSE=1 bash ~/sbx_local_opencode_deploy.sh'
report_line "Log: $log_file"
report_line ''
report_row Stage Result Details "$muted"
printf '\n  -------------------+---------+------------------------------------------\n' >&3
capture_output

stage_begin 'Checks' 'Checking existing setup'
# Apply retention only to the exact deployment log filename format.
# Keep this run and the four newest other logs, including when timestamps match.
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

# Do not overwrite user-owned or incomplete checkouts.
# Stage new clones to prevent incomplete checkouts after interrupted downloads.
if exists "$tpm_dir"; then
    tpm_ready || die "Existing TPM path is unusable: $tpm_dir"
fi
if exists "$resurrect_dir"; then
    resurrect_ready || die "Existing tmux-resurrect path is unusable: $resurrect_dir"
fi
[[ -d /etc && ! -L /etc && ! -L $conf && ( ! -e $conf || -f $conf ) ]] ||
    die "Unsafe tmux configuration path: $conf; preserve it and restore a regular file or leave it absent before retrying."
stage_done verified 'Paths validated'

# Check local dpkg state before network access.
# Only cmatrix omits recommended dependencies. Python 3 and passlib support makepass.
stage_begin 'Packages' 'Checking installed packages'
package_installed() {
    [[ $(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) == installed ]]
}
required_packages=(
    ansible strace ltrace plocate atop htop btop nmon nmap git net-tools
    unzip bind9-utils rsync curl lynx tcpdump vim whois sudo tmux mtr
    libaa-bin python3 python3-passlib python3-tomlkit rsyslog logrotate procps util-linux
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
        # Open the progress descriptor after sudo closes extra descriptors.
        # Use positional arguments to preserve path quoting.
        # Call directly so errexit stops on APT failure.
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

stage_begin 'Codex' 'Locating existing executable'
install_codex() {
    local binary status PATH="$HOME/.local/bin:$PATH"
    # Also find a previous standalone install before the calling shell reloads.
    # Supplying PATH prevents the upstream installer from editing shell files.
    export PATH
    binary=$(type -P codex || :)
    if [[ -n $binary ]]; then
        [[ -f $binary && -x $binary ]] || die "Codex is not a usable executable: $binary"
    else
        # Never overwrite an unrelated file or dangling user-created symlink.
        if exists "$HOME/.local/bin/codex"; then
            die "Existing Codex path is unusable; repair it before retrying: $HOME/.local/bin/codex"
        fi
        stage_operation "Downloading Codex installer (${download_seconds}s limit)"
        # Download completely before executing; never run a partial response.
        if timeout --kill-after="${kill_seconds}s" "${download_seconds}s" \
            curl -fsSL --connect-timeout 10 --max-time "$download_seconds" \
            -o "$work_dir/codex-install.sh" "$codex_install_url"; then
            :
        else
            status=$?
            die 'Codex installer download failed; check sandbox network/proxy access.' "$status"
        fi
        stage_operation 'Downloading/installing Codex'
        # Disable launch prompts. Keep pasted input away from the installer.
        # timeout also limits child downloads. Upstream stages releases; interruptions are retryable.
        if timeout --kill-after="${kill_seconds}s" "${install_seconds}s" env CODEX_NON_INTERACTIVE=1 \
            CODEX_INSTALL_DIR="$HOME/.local/bin" sh "$work_dir/codex-install.sh" </dev/null; then
            :
        else
            status=$?
            case $status in
                124|137) die 'Codex installation exceeded 5 minutes; check network/proxy access and retry.' "$status" ;;
                *) die 'Codex installation failed; see installer output below.' "$status" ;;
            esac
        fi
        binary="$HOME/.local/bin/codex"
        [[ -f $binary && -x $binary ]] || die 'Codex installation left no usable executable.'
        touch -- "$work_dir/changed"
    fi
    stage_operation "Checking Codex version (${version_seconds}s limit)"
    printf 'Codex executable: %s\n' "$binary"
    if timeout --kill-after="${kill_seconds}s" "${version_seconds}s" "$binary" --version </dev/null; then
        :
    else
        status=$?
        case $status in
            124|137) die "Codex version check timed out: $binary" "$status" ;;
            *) die "Codex version check failed: $binary" "$status" ;;
        esac
    fi
}
install_codex
if [[ -e $work_dir/changed ]]; then
    stage_done changed 'Installed Codex CLI'
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
    timeout --kill-after="${kill_seconds}s" "${install_seconds}s" git clone --depth 1 "https://github.com/tmux-plugins/$repository" "$staging_dir/checkout"
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

# Copy before editing. Compare immediately before publication to detect concurrent edits.
# External editors do not use the deployment lock.
snapshot_file() {
    local target=$1 original=$2 present=$3
    if exists "$target"; then
        [[ -f $target && ! -L $target ]] || die "Unsafe configuration path: $target"
        run_as_root cat -- "$target" > "$original"
        printf True > "$present"
    else
        : > "$original"
        printf False > "$present"
    fi
}
assert_input() {
    local target=$1 original=$2 present=$3
    if [[ $(< "$present") == True ]]; then
        [[ -f $target && ! -L $target ]] && run_as_root cmp -s -- "$target" "$original" ||
            die "Configuration changed during deployment: $target; review it and retry."
    else
        ! exists "$target" || die "Configuration appeared during deployment: $target; review it and retry."
    fi
}

# Replace system configuration atomically. Skip matching files. Reject symlinks.
# Preserve metadata in backups before renaming. Reuse identical backups after interruption.
replace_system_file() (
    local source=$1 target=$2 mode=${3-} staged= backup compare_status
    local original=${4:-} present=${5:-} snapshot=
    if [[ -z $original ]]; then
        snapshot=$(mktemp -d -- "$work_dir/input.XXXXXX")
        original="$snapshot/input" present="$snapshot/exists"
        snapshot_file "$target" "$original" "$present"
    fi
    assert_input "$target" "$original" "$present"
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

    # Elevate staging and publication for existing root-owned directories in HOME.
    # Preserve directory ownership.
    staged=$(run_as_root mktemp -- "$target.tmp.XXXXXX")
    if exists "$target"; then
        run_as_root cp -p -- "$target" "$staged"
    elif [[ $target == "$HOME/"* ]]; then
        # New user files belong to the caller even when root creates the stage.
        run_as_root chown "$(id -u):$(id -g)" -- "$staged"
    fi
    run_as_root tee "$staged" < "$source" >/dev/null
    if [[ -n "$mode" ]]; then
        run_as_root chmod "$mode" -- "$staged"
    elif [[ $(< "$present") == False && $target != "$HOME/"* ]]; then
        run_as_root chmod 644 -- "$staged"
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
    assert_input "$target" "$original" "$present"
    if [[ $(< "$present") == True ]]; then
        run_as_root mv -fT -- "$staged" "$target"
    else
        run_as_root ln -T -- "$staged" "$target"
        run_as_root rm -f -- "$staged"
    fi
    staged=
    touch -- "$work_dir/changed"
)

# Determine ownership from content for generated helpers and tmux configuration.
# Record private baselines only after successful file publication.
managed_conflict() {
    if [[ $1 == /etc/tmux.conf ]]; then
        die "Unrecognized or edited tmux configuration: $1. File preserved. Review it, then run bash ~/sbx_local_opencode_deploy.sh --tmux-redeploy to back it up and restore the supplied configuration."
    fi
    die "Managed file differs: $1. Preserve/rename it, or restore the baseline in $log_dir/managed after reviewing your edits, then rerun. No force overwrite is available."
}
legacy_managed_digest() {
    case "$1:$2" in
        # Supplied tmux.conf in 4944f0d through 59c9042. Keep shipped digests for upgrades.
        tmux.conf:766687fbd89ed67c0a60d8cc63651a5ebdb56876a2caffbab271a098101b8f6f) return 0 ;;
        tmux:4e5cdc439742a730df166fd7d41c858a8b3cb9f6a15f2ac6de7222851a5c0b7a) return 0 ;;
        btop:a1ff64e6c696f59d1e01c71287229fdb297aadfba7e0bea1ba7ef998f88a15f3) return 0 ;;
        sbx_check_credentials:333d4ece17931876ed9897cd1dfac2e7369e85274a1595855c22767d47b407f0) return 0 ;;
        sbx_check_mcp:c4495b3399eb27eaac14456f651db94b28746bd318bcb1789dbdc6b68a48ada6) return 0 ;;
        desktop:ada75803a1f16eb59055b164a2c67950804d0443a6ad9b0783e117c343b0286c) return 0 ;;
        xclip:269c1c506653650990fa365875c855962f394527ddf9e90ffdad7307f98ca57d) return 0 ;;
        sbx-local-syslog:6da86d19e5cd8f6ae96443998d520964c9c04499e1456175430b5497d2834d9a) return 0 ;;
        00-sbx-local-format.conf:795fcba8de73a2d8e2f98868348919ec3a8cc3cd66b22702498192b3129d2a52) return 0 ;;
        auth-openai-tty:6cc6524d12186c9cc7e4a64ac8827eaf313acd3af607b51eaf20b44b34b6f7a2) return 0 ;;
        auth-codex-openai-browser-tty:0f4374cf7633b86966ae1161215876a50fda1b57e0181ff328a6ee261808fab0) return 0 ;;
        *) return 1 ;;
    esac
}
managed_preflight() {
    local target=$1 desired=$2 mode=${3:-} baseline digest key
    if exists "$log_dir/managed"; then
        [[ -d $log_dir/managed && ! -L $log_dir/managed && -O $log_dir/managed ]] || managed_conflict "$log_dir/managed"
    fi
    key=$(printf '%s' "$target" | sha256sum); key=${key%% *}
    baseline="$log_dir/managed/$key"
    if exists "$baseline"; then
        [[ -f $baseline && ! -L $baseline && -O $baseline ]] || managed_conflict "$baseline"
    fi
    if exists "$target"; then
        [[ -f $target && ! -L $target ]] || managed_conflict "$target"
        if [[ $mode == 755 && ! -x $target ]]; then
            die "Managed helper is not executable: $target; review its permissions and restore execute permission, then retry."
        fi
        if run_as_root cmp -s -- "$target" "$desired"; then return 0; fi
        if [[ ${4:-} == --tmux-redeploy ]]; then return 0; fi
        if [[ -f $baseline ]] && run_as_root cmp -s -- "$target" "$baseline"; then return 0; fi
        [[ ! -f $baseline ]] || managed_conflict "$target"
        digest=$(run_as_root sha256sum -- "$target"); digest=${digest%% *}
        legacy_managed_digest "${target##*/}" "$digest" || managed_conflict "$target"
    fi
}
install_managed_file() (
    local target=$1 desired=$2 mode=${3:-755} baseline key staged=
    trap 'if [[ -n $staged ]]; then rm -f -- "$staged"; fi' EXIT
    local input_dir
    input_dir=$(mktemp -d -- "$work_dir/managed-input.XXXXXX")
    snapshot_file "$target" "$input_dir/input" "$input_dir/exists"
    managed_preflight "$target" "$desired" "$mode" "${4:-}"
    # tmux can already match without a baseline. Do not write state on that path.
    if [[ ${4:-} == --skip-matching || ${4:-} == --tmux-redeploy ]] && cmp -s -- "$input_dir/input" "$desired" &&
       [[ $(< "$input_dir/exists") == True ]]; then
        assert_input "$target" "$input_dir/input" "$input_dir/exists"
        return 0
    fi
    # Create user helper directories without sudo if the nearest existing ancestor is writable.
    # Use elevated staging for older root-owned directories.
    local parent=${target%/*} ancestor=${target%/*}
    while ! exists "$ancestor"; do
        ancestor=${ancestor%/*}
        ancestor=${ancestor:-/}
    done
    if [[ $target == "$HOME/"* && -d $ancestor && -w $ancestor ]]; then
        mkdir -p -- "$parent"
    else
        run_as_root mkdir -p -- "$parent"
    fi
    replace_system_file "$desired" "$target" "$mode" "$input_dir/input" "$input_dir/exists"
    key=$(printf '%s' "$target" | sha256sum); key=${key%% *}
    baseline="$log_dir/managed/$key"
    if [[ -f $baseline ]] && cmp -s -- "$baseline" "$desired"; then return 0; fi
    [[ ! -L $log_dir/managed ]] || managed_conflict "$log_dir/managed"
    (umask 077; mkdir -p -m 700 -- "$log_dir/managed")
    staged=$(umask 077; mktemp -- "$baseline.tmp.XXXXXX")
    cat -- "$desired" > "$staged"
    mv -fT -- "$staged" "$baseline"
    staged=
)
# Queue the shell group: all ownership and migration checks finish before writes.
managed_targets=() managed_sources=() managed_modes=()
queue_managed_file() {
    managed_targets+=("$1") managed_sources+=("$2") managed_modes+=("${3:-755}")
}
queue_helper() {
    local target=$1 contents=$2 desired
    desired="$work_dir/helper-${#managed_targets[@]}"
    "$contents" > "$desired"
    queue_managed_file "$target" "$desired"
}

stage_begin 'VS Code' 'Checking headless CLI'
vscode_binary="$HOME/.local/lib/sbx-deploy/vscode-code"
if exists "$vscode_binary"; then
    [[ -f $vscode_binary && -x $vscode_binary && ! -L $vscode_binary ]] ||
        die "VS Code CLI path is unusable: $vscode_binary; preserve it, then restore a regular executable or move it before retrying."
else
    case $(uname -m) in
        x86_64) vscode_platform=cli-linux-x64 ;;
        aarch64|arm64) vscode_platform=cli-linux-arm64 ;;
        *) die 'The headless VS Code CLI requires Linux x64 or ARM64.' ;;
    esac
    stage_operation "Downloading VS Code CLI (${download_seconds}s limit)"
    if timeout --kill-after="${kill_seconds}s" "${download_seconds}s" \
        curl -fsSL --connect-timeout 10 --max-time "$download_seconds" \
        -o "$work_dir/vscode-cli.tar.gz" \
        "https://update.code.visualstudio.com/latest/$vscode_platform/stable"; then
        :
    else
        status=$?
        die 'VS Code CLI download failed; check sandbox network/proxy access.' "$status"
    fi
    # Extract only the executable into the private workspace. Ignore archive paths.
    stage_operation 'Checking downloaded VS Code CLI'
    timeout --kill-after="${kill_seconds}s" "${install_seconds}s" \
        tar -xOf "$work_dir/vscode-cli.tar.gz" code > "$work_dir/vscode-code"
    chmod 755 -- "$work_dir/vscode-code"
    timeout --kill-after="${kill_seconds}s" "${version_seconds}s" \
        "$work_dir/vscode-code" --version </dev/null
    timeout --kill-after="${kill_seconds}s" "${version_seconds}s" \
        "$work_dir/vscode-code" tunnel --help </dev/null >/dev/null
    # Publish only a complete, checked binary. Keep user authentication unchanged.
    install_managed_file "$vscode_binary" "$work_dir/vscode-code"
fi
stage_operation 'Checking installed VS Code CLI'
timeout --kill-after="${kill_seconds}s" "${version_seconds}s" \
    "$vscode_binary" --version </dev/null
if [[ -e $work_dir/changed ]]; then
    stage_done changed 'Installed headless CLI; set up with vscode_tunnel'
else
    stage_done unchanged 'CLI present; tunnel login and settings preserved'
fi

# Add facility.severity tags to sandbox syslog. Preserve routing and rotation rules.
# Start with the first Bash session after restart. Earlier boot messages can be missed.
# https://docs.docker.com/ai/sandboxes/usage/#set-environment-variables
stage_begin 'Local syslog' 'Checking logging and restart hook'
[[ -f /etc/logrotate.conf && -f /etc/logrotate.d/rsyslog ]] ||
    die 'Missing distro logrotate configuration; restore the logrotate/rsyslog package files.'
cat > "$work_dir/rsyslog-format.conf" <<'SBX_SYSLOG_FORMAT'
# SBX Deploy: local syslog format; retain the existing routing and permissions.
# Explicit templates in user rules still take precedence.
template(name="SBXLocalFormat" type="string"
    string="%timegenerated:::date-rfc3339% %hostname% %syslogfacility-text%.%syslogseverity-text% %syslogtag%%msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n")
$ActionFileDefaultTemplate SBXLocalFormat
SBX_SYSLOG_FORMAT
managed_preflight /etc/rsyslog.d/00-sbx-local-format.conf "$work_dir/rsyslog-format.conf"
cat > "$work_dir/sbx-local-syslog.sh" <<'SBX_SYSLOG_START'
#!/bin/bash
# SBX Deploy: local rsyslog and rotation without systemd or cron.
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
if (( EUID != 0 )); then
    exec sudo -n /usr/bin/env -u BASH_ENV /bin/bash /usr/local/sbin/sbx-local-syslog "$@"
fi
rotate_logs() {
    # Share the distro state/lock and policy with any existing scheduler.
    # Reopen even after partial rotation failure; preserve the original error.
    local status=0 hup_status
    logrotate /etc/logrotate.conf || status=$?
    if pkill -HUP -x rsyslogd; then
        :
    else
        hup_status=$?
        (( status != 0 )) || status=$hup_status
    fi
    return "$status"
}
if [[ ${1-} == --rotate ]]; then
    # Descriptor 8 carries the lifetime lock from the launcher.
    while :; do
        sleep 3600 8>&-
        if output=$(rotate_logs 2>&1); then
            :
        else
            logger -p daemon.err -t sbx-logrotate -- "Rotation failed: $output"
        fi
    done
fi
exec 9>>/run/sbx-local-syslog.lock
# Shell startup catches failure and continues. Deployment must still stop on failure.
if flock --wait 5 --conflict-exit-code 75 9; then
    :
else
    lock_status=$?
    if (( lock_status == 75 )); then
        printf 'SBX logging: startup lock is busy after 5 seconds; logging setup skipped.\n' >&2
    fi
    exit "$lock_status"
fi
# Comparing with the daemon's PID file also recovers an interrupted install
# that published the format but did not yet restart rsyslog.
if [[ /etc/rsyslog.d/00-sbx-local-format.conf -nt /run/rsyslogd.pid ]] ||
   ! pgrep -x rsyslogd >/dev/null; then
    rsyslogd -N1
    if pgrep -x rsyslogd >/dev/null; then
        start-stop-daemon --stop --retry TERM/10 --exec /usr/sbin/rsyslogd
    fi
    rsyslogd
    pgrep -x rsyslogd >/dev/null
    printf 'Started rsyslog\n'
fi
# The lock survives in the worker, not its sleep children. Repeated startup
# invocations and installer runs reuse the existing worker without rotating.
exec 8>>/run/sbx-logrotate.lock
if flock -n 8; then
    # Start retries before the first pass, so a rotation error cannot leave
    # logging without a scheduler. The first error still fails this invocation.
    nohup /usr/bin/env -u BASH_ENV /bin/bash /usr/local/sbin/sbx-local-syslog --rotate \
        </dev/null >/dev/null 2>&1 3>&- 4>&- 6>&- 9>&- &
    worker=$!
    sleep 0.1
    kill -0 "$worker"
    printf 'Started logrotate worker\n'
    rotate_logs
fi
SBX_SYSLOG_START
[[ -d /usr/local/sbin ]] || run_as_root install -d -m 755 /usr/local/sbin
managed_preflight /usr/local/sbin/sbx-local-syslog "$work_dir/sbx-local-syslog.sh" 755
queue_managed_file /etc/rsyslog.d/00-sbx-local-format.conf "$work_dir/rsyslog-format.conf" 644
queue_managed_file /usr/local/sbin/sbx-local-syslog "$work_dir/sbx-local-syslog.sh"
stage_done verified 'Logging ownership checked; publish with shell setup'

stage_begin 'tmux configuration' 'Checking supplied configuration'
# Preserve the supplied tmux configuration. The quoted heredoc prevents early expansion
# of HOME and tmux formats.
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
# Preserve changed user settings by default. To back them up and restore these
# defaults explicitly, run: bash ~/sbx_local_opencode_deploy.sh --tmux-redeploy
# The flag does not bypass path safety or concurrent-edit checks.
tmux_option=--skip-matching
if "$tmux_redeploy"; then tmux_option=--tmux-redeploy; fi
install_managed_file "$conf" "$new_conf" 644 "$tmux_option"
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

# Get the plugin's save directory, including custom options and legacy/XDG defaults.
# Preserve the supplied tmux configuration.
stage_begin 'tmux snapshot' 'Checking saved resurrect state'
resurrect_state_dir=$(
    # Third-party helpers are not written for nounset.
    set +u
    source "$resurrect_dir/scripts/helpers.sh" || exit $?
    resurrect_dir
) || die 'Cannot resolve the tmux-resurrect save directory.'
[[ $resurrect_state_dir == /* ]] || die 'tmux-resurrect save directory must be absolute.'
seed_resurrect_snapshot() (
    local state_dir=$1 seed=tmux_resurrect_sbx_default.txt saved staged= compare_status snapshot
    trap 'if [[ -n $staged ]]; then rm -f -- "$staged"; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if exists "$state_dir"; then
        [[ -d $state_dir && ! -L $state_dir ]] ||
            die "Cannot seed a symlink or non-directory resurrect path: $state_dir"
    fi
    # Preserve dangling links, empty saves, and old snapshots without a last link.
    # Recover only the exact deployment seed filename.
    exists "$state_dir/last" && return 0
    for saved in "$state_dir"/tmux_resurrect_*.txt; do
        if exists "$saved" && [[ $saved != "$state_dir/$seed" ]]; then
            return 0
        fi
    done
    # Six single-pane windows: cli, cli2, opencode, codex, btop, log.
    # Use the caller's home directory. Preserve tabs and trailing fields during paste.
    snapshot=$(base64 --decode <<'SBX_RESURRECT_SNAPSHOT'
cGFuZQkwCTAJMAk6CTAJc2J4CTpfX1NCWF9IT01FX18JMQliYXNoCToKcGFuZQkwCTEJMAk6CTAJ
c2J4CTpfX1NCWF9IT01FX18JMQliYXNoCToKcGFuZQkwCTIJMAk6CTAJc2J4CTpfX1NCWF9IT01F
X18JMQliYXNoCToKcGFuZQkwCTMJMAk6CTAJc2J4CTpfX1NCWF9IT01FX18JMQliYXNoCToKcGFu
ZQkwCTQJMQk6KgkwCXNieAk6X19TQlhfSE9NRV9fCTEJYnRvcAk6L3Vzci9iaW4vYnRvcApwYW5l
CTAJNQkwCTotCTAJc2J4CTpfX1NCWF9IT01FX18JMQliYXNoCToKd2luZG93CTAJMAk6Y2xpCTAJ
OgliMTFkLDIwOXg1MCwwLDAsMAlvZmYKd2luZG93CTAJMQk6Y2xpMgkwCToJYjEyMywyMDl4NTAs
MCwwLDYJb2ZmCndpbmRvdwkwCTIJOm9wZW5jb2RlCTAJOgliMTFlLDIwOXg1MCwwLDAsMQlvZmYK
d2luZG93CTAJMwk6Y29kZXgJMAk6CWIxMWYsMjA5eDUwLDAsMCwyCW9mZgp3aW5kb3cJMAk0CTpi
dG9wCTEJOioJY2IwMCwxMjB4MjksMCwwLDMJb2ZmCndpbmRvdwkwCTUJOmxvZwkwCTotCWNiMDQs
MTIweDI5LDAsMCw3CW9mZgpzdGF0ZQkwCQo=
SBX_RESURRECT_SNAPSHOT
    )
    printf '%s\n' "${snapshot//__SBX_HOME__/"$HOME"}" > "$work_dir/resurrect-snapshot"
    if exists "$state_dir/$seed"; then
        # Resume only an unchanged installer seed, never a modified user file.
        [[ -f $state_dir/$seed && ! -L $state_dir/$seed ]] || return 0
        if cmp -s -- "$work_dir/resurrect-snapshot" "$state_dir/$seed"; then
            :
        else
            compare_status=$?
            (( compare_status == 1 )) || die 'Cannot compare the bundled tmux snapshot.' "$compare_status"
            return 0
        fi
    else
        (umask 077; mkdir -p -- "$state_dir")
        staged=$(umask 077; mktemp -- "$state_dir/.sbx-seed.XXXXXX")
        cat -- "$work_dir/resurrect-snapshot" > "$staged"
        # Publish a complete file without replacing any existing destination.
        ln -T -- "$staged" "$state_dir/$seed"
        rm -f -- "$staged"
        staged=
        touch -- "$work_dir/changed"
    fi
    # A user save during installation takes precedence too.
    exists "$state_dir/last" && return 0
    for saved in "$state_dir"/tmux_resurrect_*.txt; do
        if exists "$saved" && [[ $saved != "$state_dir/$seed" ]]; then
            return 0
        fi
    done
    if ln -sT -- "$seed" "$state_dir/last"; then
        touch -- "$work_dir/changed"
    else
        compare_status=$?
        exists "$state_dir/last" || die 'Cannot publish the tmux snapshot last link.' "$compare_status"
    fi
)
seed_resurrect_snapshot "$resurrect_state_dir"
if [[ -e $work_dir/changed ]]; then
    stage_done changed 'Seeded snapshot; in tmux press Ctrl-b, then Ctrl-r'
else
    stage_done unchanged 'Existing resurrect state preserved'
fi

stage_begin 'Shell setup' 'Checking wrappers, PATH, and aliases'
vscode_contents() {
    cat <<'SBX_VSCODE'
#!/usr/bin/env bash
# Set up the tunnel once. The SBX startup kit restarts the enabled supervisor.
set -euo pipefail
umask 077
binary="$HOME/.local/lib/sbx-deploy/vscode-code"
state="$HOME/.local/state/sbx-deploy/vscode-tunnel"
mode=${1:---setup}
case $mode in
    --setup|--login|--run|--status|--disable|--foreground) ;;
    *) printf 'Usage: vscode_tunnel [--setup|--login|--status|--disable|--foreground]\n' >&2; exit 2 ;;
esac
(( $# <= 1 )) || { printf 'Use one tunnel command at a time.\n' >&2; exit 2; }
if [[ $mode == --status ]]; then
    exec "$HOME/.local/lib/sbx-deploy/vscode-status"
fi
# An unused startup kit must make no files or network requests.
if [[ $mode == --run && ! -e $state/enabled ]]; then exit 0; fi
for path in "$HOME/.local" "$HOME/.local/state" "$HOME/.local/state/sbx-deploy" "$state" "$state/cli"; do
    if [[ -L $path || ( -e $path && ( ! -d $path || ! -O $path ) ) ]]; then
        printf 'Unsafe tunnel state directory: %s. Preserve it and repair ownership or links.\n' "$path" >&2
        exit 1
    fi
done
if [[ ! -f $binary || ! -x $binary || -L $binary ]]; then
    printf 'VS Code CLI is missing or unusable. Rerun the SBX installer.\n' >&2
    exit 1
fi
mkdir -p -- "$state"
for file in enabled setup.lock run.lock last-exit; do
    if [[ -L $state/$file || ( -e $state/$file && ( ! -f $state/$file || ! -O $state/$file ) ) ]]; then
        printf 'Unsafe tunnel state file: %s. Preserve it and repair it before retrying.\n' "$state/$file" >&2
        exit 1
    fi
done
# Keep this helper's login separate from the default VS Code keyring entry.
export VSCODE_CLI_USE_FILE_KEYCHAIN=1
cli=("$binary" --cli-data-dir "$state/cli")
case $mode in
    --disable)
        exec 8> "$state/setup.lock"
        flock -w 5 8
        rm -f -- "$state/enabled"
        # The CLI uses local IPC in this private data directory.
        if timeout --kill-after=5s 15s "${cli[@]}" tunnel kill; then :; else
            printf 'No active tunnel stopped. The supervisor will exit within 30 seconds.\n'
        fi
        exit 0
        ;;
    --foreground)
        exec "${cli[@]}" tunnel --accept-server-license-terms
        ;;
    --run)
        exec 9> "$state/run.lock"
        if flock -n 9; then :; else
            result=$?
            if (( result == 1 )); then exit 0; fi
            printf 'Cannot lock the tunnel supervisor.\n' >&2
            exit "$result"
        fi
        child=
        cleanup() {
            trap - EXIT INT TERM
            if [[ -n $child ]]; then
                kill "$child" 2>/dev/null || :
                wait "$child" 2>/dev/null || :
            fi
        }
        trap cleanup EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        while [[ -f $state/enabled ]]; do
            # Use the saved login. Keep runtime and sign-in output out of all logs.
            "${cli[@]}" tunnel --accept-server-license-terms </dev/null >/dev/null 2>&1 9>&- &
            child=$!
            result=0
            wait "$child" || result=$?
            child=
            printf '%s\n' "$result" > "$state/last-exit"
            [[ -f $state/enabled ]] || break
            sleep 30 9>&- &
            child=$!
            wait "$child"
            child=
        done
        exit 0
        ;;
esac
# Setup is explicit and interactive. Never read pending pasted commands.
exec 8> "$state/setup.lock"
flock -w 5 8
if [[ $mode == --login ]] || ! timeout --kill-after=5s 15s "${cli[@]}" tunnel user show >/dev/null 2>&1; then
    if ! { exec 7<> /dev/tty; } 2>/dev/null; then
        printf 'Tunnel sign-in needs a terminal. Run: vscode_tunnel\n' >&2
        exit 1
    fi
    "$HOME/.local/lib/sbx-deploy/auth-vscode-browser-tty" \
        "${cli[@]}" tunnel user login --provider github <&7 >&7 2>&7
fi
# Enable only after successful login. Preserve existing authentication and settings.
if [[ ! -f $state/enabled ]]; then : > "$state/enabled"; fi
# The startup kit uses the same lock. A second supervisor exits without a tunnel.
if [[ $mode == --login ]]; then
    if timeout --kill-after=5s 15s "${cli[@]}" tunnel kill >/dev/null 2>&1; then :; fi
fi
nohup /usr/bin/env -u BASH_ENV /bin/bash "$0" --run </dev/null >/dev/null 2>&1 7>&- 8>&- &
exec 9> "$state/run.lock"
started=false
for attempt in {1..30}; do
    if flock -n 9; then
        flock -u 9
    else
        result=$?
        if (( result == 1 )); then started=true; break; fi
        printf 'Cannot check the tunnel supervisor lock.\n' >&2
        exit "$result"
    fi
    sleep 0.1
done
if [[ $started != true ]]; then
    printf 'Tunnel supervisor did not start. Inspect with: vscode_tunnel --foreground\n' >&2
    exit 1
fi
printf 'Tunnel startup enabled. The background supervisor will connect now.\n'
printf 'Check connection: vscode_status\n'
printf 'Connect in VS Code: Remote Tunnels: Connect to Tunnel\n'
printf 'For automatic restart, attach the Windows host startup kit once. See HOST_SETUP_WIN.md.\n'
printf 'Stop and disable: vscode_disable\n'

SBX_VSCODE
}
queue_helper "$HOME/.local/bin/sbx_vscode" vscode_contents
vscode_status_contents() {
    cat <<'SBX_VSCODE_STATUS'
#!/usr/bin/env python3
"""Show local tunnel status. Do not change files, authenticate, or log output."""
import fcntl
import json
import locale
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import textwrap

if len(sys.argv) != 1:
    sys.exit('Usage: vscode_status')
state = Path.home() / '.local/state/sbx-deploy/vscode-tunnel'
binary = Path.home() / '.local/lib/sbx-deploy/vscode-code'
width = max(32, min(80, shutil.get_terminal_size((80, 24)).columns))
boxed = width >= 60
utf8 = locale.getpreferredencoding(False).lower().replace('-', '') == 'utf8'
color = sys.stdout.isatty() and os.environ.get('TERM', 'dumb') != 'dumb' and 'NO_COLOR' not in os.environ
green, amber, muted, reset = ('\033[32m', '\033[33m', '\033[90m', '\033[0m') if color else ('', '', '', '')
vertical, horizontal = ('│', '─') if utf8 else ('|', '-')
corners = ('┌', '┐', '└', '┘') if utf8 else ('+', '+', '+', '+')

def line(text='', style='', literal=False):
    rows = [text] if literal else textwrap.wrap(text, width=width - 4) or ['']
    for row in rows:
        if boxed and len(row) <= width - 4:
            print(f'{muted}{vertical}{reset} {style}{row}{reset}{" " * (width - 4 - len(row))} {muted}{vertical}{reset}')
        else:
            print(f'  {style}{row}{reset}')

enabled = running = False
connection, name, last_exit, problem, status = 'Not configured', None, None, None, 0
try:
    for path in (state.parent.parent.parent, state.parent.parent, state.parent, state, state / 'cli'):
        if path.is_symlink() or (path.exists() and (not path.is_dir() or path.stat().st_uid != os.geteuid())):
            raise ValueError('Unsafe tunnel state directory. Preserve it and repair ownership or links.')
    if state.exists():
        for filename in ('enabled', 'run.lock', 'last-exit'):
            path = state / filename
            if path.is_symlink() or (path.exists() and (not path.is_file() or path.stat().st_uid != os.geteuid())):
                raise ValueError('Unsafe tunnel state file. Preserve it and repair it before retrying.')
        enabled = (state / 'enabled').is_file()
        if (state / 'run.lock').is_file():
            fd = os.open(state / 'run.lock', os.O_RDONLY | os.O_NOFOLLOW)
            try:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    running = True
            finally:
                os.close(fd)
        if (state / 'last-exit').is_file():
            value = (state / 'last-exit').read_text().strip()
            last_exit = value if re.fullmatch(r'[0-9]{1,3}', value) else 'Unknown'
        if not (state / 'cli').is_dir():
            connection = 'Not configured'
        else:
            if not binary.is_file() or binary.is_symlink() or not os.access(binary, os.X_OK):
                raise ValueError('VS Code CLI is missing or unusable. Rerun the SBX installer.')
            result = subprocess.run(['timeout', '--kill-after=5s', '15s', str(binary),
                                     '--cli-data-dir', str(state / 'cli'), 'tunnel', 'status'],
                                    env={**os.environ, 'VSCODE_CLI_USE_FILE_KEYCHAIN': '1'},
                                    capture_output=True, text=True)
            if result.returncode:
                status = result.returncode if result.returncode > 0 else 128 - result.returncode
                raise ValueError(f'Local status check failed (exit {status}).')
            data = json.loads(result.stdout)
            if not isinstance(data, dict) or 'tunnel' not in data:
                raise ValueError('Unsupported VS Code status response.')
            tunnel = data['tunnel']
            connection = 'Stopped'
            if tunnel is not None:
                if not isinstance(tunnel, dict) or tunnel.get('tunnel') not in ('Connected', 'Disconnected'):
                    raise ValueError('Unsupported VS Code connection state.')
                connection = tunnel['tunnel']
                candidate = tunnel.get('name')
                if isinstance(candidate, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,80}', candidate):
                    name = candidate
except (OSError, ValueError, subprocess.SubprocessError) as error:
    connection = 'Check needed'
    problem = str(error) if isinstance(error, ValueError) and not isinstance(error, json.JSONDecodeError) else 'Local status unavailable. Run vscode_tunnel --foreground to investigate.'
    status = status or 1

print()
if boxed:
    print(muted + corners[0] + horizontal * (width - 2) + corners[1] + reset)
line('VS CODE TUNNEL', green if connection == 'Connected' else amber)
line()
line('Connection: ' + connection, green if connection == 'Connected' else amber)
line('Automatic startup: ' + ('Enabled; host startup kit required' if enabled else 'Disabled'))
line('Supervisor: ' + ('Running' if running else 'Stopped'))
if name:
    line('Tunnel: ' + name)
    if connection == 'Connected':
        line('https://vscode.dev/tunnel/' + name, literal=True)
if last_exit is not None:
    line('Last tunnel exit: ' + last_exit, muted)
if problem:
    line(problem, amber)
line()
line('vscode_tunnel              Set up or start', literal=True)
line('vscode_tunnel --login      Authorize again', literal=True)
line('vscode_disable            Stop and disable', literal=True)
if boxed:
    print(muted + corners[2] + horizontal * (width - 2) + corners[3] + reset)
print()
sys.exit(status)
SBX_VSCODE_STATUS
}
queue_helper "$HOME/.local/lib/sbx-deploy/vscode-status" vscode_status_contents
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

queue_helper "$tmux_wrapper" wrapper_contents
queue_helper "$HOME/.local/bin/btop" btop_wrapper_contents

# Generate Python literals. Do not insert shell text directly into Python source.
python_settings() {
    local name
    local -a values=()
    for name in "$@"; do
        values+=("$name" "${!name}")
    done
    python3 - "${values[@]}" <<'SBX_PYTHON_VALUES'
import sys
for index in range(1, len(sys.argv), 2):
    name, value = sys.argv[index:index + 2]
    print(f'{name} = {int(value) if name.endswith("_seconds") else repr(value)}')
SBX_PYTHON_VALUES
}

credential_check_contents() {
    printf '#!/usr/bin/env python3\n'
    python_settings oauth_access oauth_provider oauth_base_url api_base_url \
        opencode_binary credential_seconds version_seconds kill_seconds
    cat <<'SBX_CREDENTIAL_CHECK'
"""Read-only live credential checks; never print tokens or command diagnostics."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import textwrap

if len(sys.argv) != 1:
    sys.exit('Usage: check_credentials')

home = Path.home()
failed = False
modes = []
passed = 0
actions = []
width = max(36, min(88, shutil.get_terminal_size((80, 24)).columns - 2))
color = sys.stdout.isatty() and os.environ.get('TERM', 'dumb') != 'dumb' and 'NO_COLOR' not in os.environ
palette = {'green': '\033[32m', 'amber': '\033[33m', 'cyan': '\033[36m',
           'dim': '\033[2m', 'bold': '\033[1m'}

def paint(text, style):
    return palette[style] + text + '\033[0m' if color else text

def note(text, style='dim'):
    for line in textwrap.wrap(text, width=width - 2):
        print('  ' + paint(line, style))

sentinel = oauth_access
base = oauth_base_url

def run(args, payload=None):
    # Capture all output in memory; stderr can contain credentials.
    seconds = version_seconds if '--version' in args else credential_seconds
    return subprocess.run(['timeout', f'--kill-after={kill_seconds}s', f'{seconds}s', *args],
                          input=payload, text=True, capture_output=True,
                          env={**os.environ, 'GH_DEBUG': '',
                          'GH_PROMPT_DISABLED': '1', 'GH_NO_UPDATE_NOTIFIER': '1'})

def report(name, mode, ok, detail):
    global failed, passed
    modes.append(mode)
    failed |= not ok
    passed += int(ok)
    source = {'passthrough': 'Host proxy', 'local login': 'Local login',
              'environment token (unknown)': 'Env token',
              'API key (local/env)': 'API key', 'unknown / missing': 'Missing'}.get(mode, 'Unknown')
    status = paint(f'{"PASS" if ok else "CHECK":5}', 'green' if ok else 'amber')
    row = f'  {name:10} {status}  {source:12}'
    if width >= 66:
        access = ('Account access' if name == 'GitHub' else 'Model access') if ok else detail
        row += '  ' + (access if ok else paint(access, 'amber'))
        print(row)
    else:
        print(f'  {name:10} {status}  {source}')
        if not ok:
            note(detail, 'amber')
    sys.stdout.flush()

def read_json(path):
    return json.loads(path.read_text()) if path.exists() else {}

def probe(token, url, version=None, account=None):
    if not isinstance(token, str) or not token or any(c in token for c in '\r\n'):
        return False, 'missing or unsupported token'
    headers = f'Authorization: Bearer {token}\n'
    if account:
        if not isinstance(account, str) or any(c in account for c in '\r\n'):
            return False, 'unsupported account ID'
        headers += f'ChatGPT-Account-Id: {account}\n'
    if version:
        url += '?client_version=' + version
    result = run(['curl', '--disable', '--silent', '--connect-timeout', '10',
                  '--max-time', '25', '--output', '/dev/null', '--write-out',
                  '%{http_code}', '--header', '@-', url], headers)
    code = result.stdout.strip()
    return result.returncode == 0 and code == '200', (
        f'HTTP {code}' if re.fullmatch(r'\d{3}', code) else 'request failed')

def check_github():
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if token:
        mode = 'passthrough' if 'proxy-managed' in token else 'environment token (unknown)'
    else:
        saved = run(['gh', 'auth', 'token', '--hostname', 'github.com'])
        token = saved.stdout.strip() if saved.returncode == 0 else ''
        mode = ('passthrough' if 'proxy-managed' in token else
                'local login' if token else 'unknown / missing')
    result = run(['gh', 'api', '--hostname', 'github.com', 'user', '--jq', '.login'])
    ok = result.returncode == 0 and bool(re.fullmatch(r'[A-Za-z0-9-]+', result.stdout.strip()))
    code = re.search(r'HTTP (\d{3})', result.stderr)
    report('GitHub', mode, ok, 'account request accepted' if ok else
           f'HTTP {code[1]}' if code else 'account request failed')
    if not ok and code and code[1] == '401':
        actions.append('GitHub 401: if host gh works, run sbx daemon restart in host PowerShell, then retry.')

def check_codex():
    import tomlkit
    directory = Path(os.environ.get('CODEX_HOME', str(home / '.codex')))
    path = directory / 'config.toml'
    config = tomlkit.parse(path.read_text()) if path.exists() else {}
    provider = config.get('model_provider', 'openai')
    version_result = run(['codex', '--version'])
    match = re.search(r'\b(\d+\.\d+\.\d+)\b', version_result.stdout)
    if not match:
        report('Codex', 'unknown', False, 'cannot determine CLI version')
        return
    if provider == oauth_provider:
        record = config.get('model_providers', {}).get(provider, {})
        if record.get('experimental_bearer_token') != sentinel or record.get('base_url') != base:
            report('Codex', 'unknown', False, 'managed provider differs')
            return
        mode, token, url, account = 'passthrough', sentinel, base + '/models', None
    elif provider == 'openai':
        auth = read_json(directory / 'auth.json')
        tokens = auth.get('tokens') or {}
        token = os.environ.get('OPENAI_API_KEY') or auth.get('OPENAI_API_KEY')
        account = None
        if token:
            mode, url = 'API key (local/env)', api_base_url + '/models'
        else:
            mode, token, url = 'local login', tokens.get('access_token'), base + '/models'
            account = tokens.get('account_id')
    else:
        report('Codex', 'unknown', False, 'custom provider; check in harness')
        return
    ok, detail = probe(token, url, match[1] if url.startswith(base) else None, account)
    report('Codex', mode, ok, detail)

def check_opencode():
    binary = shutil.which('opencode') or opencode_binary
    result = run([binary, 'auth', 'export', '--standalone'])
    if result.returncode:
        report('OpenCode', 'unknown', False, 'credential inventory unavailable')
        return
    records = json.loads(result.stdout)
    active = [r for r in records if r.get('integrationID') == 'openai' and r.get('active') is True]
    if len(active) != 1:
        report('OpenCode', 'unknown', False, 'expected one active OpenAI credential')
        return
    value = active[0]['value']
    token = value.get('access') if value.get('type') == 'oauth' else value.get('key')
    mode = 'passthrough' if token == sentinel else 'local login'
    if value.get('type') == 'oauth':
        result = run(['codex', '--version'])
        version = re.search(r'\b(\d+\.\d+\.\d+)\b', result.stdout)
        if not version:
            report('OpenCode', mode, False, 'cannot determine model probe version')
            return
        ok, detail = probe(token, base + '/models', version[1])
    else:
        ok, detail = probe(token, api_base_url + '/models')
    report('OpenCode', mode, ok, detail)

print('\n  ' + paint('CREDENTIAL CHECK', 'bold'))
note('Live access and selected credential sources. No settings changed.')
print('  ' + paint('-' * (width - 2), 'dim'))
if width >= 66:
    print('  ' + paint(f'{"SERVICE":10} {"STATE":5}  {"SOURCE":12}  ACCESS', 'dim'))
for name, check in [('GitHub', check_github), ('OpenCode', check_opencode), ('Codex', check_codex)]:
    try:
        check()
    except (OSError, ValueError, TypeError, KeyError, AttributeError, ImportError, subprocess.SubprocessError):
        report(name, 'unknown', False, 'check unavailable; diagnostics withheld')
print('  ' + paint('-' * (width - 2), 'dim'))
if all(mode == 'passthrough' for mode in modes):
    mode_label = 'Host passthrough'
elif all(mode == 'local login' for mode in modes):
    mode_label = 'Local login (auth_all style)'
else:
    mode_label = 'Mixed / unknown sources'
note(f'{passed}/3 passed | {mode_label}', 'amber' if failed else 'green')
if actions:
    print()
    for action in actions:
        note(action, 'amber')
print()
note('Sources: Host proxy = passthrough; Local login = saved auth_all-style credentials. The host proxy may still replace tokens.')
note('OpenAI: model access, not inference. Expired local OAuth may need a harness refresh.')
print()
sys.exit(1 if failed else 0)
SBX_CREDENTIAL_CHECK
}
credential_check_contents > "$work_dir/sbx_check_credentials"
queue_managed_file "$HOME/.local/bin/sbx_check_credentials" "$work_dir/sbx_check_credentials"

mcp_check_contents() {
    printf '#!/usr/bin/env python3\n'
    python_settings mcp_gateway_url credential_seconds
    cat <<'SBX_MCP_CHECK'
"""Discover brokered MCP tools without executing tools or changing attachments."""
import http.client
import json
import os
import re
import shutil
import socket
import sys
import textwrap
import time
import urllib.error
import urllib.request

if len(sys.argv) != 1:
    sys.exit('Usage: check_mcp')

width = max(36, min(88, shutil.get_terminal_size((80, 24)).columns - 2))
color = sys.stdout.isatty() and os.environ.get('TERM', 'dumb') != 'dumb' and 'NO_COLOR' not in os.environ
palette = {'green': '\033[32m', 'amber': '\033[33m', 'cyan': '\033[36m',
           'dim': '\033[2m', 'bold': '\033[1m'}

def paint(text, style):
    return palette[style] + text + '\033[0m' if color else text

def note(text, style='dim'):
    for line in textwrap.wrap(text, width=width - 2):
        print('  ' + paint(line, style))

def check_mcp():
    # Query only the shared managed endpoint. Never invoke upstream tools,
    # authorization helpers, or dynamic attachment/configuration tools.
    endpoint = mcp_gateway_url
    # The gateway alias can be routed by the SBX HTTP proxy. Honor the same
    # proxy/NO_PROXY environment as clients instead of forcing direct DNS.
    opener = urllib.request.build_opener()
    headers = {'Content-Type': 'application/json',
               'Accept': 'application/json, text/event-stream'}
    deadline = time.monotonic() + credential_seconds
    sequence = 0
    phase = 'initialize'

    def rpc(method, params=None, notification=False):
        nonlocal sequence, phase
        phase = method
        sequence += 1
        message = {'jsonrpc': '2.0', 'method': method}
        if not notification:
            message['id'] = sequence
        if params is not None:
            message['params'] = params
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError('MCP discovery timed out')
        request = urllib.request.Request(endpoint, json.dumps(message).encode(), headers)
        with opener.open(request, timeout=min(10, remaining)) as response:
            session = response.headers.get('Mcp-Session-Id')
            if session:
                if len(session) > 1024 or not re.fullmatch(r'[\x21-\x7e]+', session):
                    raise ValueError('Invalid MCP session')
                headers['Mcp-Session-Id'] = session
            if notification:
                return {}
            reply = None
            if 'text/event-stream' in response.headers.get('Content-Type', ''):
                data, size = [], 0
                while time.monotonic() < deadline:
                    line = response.readline(1048577)
                    size += len(line)
                    if size > 1048576:
                        raise ValueError('MCP response too large')
                    if not line:
                        break
                    line = line.decode('utf-8').rstrip('\r\n')
                    if line.startswith('data:'):
                        data.append(line[5:].lstrip(' '))
                    elif not line and data:
                        reply = json.loads('\n'.join(data))
                        data = []
                        if isinstance(reply, dict) and reply.get('id') == sequence:
                            break
                else:
                    raise ValueError('MCP discovery timed out')
                if not isinstance(reply, dict) or reply.get('id') != sequence:
                    raise ValueError('Missing MCP response')
            else:
                body = response.read(1048577)
                if len(body) > 1048576:
                    raise ValueError('MCP response too large')
                reply = json.loads(body)
            if not isinstance(reply, dict) or reply.get('id') != sequence or 'error' in reply:
                raise ValueError('MCP request failed')
            result = reply.get('result')
            if not isinstance(result, dict):
                raise ValueError('Invalid MCP result')
            return result

    print('\n  ' + paint('BROKERED MCP', 'bold'), flush=True)
    print('  ' + paint('-' * (width - 2), 'dim'))
    try:
        result = rpc('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {},
                     'clientInfo': {'name': 'check_mcp', 'version': '1.0'}})
        version = result.get('protocolVersion')
        if version not in ('2024-11-05', '2025-03-26', '2025-06-18', '2025-11-25'):
            raise ValueError('Unsupported MCP protocol')
        headers['MCP-Protocol-Version'] = version
        rpc('notifications/initialized', notification=True)
        tools, cursors, cursor = [], set(), None
        for page in range(20):
            result = rpc('tools/list', {'cursor': cursor} if cursor else {})
            batch = result.get('tools')
            if not isinstance(batch, list) or any(not isinstance(tool, dict) for tool in batch):
                raise ValueError('Invalid MCP tools')
            tools.extend(batch)
            cursor = result.get('nextCursor')
            if not cursor:
                break
            if not isinstance(cursor, str) or cursor in cursors:
                raise ValueError('Invalid MCP pagination')
            cursors.add(cursor)
        else:
            raise ValueError('MCP pagination limit reached')
        names = sorted({tool['name'] for tool in tools
                        if isinstance(tool.get('name'), str)
                        and re.fullmatch(r'[A-Za-z0-9_.:/-]{1,128}', tool['name'])})
        note('PASS  Gateway connected', 'green')
        # Docker documents these helpers as belonging to exposed OAuth servers.
        # Their presence is not proof that a server currently has valid OAuth.
        helpers = [name for name in names if name.endswith(('-authorize', '-revoke-auth'))]
        servers = sorted({re.sub(r'-(?:authorize|revoke-auth)$', '', name) for name in helpers})
        if servers:
            note('Servers  ' + ', '.join(servers), 'cyan')
        else:
            note('Servers  Names hidden by gateway')
        gateway_names = {'code-mode', 'mcp-exec', 'mcp-find', 'mcp-add', 'mcp-config-set'}
        server_tools = [name for name in names if name not in gateway_names and name not in helpers]
        gateway_tools = [name for name in names if name in gateway_names]
        for label, group, style in [('SERVER TOOLS', server_tools, 'cyan'),
                                    ('AUTH HELPERS', helpers, 'dim'),
                                    ('GATEWAY TOOLS', gateway_tools, 'dim')]:
            if group:
                print()
                note(f'{label} ({len(group)})', 'bold')
                for name in group:
                    note('  - ' + name, style)
        if not names:
            note('No displayable tools exposed.')
        print()
        note(f'{len(tools)} tools exposed | Discovery only; upstream OAuth unverified.')
        if any(name in names for name in ('mcp-exec', 'code-mode')):
            note('Additional upstream tools may be available through the gateway.')
        print('  ' + paint('-' * (width - 2), 'dim'))
        return True
    except (OSError, ValueError, TypeError, KeyError, urllib.error.URLError,
            http.client.HTTPException) as error:
        # Report only status codes and known categories, never raw response
        # bodies, headers, URLs with credentials, or remote error messages.
        if isinstance(error, urllib.error.HTTPError):
            reason = f'HTTP {error.code}'
        else:
            cause = error.reason if isinstance(error, urllib.error.URLError) else error
            if isinstance(cause, socket.gaierror):
                reason = 'DNS lookup failed'
            elif isinstance(cause, (TimeoutError, socket.timeout)):
                reason = 'request timed out'
            elif isinstance(cause, ConnectionRefusedError):
                reason = 'connection refused'
            elif isinstance(error, json.JSONDecodeError):
                reason = 'invalid JSON response'
            elif isinstance(error, ValueError) and str(error) in {
                'MCP discovery timed out', 'Invalid MCP session', 'MCP response too large',
                'Missing MCP response', 'MCP request failed', 'Invalid MCP result',
                'Unsupported MCP protocol', 'Invalid MCP tools', 'Invalid MCP pagination',
                'MCP pagination limit reached',
            }:
                reason = str(error)
            else:
                reason = 'transport or protocol error'
        note(f'CHECK | {phase} | {reason}', 'amber')
        note('Routing follows sandbox proxy / NO_PROXY settings.')
        note('Check host sbx mcp ls and sandbox attachments; verify tools in each harness.')
        return False
    finally:
        if 'Mcp-Session-Id' in headers:
            try:
                request = urllib.request.Request(endpoint, headers=headers, method='DELETE')
                with opener.open(request, timeout=3):
                    pass
            except (OSError, urllib.error.URLError, http.client.HTTPException):
                pass  # Session termination is optional; never mask probe results.

sys.exit(0 if check_mcp() else 1)
SBX_MCP_CHECK
}
mcp_check_contents > "$work_dir/sbx_check_mcp"
queue_managed_file "$HOME/.local/bin/sbx_check_mcp" "$work_dir/sbx_check_mcp"

desktop_contents() {
    cat <<'SBX_DESKTOP'
#!/usr/bin/env bash
# Display local desktop status and reconnection commands; no settings changed.
set -euo pipefail
if (( $# > 1 )); then
    printf 'Usage: desktop [sandbox-name]\n' >&2
    exit 2
fi
exec 3>&1
log_file=
green= amber= muted= reset=
utf8=false
locale_name=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ ${locale_name,,} == *utf-8* || ${locale_name,,} == *utf8* ]]; then utf8=true; fi
if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR+x} ]]; then
    green=$'\033[32m' amber=$'\033[33m' muted=$'\033[90m' reset=$'\033[0m'
fi
# Use the installer's summary layout without writing to an installer log.
report_line() { printf '%s%s%s\n' "${2-}" "$1" "$reset" >&3; }
SBX_DESKTOP
    # Share wrapping, boxes, command bullets and narrow-terminal fallbacks.
    declare -f summary_layout box_rule summary_begin summary_end summary_text summary_command
    cat <<'SBX_DESKTOP'
summary_layout
sandbox_name=${1:-${HOSTNAME:-}}
if [[ ! $sandbox_name =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    sandbox_name='$sandboxName'
fi
container_state= image= status_color=$amber
if ! command -v docker >/dev/null 2>&1; then
    status='Docker is not installed in this sandbox.'
elif ! docker info >/dev/null 2>&1; then
    status='Docker is unavailable; run docker info for details.'
else
    container_id=$(docker container ls -a --filter 'name=^/webtop$' --format '{{.ID}}')
    if [[ -n $container_id ]]; then
        container_state=$(docker inspect --format '{{.State.Status}}' "$container_id")
        image=$(docker inspect --format '{{.Config.Image}}' "$container_id")
        status=$container_state
        if [[ $container_state == running ]]; then status_color=$green; fi
    else
        status='Not deployed'
    fi
fi
summary_begin 'WEBTOP DESKTOP' "$status_color"
summary_text ''
summary_text "Status: $status" "$status_color"
if [[ -n $image ]]; then summary_text "Image: $image" "$muted"; fi
summary_text ''
summary_text 'Open in your browser:'
summary_command 'https://127.0.0.1:3001/'
summary_text 'Accept the self-signed certificate.' "$muted"
summary_text 'Use your mapped host port if different.' "$muted"
if [[ $container_state == exited || $container_state == created ]]; then
    summary_text ''
    summary_text 'Sandbox Bash - start the desktop:'
    summary_command 'docker start webtop'
elif [[ $status == 'Not deployed' ]]; then
    summary_text ''
    summary_text 'Sandbox Bash - deploy the desktop (choose Yes):'
    summary_command 'bash ~/sbx_local_opencode_deploy.sh'
fi
summary_text ''
summary_end
summary_begin 'WINDOWS POWERSHELL - CONNECT' "$green"
summary_text ''
summary_text 'Confirm the sandbox name:'
summary_command 'sbx ls'
if [[ $sandbox_name == '$sandboxName' ]]; then
    summary_command '$sandboxName = Read-Host "Sandbox name"'
fi
summary_text ''
summary_text 'Reconnect to the sandbox:'
summary_command "sbx exec -it $sandbox_name bash"
summary_text ''
summary_text 'Check published ports:'
summary_command "sbx ports $sandbox_name"
summary_text ''
summary_text 'Publish only if the mapping is absent:'
summary_command "sbx ports $sandbox_name --publish 127.0.0.1:3001:3001"
summary_text ''
summary_text 'Port bindings normally survive disconnection.' "$muted"
summary_text ''
summary_end
summary_begin 'SANDBOX BASH - RESUME' "$green"
summary_text ''
summary_command 'tmux attach' 'Resume an existing tmux session after reconnecting'
summary_text ''
summary_text 'The suggested sandbox name defaults to this sandbox hostname.' "$muted"
summary_text 'For another name, run: desktop SANDBOX-NAME' "$muted"
summary_text ''
summary_end
report_line ''
SBX_DESKTOP
}
queue_helper "$HOME/.local/bin/desktop" desktop_contents

# Private adapter for login helpers. Leave desktop clipboard tools unchanged.
gh_clipboard_contents() {
    cat <<'SBX_GH_CLIPBOARD'
#!/bin/sh
set -eu
# GitHub CLI's clipboard library invokes xclip with these write arguments.
case "$*" in
    '-in -selection clipboard') ;;
    *) printf 'SBX clipboard adapter supports writes only.\n' >&2; exit 1 ;;
esac
if [ -n "${TMUX:-}" ]; then
    # Let tmux forward the clipboard to the outer terminal using its settings.
    exec /usr/bin/tmux load-buffer -w -
fi
encoded=$(base64 -w0)
printf '\033]52;c;%s\007' "$encoded" > /dev/tty
SBX_GH_CLIPBOARD
}
queue_helper "$HOME/.local/lib/sbx-deploy/gh-clipboard/xclip" gh_clipboard_contents

# Keep auth output attached to a pseudoterminal so prompts stay interactive.
# Forward output live without saving authentication output to installer logs.
openai_auth_contents() {
    printf '#!/usr/bin/env python3\n'
    case ${1-} in
        codex) python_settings oauth_provider codex_device_url deploy_lock credential_seconds ;;
        vscode) : ;;
        *) python_settings opencode_binary ;;
    esac
    cat <<'SBX_OPENAI_AUTH'
import os
import errno
import fcntl
from pathlib import Path
import pty
import re
import signal
import subprocess
import sys
import termios

SBX_OPENAI_AUTH
    if [[ ${1-} == codex ]]; then
        printf '%s\n' "command = ['codex', '-c', 'model_provider=\"openai\"', '-c', 'forced_login_method=\"chatgpt\"', 'login', '--device-auth']"
    elif [[ ${1-} == vscode ]]; then
        cat <<'SBX_VSCODE_AUTH_COMMAND'
command = sys.argv[1:]
if not command:
    sys.exit('Use vscode_tunnel to start tunnel sign-in.')
SBX_VSCODE_AUTH_COMMAND
    else
        cat <<'SBX_OPENAI_COMMAND'
command = [opencode_binary, 'auth', 'login', 'openai',
           '--method', 'chatgpt-headless']
SBX_OPENAI_COMMAND
    fi
    cat <<'SBX_OPENAI_AUTH'
adapter = Path.home() / '.local/lib/sbx-deploy/gh-clipboard/xclip'
ansi = re.compile(rb'\x1b\[[0-?]*[ -/]*[@-~]')
SBX_OPENAI_AUTH
    if [[ ${1-} == codex ]]; then
        printf '%s\n' "code_pattern = re.compile(rb'\b([A-Z0-9]{4,8}-[A-Z0-9]{4,8})\b')"
    elif [[ ${1-} == vscode ]]; then
        cat <<'SBX_VSCODE_AUTH_PATTERN'
code_pattern = re.compile(rb'\b(?:use|enter)(?: the)? code[: \t]+([A-Z0-9]{4}-[A-Z0-9]{4})(?![A-Z0-9-])', re.I)
SBX_VSCODE_AUTH_PATTERN
    else
        cat <<'SBX_OPENAI_PATTERN'
code_pattern = re.compile(rb'Enter code:[ \t]*([A-Z0-9]{4,8}(?:-[A-Z0-9]{4,8})?)(?=[ \t\r\n])')
SBX_OPENAI_PATTERN
    fi
    cat <<'SBX_OPENAI_AUTH'
pending = b''
attempted = False

def interrupted(signum, frame):
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGHUP, interrupted)
master, slave = pty.openpty()
# Input stays on the real terminal: OpenCode receives Enter and keyboard signals
# directly. Both output streams see a terminal instead of a noninteractive pipe.
try:
    if sys.stdin.isatty():
        size = fcntl.ioctl(sys.stdin.fileno(), termios.TIOCGWINSZ, b'\0' * 8)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, size)
    process = subprocess.Popen(command, stdout=slave, stderr=slave)
except BaseException:
    os.close(master)
    raise
finally:
    os.close(slave)
try:
    while True:
        try:
            chunk = os.read(master, 4096)
        except OSError as error:
            if error.errno == errno.EIO:  # Linux PTY EOF after the child exits.
                break
            raise
        if not chunk:
            break
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        if attempted:
            continue
        pending = (pending + chunk)[-16384:]
        match = code_pattern.search(ansi.sub(b'', pending))
        if match:
            attempted = True
            try:
                subprocess.run([str(adapter), '-in', '-selection', 'clipboard'],
                               input=match[1], check=True, timeout=5)
                print('\nDevice code sent to terminal clipboard.', flush=True)
            except (OSError, subprocess.SubprocessError):
                print('\nClipboard unavailable; copy the displayed device code manually.',
                      file=sys.stderr, flush=True)
SBX_OPENAI_AUTH
    if [[ ${1-} == codex ]]; then
        cat <<'SBX_CODEX_BROWSER'
            # Open after copying the code, once per login. Honor BROWSER through
            # Python's browser selection; keep opener output out of the auth UI.
            url = codex_device_url
            try:
                subprocess.run(
                    [sys.executable, '-c',
                     'import sys, webbrowser; sys.exit(0 if webbrowser.open(sys.argv[1], new=2) else 1)',
                     url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, check=True, timeout=5)
            except (OSError, subprocess.SubprocessError):
                print(f'Open this URL in your browser: {url}', flush=True)
SBX_CODEX_BROWSER
    elif [[ ${1-} == vscode ]]; then
        cat <<'SBX_VSCODE_BROWSER'
            # SBX's bridge opens the Windows host browser. Never open a local desktop browser.
            url = 'https://github.com/login/device'
            try:
                subprocess.run(['/usr/local/bin/xdg-open', url],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, check=True, timeout=5)
            except (OSError, subprocess.SubprocessError):
                print(f'Open this URL in your host browser: {url}', flush=True)
SBX_VSCODE_BROWSER
    fi
    cat <<'SBX_OPENAI_AUTH'
    status = process.wait()
except BaseException as error:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    if isinstance(error, KeyboardInterrupt):
        sys.exit(130)
    raise
finally:
    os.close(master)
SBX_OPENAI_AUTH
    if [[ ${1-} == codex ]]; then
        cat <<'SBX_CODEX_AUTH_CONFIG'
if status == 0:
    # Explicit local login overrides the managed provider only after success.
    # Installer reruns preserve the selected provider. Never edit auth.json.
    import tomlkit
    import tempfile
    lock_fd = os.open(deploy_lock, os.O_RDONLY | os.O_NOFOLLOW)
    lock_result = subprocess.run(['flock', '--conflict-exit-code', '124', '--wait', str(credential_seconds), str(lock_fd)],
                                 pass_fds=(lock_fd,))
    if lock_result.returncode:
        print('Local login succeeded, but configuration locking failed or timed out; retry auth_codex_openai --force later.', file=sys.stderr)
        sys.exit(lock_result.returncode)
    config_dir = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex')))
    config_file = config_dir / 'config.toml'
    if not config_dir.is_absolute() or config_file.is_symlink():
        sys.exit('Local login succeeded, but the Codex configuration path is unsafe.')
    if config_file.exists():
        try:
            original = config_file.read_bytes().decode('utf-8')
            config = tomlkit.parse(original)
        except (OSError, ValueError):
            sys.exit('Local login succeeded, but Codex configuration could not be read.')
        if config.get('model_provider') == oauth_provider:
            config['model_provider'] = 'openai'
            if config.get('forced_login_method') == 'api':
                del config['forced_login_method']
            staged = None
            try:
                with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8',
                                                 dir=config_dir, delete=False) as handle:
                    staged = Path(handle.name)
                    handle.write(tomlkit.dumps(config))
                staged.chmod(config_file.stat().st_mode & 0o777)
                if config_file.is_symlink() or config_file.read_bytes().decode('utf-8') != original:
                    sys.exit('Codex configuration changed after login; preserve it and retry.')
                os.replace(staged, config_file)
            finally:
                if staged is not None:
                    staged.unlink(missing_ok=True)
SBX_CODEX_AUTH_CONFIG
    fi
    cat <<'SBX_OPENAI_AUTH'
sys.exit(status if status >= 0 else 128 - status)
SBX_OPENAI_AUTH
}
# Use a new managed path so existing wrappers remain safe to migrate on rerun.
queue_helper "$HOME/.local/lib/sbx-deploy/auth-openai-tty" openai_auth_contents
codex_auth_contents() { openai_auth_contents codex; }
queue_helper "$HOME/.local/lib/sbx-deploy/auth-codex-openai-browser-tty" codex_auth_contents
vscode_auth_contents() { openai_auth_contents vscode; }
queue_helper "$HOME/.local/lib/sbx-deploy/auth-vscode-browser-tty" vscode_auth_contents

# Interactive definitions live in one owned file; startup files hold loaders.
{
    printf 'sbx_opencode_binary=%q\nsbx_credential_seconds=%q\nsbx_kill_seconds=%q\n' \
        "$opencode_binary" "$credential_seconds" "$kill_seconds"
    cat <<'SBX_SHELL_SETTINGS'
alias check_credentials='"$HOME/.local/bin/sbx_check_credentials"'
alias check_mcp='"$HOME/.local/bin/sbx_check_mcp"'

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

# Set up authentication and enable automatic tunnel startup.
alias vscode_tunnel='"$HOME/.local/bin/sbx_vscode"'
alias vscode_status='"$HOME/.local/bin/sbx_vscode" --status'
alias vscode_disable='"$HOME/.local/bin/sbx_vscode" --disable'


# SBX Deploy: GitHub browser login
auth_gh() {
    case $#:${1-} in
        0:|1:--force) ;;
        *) printf 'Usage: auth_gh [--force]\n' >&2; return 2 ;;
    esac
    unset GH_TOKEN GITHUB_TOKEN || return
    if [[ ${1-} != --force ]] && command timeout --kill-after="${sbx_kill_seconds}s" "${sbx_credential_seconds}s" gh auth status --active --hostname github.com >/dev/null 2>&1; then
        printf 'GitHub: already authenticated; skipping login.\n'
        return 0
    fi
    # Scope the adapter and X11 backend selection to this gh process.
    command env -u WAYLAND_DISPLAY \
        PATH="$HOME/.local/lib/sbx-deploy/gh-clipboard:$PATH" \
        gh auth login --hostname github.com --git-protocol https --web --clipboard
}

# SBX Deploy: OpenAI device-code login
auth_opencode_openai() {
    local auth_status
    case $#:${1-} in
        0:|1:--force) ;;
        *) printf 'Usage: auth_opencode_openai [--force]\n' >&2; return 2 ;;
    esac
    # auth list reports stored providers, including refreshable OAuth sessions.
    if [[ ${1-} != --force && ${SBX_CRED_OPENAI_MODE:-none} != oauth ]] &&
       auth_status=$(timeout --kill-after="${sbx_kill_seconds}s" "${sbx_credential_seconds}s" "$sbx_opencode_binary" auth list 2>/dev/null) &&
       printf '%s' "$auth_status" | python3 -c '
import re
import sys
text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", sys.stdin.read())
sys.exit(0 if re.search(r"\bOpenAI[ \t]+(?:\(?(?:oauth|api)\b|OpenAI[ \t]+stored\b)", text, re.I) else 1)
'; then
        printf 'OpenCode OpenAI: saved credentials found; skipping login.\n'
        return 0
    fi
    "$HOME/.local/lib/sbx-deploy/auth-openai-tty"
}

# SBX Deploy: Codex OpenAI device-code login
auth_codex_openai() {
    case $#:${1-} in
        0:|1:--force) ;;
        *) printf 'Usage: auth_codex_openai [--force]\n' >&2; return 2 ;;
    esac
    if [[ ${1-} != --force && ${SBX_CRED_OPENAI_MODE:-none} != oauth ]] &&
       command timeout --kill-after="${sbx_kill_seconds}s" "${sbx_credential_seconds}s" env PATH="$HOME/.local/bin:$PATH" codex login status >/dev/null 2>&1; then
        printf 'Codex: already authenticated; skipping login.\n'
        return 0
    fi
    command env PATH="$HOME/.local/bin:$PATH" \
        "$HOME/.local/lib/sbx-deploy/auth-codex-openai-browser-tty"
}


# SBX Deploy: authenticate all agents
auth_all() {
    case $#:${1-} in
        0:|1:--force) ;;
        *) printf 'Usage: auth_all [--force]\n' >&2; return 2 ;;
    esac
    auth_opencode_openai "$@" || return
    auth_codex_openai "$@" || return
    auth_gh "$@"
}


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
SBX_SHELL_SETTINGS
} > "$work_dir/shell.bash"
queue_managed_file /usr/local/lib/sbx-deploy/shell.bash "$work_dir/shell.bash" 644
cat > "$work_dir/path.bash" <<'SBX_PATH_SETTINGS'
case $- in
    *i*)
        case ${PATH-} in
            "$HOME/.local/bin"|"$HOME/.local/bin:"*) ;;
            *) export PATH="$HOME/.local/bin${PATH:+:$PATH}" ;;
        esac
        ;;
esac
SBX_PATH_SETTINGS
queue_managed_file /usr/local/lib/sbx-deploy/path.bash "$work_dir/path.bash" 644
# Compare complete legacy blocks. Reject remaining managed labels or definitions.
# Never guess where an edited block ends.
cat > "$work_dir/migrate-shell.py" <<'SBX_MIGRATE_SHELL'
from pathlib import Path
import re
import sys

source, staged, kind = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
if source.is_symlink() or (source.exists() and not source.is_file()):
    sys.exit(f'Unsafe startup file: {source}')
existed = source.exists()
original = source.read_bytes().decode('utf-8') if existed else ''
Path(str(staged) + '.input').write_text(original)
Path(str(staged) + '.exists').write_text(str(existed))
legacy = [
    '\n# SBX Deploy: custom system prompts\ncase $- in\n    *i*)\n        # Abbreviate every parent to its first character; keep the last name.\n        # Bash string operations preserve spaces/globs and avoid external tools.\n        short_path() {\n            local path=${PWD#/} component result=\n            while [[ $path == */* ]]; do\n                component=${path%%/*}\n                path=${path#*/}\n                [[ -z $component ]] || result+="/${component:0:1}"\n            done\n            printf \'%s/%s\' "$result" "$path"\n        }\n        _sbx_prompt() {\n            local status=$?\n            if (( EUID == 0 )); then\n                PS1=\'${debian_chroot:+($debian_chroot)}\\[\\033[01;31m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]$(short_path)\\[\\033[00m\\]\\$ \'\n            else\n                PS1=\'${debian_chroot:+($debian_chroot)}\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]$(short_path)\\[\\033[00m\\]\\$ \'\n            fi\n            return "$status"\n        }\n        # Personal .bashrc defaults run after /etc/bash.bashrc. Set PS1 just\n        # before display, preserving existing command hooks and their status.\n        _sbx_register_prompt() {\n            local command\n            for command in "${PROMPT_COMMAND[@]}"; do\n                [[ $command != _sbx_prompt ]] || return 0\n            done\n            PROMPT_COMMAND=("${PROMPT_COMMAND[@]}" _sbx_prompt)\n        }\n        _sbx_register_prompt\n        unset -f _sbx_register_prompt\n        ;;\nesac\n',
    '# SBX Deploy: OpenAI device-code login\nauth_opencode_openai() {\n    local auth_status\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_opencode_openai [--force]\\n\' >&2; return 2 ;;\n    esac\n    # auth list reports stored providers, including refreshable OAuth sessions.\n    if [[ ${1-} != --force && ${SBX_CRED_OPENAI_MODE:-none} != oauth ]] &&\n       auth_status=$(/home/agent/.opencode/bin/opencode auth list 2>/dev/null) &&\n       printf \'%s\' "$auth_status" | python3 -c \'\nimport re\nimport sys\ntext = re.sub(r"\\x1b\\[[0-?]*[ -/]*[@-~]", "", sys.stdin.read())\nsys.exit(0 if re.search(r"\\bOpenAI[ \\t]+(?:\\(?(?:oauth|api)\\b|OpenAI[ \\t]+stored\\b)", text, re.I) else 1)\n\'; then\n        printf \'OpenCode OpenAI: saved credentials found; skipping login.\\n\'\n        return 0\n    fi\n    "$HOME/.local/lib/sbx-deploy/auth-openai-tty"\n}\n',
    'auth_opencode_openai() {\n    local auth_status\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_opencode_openai [--force]\\n\' >&2; return 2 ;;\n    esac\n    # auth list reports stored providers, including refreshable OAuth sessions.\n    if [[ ${1-} != --force && ${SBX_CRED_OPENAI_MODE:-none} != oauth ]] &&\n       auth_status=$(/home/agent/.opencode/bin/opencode auth list 2>/dev/null) &&\n       printf \'%s\' "$auth_status" | python3 -c \'\nimport re\nimport sys\ntext = re.sub(r"\\x1b\\[[0-?]*[ -/]*[@-~]", "", sys.stdin.read())\nsys.exit(0 if re.search(r"\\bOpenAI[ \\t]+(?:\\(?(?:oauth|api)\\b|OpenAI[ \\t]+stored\\b)", text, re.I) else 1)\n\'; then\n        printf \'OpenCode OpenAI: saved credentials found; skipping login.\\n\'\n        return 0\n    fi\n    "$HOME/.local/lib/sbx-deploy/auth-openai-tty"\n}\n',
    '# SBX Deploy: OpenAI device-code login\nauth_opencode_openai() {\n    local auth_status\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_opencode_openai [--force]\\n\' >&2; return 2 ;;\n    esac\n    # auth list reports stored providers, including refreshable OAuth sessions.\n    if [[ ${1-} != --force ]] &&\n       auth_status=$(/home/agent/.opencode/bin/opencode auth list 2>/dev/null) &&\n       printf \'%s\' "$auth_status" | python3 -c \'\nimport re\nimport sys\ntext = re.sub(r"\\x1b\\[[0-?]*[ -/]*[@-~]", "", sys.stdin.read())\nsys.exit(0 if re.search(r"\\bOpenAI[ \\t]+(?:\\(?(?:oauth|api)\\b|OpenAI[ \\t]+stored\\b)", text, re.I) else 1)\n\'; then\n        printf \'OpenCode OpenAI: saved credentials found; skipping login.\\n\'\n        return 0\n    fi\n    "$HOME/.local/lib/sbx-deploy/auth-openai-tty"\n}\n',
    '# SBX Deploy: OpenAI device-code login\nauth_opencode_openai() {\n    local auth_status\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_opencode_openai [--force]\\n\' >&2; return 2 ;;\n    esac\n    # auth list reports stored providers, including refreshable OAuth sessions.\n    if [[ ${1-} != --force ]] &&\n       auth_status=$(/home/agent/.opencode/bin/opencode auth list 2>/dev/null) &&\n       printf \'%s\' "$auth_status" | python3 -c \'\nimport re\nimport sys\ntext = re.sub(r"\\x1b\\[[0-?]*[ -/]*[@-~]", "", sys.stdin.read())\nsys.exit(0 if re.search(r"\\bOpenAI\\s+\\(?(?:oauth|api)\\b", text, re.I) else 1)\n\'; then\n        printf \'OpenCode OpenAI: saved credentials found; skipping login.\\n\'\n        return 0\n    fi\n    "$HOME/.local/lib/sbx-deploy/auth-openai-tty"\n}\n',
    'auth_opencode_openai() {\n    local auth_status\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_opencode_openai [--force]\\n\' >&2; return 2 ;;\n    esac\n    # auth list reports stored providers, including refreshable OAuth sessions.\n    if [[ ${1-} != --force ]] &&\n       auth_status=$(/home/agent/.opencode/bin/opencode auth list 2>/dev/null) &&\n       printf \'%s\' "$auth_status" | python3 -c \'\nimport re\nimport sys\ntext = re.sub(r"\\x1b\\[[0-?]*[ -/]*[@-~]", "", sys.stdin.read())\nsys.exit(0 if re.search(r"\\bOpenAI[ \\t]+(?:\\(?(?:oauth|api)\\b|OpenAI[ \\t]+stored\\b)", text, re.I) else 1)\n\'; then\n        printf \'OpenCode OpenAI: saved credentials found; skipping login.\\n\'\n        return 0\n    fi\n    "$HOME/.local/lib/sbx-deploy/auth-openai-tty"\n}\n',
    'auth_opencode_openai() {\n    local auth_status\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_opencode_openai [--force]\\n\' >&2; return 2 ;;\n    esac\n    # auth list reports stored providers, including refreshable OAuth sessions.\n    if [[ ${1-} != --force ]] &&\n       auth_status=$(/home/agent/.opencode/bin/opencode auth list 2>/dev/null) &&\n       printf \'%s\' "$auth_status" | python3 -c \'\nimport re\nimport sys\ntext = re.sub(r"\\x1b\\[[0-?]*[ -/]*[@-~]", "", sys.stdin.read())\nsys.exit(0 if re.search(r"\\bOpenAI\\s+\\(?(?:oauth|api)\\b", text, re.I) else 1)\n\'; then\n        printf \'OpenCode OpenAI: saved credentials found; skipping login.\\n\'\n        return 0\n    fi\n    "$HOME/.local/lib/sbx-deploy/auth-openai-tty"\n}\n',
    '# SBX Deploy: GitHub browser login\nlogin_gh() {\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_gh [--force]\\n\' >&2; return 2 ;;\n    esac\n    unset GH_TOKEN GITHUB_TOKEN || return\n    if [[ ${1-} != --force ]] && command gh auth status --active --hostname github.com >/dev/null 2>&1; then\n        printf \'GitHub: already authenticated; skipping login.\\n\'\n        return 0\n    fi\n    # Scope the adapter and X11 backend selection to this gh process.\n    command env -u WAYLAND_DISPLAY \\\n        PATH="$HOME/.local/lib/sbx-deploy/gh-clipboard:$PATH" \\\n        gh auth login --hostname github.com --git-protocol https --web --clipboard\n}\n',
    '# SBX Deploy: GitHub browser login\nauth_gh() {\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_gh [--force]\\n\' >&2; return 2 ;;\n    esac\n    unset GH_TOKEN GITHUB_TOKEN || return\n    if [[ ${1-} != --force ]] && command gh auth status --active --hostname github.com >/dev/null 2>&1; then\n        printf \'GitHub: already authenticated; skipping login.\\n\'\n        return 0\n    fi\n    # Scope the adapter and X11 backend selection to this gh process.\n    command env -u WAYLAND_DISPLAY \\\n        PATH="$HOME/.local/lib/sbx-deploy/gh-clipboard:$PATH" \\\n        gh auth login --hostname github.com --git-protocol https --web --clipboard\n}\n',
    '\n# SBX Deploy: custom system aliases\n# Custom aliases for ansible control\nalias playbook=\'ansible-playbook\'\nalias playtest=\'ansible-playbook -C\'\nalias playsyntax=\'ansible-playbook --syntax-check\'\n\n# List active permissions on a file or folder\nalias lperms=\'stat -c "%a %n"\'\n\n# Make a password hash\nalias makepass=\'python3 -c "from passlib.hash import sha512_crypt; import getpass; print(sha512_crypt.using(rounds=5000).hash(getpass.getpass()))"\'\n\n# Strip comments and blank lines from a configuration file\nalias configcat=\'grep -Ev "^$|^#"\'\n\n# Netstat aliases\nalias netstat-numeric=\'netstat -tulpn\'\nalias netstat-names=\'netstat -tulp\'\n',
    '# SBX Deploy: Codex OpenAI device-code login\nauth_codex_openai() {\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_codex_openai [--force]\\n\' >&2; return 2 ;;\n    esac\n    if [[ ${1-} != --force && ${SBX_CRED_OPENAI_MODE:-none} != oauth ]] &&\n       command env PATH="$HOME/.local/bin:$PATH" codex login status >/dev/null 2>&1; then\n        printf \'Codex: already authenticated; skipping login.\\n\'\n        return 0\n    fi\n    command env PATH="$HOME/.local/bin:$PATH" \\\n        "$HOME/.local/lib/sbx-deploy/auth-codex-openai-browser-tty"\n}\n',
    '# SBX Deploy: Codex OpenAI device-code login\nauth_codex_openai() {\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_codex_openai [--force]\\n\' >&2; return 2 ;;\n    esac\n    if [[ ${1-} != --force ]] &&\n       command env PATH="$HOME/.local/bin:$PATH" codex login status >/dev/null 2>&1; then\n        printf \'Codex: already authenticated; skipping login.\\n\'\n        return 0\n    fi\n    command env PATH="$HOME/.local/bin:$PATH" \\\n        "$HOME/.local/lib/sbx-deploy/auth-codex-openai-browser-tty"\n}\n',
    '# SBX Deploy: GitHub browser login\nlogin_gh() {\n    unset GH_TOKEN GITHUB_TOKEN || return\n    # Scope the adapter and X11 backend selection to this gh process.\n    command env -u WAYLAND_DISPLAY \\\n        PATH="$HOME/.local/lib/sbx-deploy/gh-clipboard:$PATH" \\\n        gh auth login --hostname github.com --git-protocol https --web --clipboard\n}\n',
    '# SBX Deploy: GitHub browser login\nauth_gh() {\n    unset GH_TOKEN GITHUB_TOKEN || return\n    # Scope the adapter and X11 backend selection to this gh process.\n    command env -u WAYLAND_DISPLAY \\\n        PATH="$HOME/.local/lib/sbx-deploy/gh-clipboard:$PATH" \\\n        gh auth login --hostname github.com --git-protocol https --web --clipboard\n}\n',
    '\n# SBX Deploy: authenticate all agents\nauth_all() {\n    case $#:${1-} in\n        0:|1:--force) ;;\n        *) printf \'Usage: auth_all [--force]\\n\' >&2; return 2 ;;\n    esac\n    auth_opencode_openai "$@" || return\n    auth_codex_openai "$@" || return\n    auth_gh "$@"\n}\n',
    '# SBX Deploy: Codex OpenAI device-code login\nauth_codex_openai() {\n    command env PATH="$HOME/.local/bin:$PATH" \\\n        "$HOME/.local/lib/sbx-deploy/auth-codex-openai-browser-tty" "$@"\n}\n',
    '# SBX Deploy: Codex OpenAI device-code login\nauth_codex_openai() {\n    command env PATH="$HOME/.local/bin:$PATH" \\\n        "$HOME/.local/lib/sbx-deploy/auth-codex-openai-tty" "$@"\n}\n',
    '# SBX Deploy: GitHub browser login\nlogin_gh() {\n    unset GH_TOKEN GITHUB_TOKEN || return\n    command gh auth login --hostname github.com --git-protocol https --web\n}\n',
    '# SBX Deploy: authenticate all agents\nauth_all() {\n    auth_opencode_openai || return\n    auth_codex_openai || return\n    auth_gh\n}\n',
    '# SBX Deploy: authenticate all agents\nauth_all() {\n    "$HOME/.local/lib/sbx-deploy/auth-openai-tty" || return\n    auth_gh\n}\n',
    '# SBX Deploy: OpenAI device-code login\nauth_opencode_openai() {\n    "$HOME/.local/lib/sbx-deploy/auth-openai-tty" "$@"\n}\n',
    "alias login_openai='/home/agent/.opencode/bin/opencode auth login openai --method chatgpt-headless'\n",
    "alias openai_login='/home/agent/.opencode/bin/opencode auth login openai --method chatgpt-headless'\n",
    '# SBX Deploy: authenticate all agents\nauth_all() {\n    auth_opencode_openai || return\n    auth_gh\n}\n',
    "alias auth_openai='/home/agent/.opencode/bin/opencode auth login openai --method chatgpt-headless'\n",
    'auth_all() {\n    auth_opencode_openai || return\n    auth_codex_openai || return\n    auth_gh\n}\n',
    'auth_all() {\n    "$HOME/.local/lib/sbx-deploy/auth-openai-tty" || return\n    auth_gh\n}\n',
    'auth_opencode_openai() {\n    "$HOME/.local/lib/sbx-deploy/auth-openai-tty" "$@"\n}\n',
    'alias check_connections=\'"$HOME/.local/bin/sbx_check_connections"\'\n',
    'alias check_credentials=\'"$HOME/.local/bin/sbx_check_credentials"\'\n',
    'alias auth_openai=\'"$HOME/.local/lib/sbx-deploy/auth-openai-tty"\'\n',
    'alias auth_openai=\'"$HOME/.local/lib/sbx-deploy/auth-openai"\'\n',
    'auth_all() {\n    auth_opencode_openai || return\n    auth_gh\n}\n',
    'alias auth_check=\'"$HOME/.local/bin/sbx-check-credentials"\'\n',
    'alias check_mcp=\'"$HOME/.local/bin/sbx_check_mcp"\'\n',
]
path_block = '# SBX Deploy: put the tmux wrapper on PATH\ncase $- in\n    *i*)\n        case ${PATH-} in\n            "$HOME/.local/bin"|"$HOME/.local/bin:"*) ;;\n            *) export PATH="$HOME/.local/bin${PATH:+:$PATH}" ;;\n        esac\n        ;;\nesac\n'
syslog_block = "# SBX Deploy: start sandbox logging on Bash startup\n# Clear BASH_ENV for the helper to avoid recursively sourcing this file.\nif [ -x /usr/local/sbin/sbx-local-syslog ]; then\n    if ! /usr/bin/sudo -n /usr/bin/env -u BASH_ENV /bin/bash /usr/local/sbin/sbx-local-syslog >/dev/null; then\n        printf 'SBX logging startup failed; run: sudo env -u BASH_ENV bash /usr/local/sbin/sbx-local-syslog\\n' >&2\n    fi\nfi\n"
loaders = {
    'global': '# SBX Deploy: interactive shell loader\ncase $- in *i*) source /usr/local/lib/sbx-deploy/shell.bash ;; esac\n',
    'path': '# SBX Deploy: PATH loader\nsource /usr/local/lib/sbx-deploy/path.bash\n',
    'syslog': syslog_block,
}
updated = original
for block in ([loaders[kind]] + (legacy if kind == 'global' else [path_block] if kind == 'path' else [])):
    # Duplicates are ambiguous, even if each copy looks familiar.
    if updated.count(block) > 1:
        sys.exit(f'Duplicate managed startup block: {source}; preserve/repair it before retrying.')
    updated = updated.replace(block, '', 1)
if '# SBX Deploy:' in updated or (kind == 'global' and re.search(
        r'(?m)^\s*(?:(?:auth_(?:gh|all|opencode_openai|codex_openai)|login_gh|short_path|_sbx_prompt)\s*\(\)|alias\s+(?:check_credentials|check_mcp|auth_openai|openai_login|login_openai|check_connections|auth_check)=)', updated)):
    sys.exit(f'Edited or partial managed startup block: {source}; preserve/repair it before retrying.')
# Keep unrelated text byte-for-byte. A matching loader is already in its final
# position; avoid removing/reappending it, which would accumulate blank lines.
if loaders[kind] in original and updated == original.replace(loaders[kind], '', 1):
    result = original
else:
    result = updated + ('' if not updated or updated.endswith('\n') else '\n') + loaders[kind]
staged.write_text(result)
SBX_MIGRATE_SHELL
startup_targets=() startup_sources=()
stage_startup() {
    local target=$1 kind=$2 staged="$work_dir/startup-${#startup_targets[@]}"
    python3 "$work_dir/migrate-shell.py" "$target" "$staged" "$kind"
    startup_targets+=("$target") startup_sources+=("$staged")
}
global_bashrc=/etc/bash.bashrc
[[ -f $global_bashrc && -r $global_bashrc ]] || die "Cannot read: $global_bashrc"
stage_startup "$global_bashrc" global
stage_startup "$HOME/.bashrc" path
login_file="$HOME/.profile"
for candidate in "$HOME/.bash_profile" "$HOME/.bash_login"; do
    if [[ -f $candidate && -r $candidate ]]; then login_file=$candidate; break; fi
done
stage_startup "$login_file" path
stage_startup /etc/sandbox-persistent.sh syslog
for ((i=0; i<${#managed_targets[@]}; i++)); do
    managed_preflight "${managed_targets[i]}" "${managed_sources[i]}" "${managed_modes[i]}"
done
for ((i=0; i<${#startup_targets[@]}; i++)); do
    assert_input "${startup_targets[i]}" "${startup_sources[i]}.input" "${startup_sources[i]}.exists"
done
for ((i=0; i<${#managed_targets[@]}; i++)); do
    install_managed_file "${managed_targets[i]}" "${managed_sources[i]}" "${managed_modes[i]}"
done
for ((i=0; i<${#startup_targets[@]}; i++)); do
    replace_system_file "${startup_sources[i]}" "${startup_targets[i]}" '' "${startup_sources[i]}.input" "${startup_sources[i]}.exists"
done
stage_operation 'Ensuring rsyslog and rotation are running'
run_as_root /usr/bin/env -u BASH_ENV /bin/bash /usr/local/sbin/sbx-local-syslog > "$work_dir/syslog-start"
cat -- "$work_dir/syslog-start"
if [[ -e $work_dir/changed || -s $work_dir/syslog-start ]]; then
    stage_done changed 'Updated managed helpers and shell loaders'
else
    stage_done unchanged 'Helpers and shell loaders match'
fi

stage_begin 'OpenCode' 'Checking upgrade'
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
    # Record successful upgrades locally to skip network checks on unchanged reruns.
    # Check again if the binary changes or the record is missing.
    if [[ -f $state_file && $(< "$state_file") == "$before" ]]; then
        return 0
    fi
    # Unattended upgrades must not wait for input from the calling terminal.
    timeout --kill-after="${kill_seconds}s" "${install_seconds}s" "$opencode_binary" upgrade --method curl </dev/null
    [[ -f $opencode_binary && -x $opencode_binary ]] ||
        die "OpenCode upgrade left no usable executable: $opencode_binary"
    after=$(sha256sum -- "$opencode_binary")
    # Record completion atomically after success. Retry interrupted or failed upgrades.
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

# Shared deployment defaults; each harness translates these to its own schema.
host_oauth=false
stage_begin 'Host credentials' 'Checking proxy-managed OpenAI configuration'
case ${SBX_CRED_OPENAI_MODE:-none} in
    oauth) host_oauth=true ;;
    *) : ;; # The credential stage reports this once, with recovery actions.
esac
# GitHub mode can lag host updates. Check live access before warning.
if "$host_oauth" && [[ -f $opencode_binary && -x $opencode_binary ]]; then
    # Import only the kit's masked bridge record. Keep exported credentials in memory.
    # Never put real local tokens in logs, temporary files, or backups.
    # Use the kit's lock to prevent concurrent startup imports.
    python3 - "$opencode_binary" "$oauth_access" "$oauth_refresh" "$work_dir/changed" "$credential_seconds" "$kill_seconds" <<'SBX_PROXY_OAUTH'
import json
import math
import os
from pathlib import Path
import subprocess
import sys

binary, access, refresh, changed = sys.argv[1:5]
credential_seconds, kill_seconds = map(int, sys.argv[5:])
data_home = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
if not data_home.is_absolute():
    sys.exit('OpenCode data directory must be absolute.')
directory = data_home / 'opencode'
source = directory / 'auth.json'
if source.is_symlink() or not source.is_file():
    sys.exit('Missing regular OpenCode OAuth bridge file; restart the sandbox after authorizing host OAuth.')
lock_path = directory / '.credentials-sync.lock'
try:
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
except OSError:
    sys.exit('Cannot open the OpenCode credential synchronization lock.')

def run(*args, payload=None):
    result = subprocess.run(['timeout', f'--kill-after={kill_seconds}s', f'{credential_seconds}s',
                             binary, 'auth', *args, '--standalone'],
                            input=payload, text=True, capture_output=True)
    if result.returncode:
        # Auth command diagnostics may contain secrets. Keep only its exit code.
        print('OpenCode credential command failed; output withheld to protect credentials.', file=sys.stderr)
        sys.exit(result.returncode if result.returncode > 0 else 128 - result.returncode)
    return result.stdout

with os.fdopen(lock_fd, 'w') as lock:
    result = subprocess.run(['flock', '--conflict-exit-code', '124', '--wait', str(credential_seconds), str(lock.fileno())],
                            pass_fds=(lock.fileno(),), capture_output=True)
    if result.returncode:
        print('Credential synchronization lock timed out; retry after the other import finishes.', file=sys.stderr)
        sys.exit(result.returncode)
    try:
        bridge = json.loads(source.read_text())
        record = bridge['openai']
        if (record['type'] != 'oauth' or record['access'] != access
                or record['refresh'] != refresh):
            raise ValueError()
        expires = float(record['expires'])
        if not math.isfinite(expires) or expires < 0 or not expires.is_integer():
            raise ValueError()
    except (OSError, ValueError, KeyError, TypeError, OverflowError):
        sys.exit('Expected Docker OAuth placeholders and a valid expiry; local credentials left unchanged.')
    value = dict(type='oauth', methodID='chatgpt-browser', access=access,
                 refresh=refresh, expires=int(expires))
    wanted = dict(id='sbx-openai', integrationID='openai', label='Sandbox OpenAI',
                  active=True, value=value)
    try:
        existing = json.loads(run('export'))
        if not isinstance(existing, list) or any(not isinstance(item, dict) for item in existing):
            raise ValueError()
    except (ValueError, TypeError):
        sys.exit('Cannot parse OpenCode credential inventory; credentials left unchanged.')
    matching = [item for item in existing if item.get('integrationID') == 'openai'
                and item.get('id') == wanted['id']]
    if len(matching) > 1:
        sys.exit('Duplicate managed OpenCode credential IDs; credentials left unchanged.')
    current = matching[0] if matching else None
    if current:
        stored = current.get('value')
        if not isinstance(stored, dict) or stored.get('access') != access or stored.get('refresh') != refresh:
            sys.exit('Managed OpenCode credential ID contains local data; refusing to replace it.')
    # Keep the saved selection. An inactive managed login is also a saved choice.
    if ((current and current.get('active') is not True)
            or any(item.get('integrationID') == 'openai'
                   and item.get('id') != wanted['id'] and item.get('active') is True
                   for item in existing)):
        sys.exit(0)
    if not current or current.get('value') != value:
        run('import', payload=json.dumps([wanted]))
        Path(changed).touch()
SBX_PROXY_OAUTH
fi
if [[ -e $work_dir/changed ]]; then
    stage_done changed 'Imported masked OpenCode OAuth from host bridge'
elif "$host_oauth"; then
    stage_done unchanged 'Saved authentication selection preserved'
else
    stage_done unchanged 'Host setup needed; local credentials preserved'
fi

# Track each deployed setting. Keep user changes, including deleted settings.
cat > "$work_dir/config_ownership.py" <<'SBX_CONFIG_OWNERSHIP'
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_record(path):
    if path.is_symlink() or (path.exists() and
            (not path.is_file() or path.stat().st_uid != os.getuid())):
        sys.exit(f'Unsafe ownership record: {path}. Preserve it and repair its ownership or links.')
    if not path.exists():
        return None
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
        if type(value['version']) is not int or value['version'] != 1 or not isinstance(value['settings'], dict):
            raise ValueError()
        if any(not isinstance(key, str) or type(item) not in (str, bool)
               for key, item in value['settings'].items()):
            raise ValueError()
        if path.suffix == '.pending':
            for key in ('before', 'after'):
                item = value[key]
                if item is not None and (not isinstance(item, str) or len(item) != 64 or
                                         any(char not in '0123456789abcdef' for char in item)):
                    raise ValueError()
        elif set(value) != {'version', 'settings'}:
            raise ValueError()
        return value
    except (ValueError, KeyError, TypeError):
        sys.exit(f'Invalid ownership record: {path}. Preserve it and restore a known good record.')


def atomic(path, value):
    fd, name = tempfile.mkstemp(prefix=path.name + '.tmp.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


class Ownership:
    def __init__(self, source, directory):
        self.source = source
        self.directory = Path(directory)
        if self.directory.is_symlink() or (self.directory.exists() and
                (not self.directory.is_dir() or self.directory.stat().st_uid != os.getuid())):
            sys.exit(f'Unsafe ownership directory: {self.directory}. Repair its ownership or links.')
        self.path = self.directory / (digest(str(source).encode()) + '.json')
        self.pending = self.path.with_suffix('.pending')
        self.saved = read_record(self.path)
        self.transaction = read_record(self.pending)
        self.before = digest(source.read_bytes()) if source.exists() else None
        active = self.saved
        if self.transaction:
            if self.before == self.transaction['after']:
                active = self.transaction
            elif self.before != self.transaction['before']:
                sys.exit(f'Configuration changed during an interrupted update: {source}. '
                         'Preserve the file and ownership records. Restore the pre-update file '
                         'from its deployment backup, then rerun.')
        self.settings = dict(active['settings']) if active else {}

    def unknown(self, label):
        sys.exit(f'Unknown deployment ownership: {self.source}, setting {label}. '
                 f'File preserved. Move the config and these records, if present, to safe backup paths: '
                 f'{self.path}, {self.pending}. Rerun to create managed defaults. '
                 'Copy your custom settings into the new config. Keep the backups. '
                 'Do not copy credentials into deployment records.')

    def select(self, data, desired, prefix=()):
        selected = {}
        for key, wanted in desired.items():
            location = prefix + (key,)
            label = '.'.join(location)
            present = key in data
            if isinstance(wanted, dict):
                current = data.get(key, {})
                if not isinstance(current, dict):
                    sys.exit(f'Expected an object or table at {label} in {self.source}. File preserved.')
                children = self.select(current, wanted, location)
                if children:
                    selected[key] = children
                continue
            if label in self.settings:
                if not present or type(data[key]) is not type(self.settings[label]) or data[key] != self.settings[label]:
                    continue
            elif present:
                # Matching values need no change. Do not claim their ownership.
                if type(data[key]) is type(wanted) and data[key] == wanted:
                    continue
                self.unknown(label)
            selected[key] = wanted
            self.settings[label] = wanted
        return selected

    def prepare(self, staged):
        after = digest(staged.read_bytes()) if staged.exists() else self.before
        record = dict(version=1, settings=self.settings)
        if self.saved == record and not self.transaction:
            return
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        pending = dict(record, before=self.before, after=after)
        if self.transaction != pending:
            atomic(self.pending, pending)

    def commit(self):
        if not self.transaction:
            return
        if self.before != self.transaction['after']:
            sys.exit(f'Configuration publication did not finish: {self.source}. Rerun the installer.')
        record = dict(version=1, settings=self.transaction['settings'])
        if self.saved != record:
            atomic(self.path, record)
        self.pending.unlink()


if __name__ == '__main__':
    Ownership(Path(sys.argv[1]), sys.argv[2]).commit()
SBX_CONFIG_OWNERSHIP

stage_begin 'OpenCode defaults' 'Checking shared models and MCP gateway'
opencode_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
[[ $opencode_config_dir == /* ]] || die 'OpenCode configuration directory must be absolute.'
# JSONC takes precedence when both files exist. Edit only the effective file.
opencode_config="$opencode_config_dir/opencode.json"
if exists "$opencode_config_dir/opencode.jsonc"; then
    opencode_config="$opencode_config_dir/opencode.jsonc"
fi
if exists "$opencode_config"; then
    [[ -f $opencode_config && -r $opencode_config && ! -L $opencode_config ]] ||
        die "OpenCode configuration must be a readable regular file, not a symlink: $opencode_config"
fi
# Mask JSONC comments and trailing commas without changing character offsets.
# Update owned settings. Preserve user overrides, other text, and comments.
PYTHONPATH="$work_dir${PYTHONPATH:+:$PYTHONPATH}" python3 - "$opencode_config" "$work_dir/opencode-model.json" "$main_model" "$subagent_model" "$mcp_gateway_url" "$log_dir/config-ownership" <<'SBX_OPENCODE_MODEL'
import json
from pathlib import Path
import re
import sys

source, staged = map(Path, sys.argv[1:3])
main_model, subagent_model = ('openai/' + model for model in sys.argv[3:5])
gateway_url = sys.argv[5]
from config_ownership import Ownership
ownership = Ownership(source, sys.argv[6])
desired = {
    "model": main_model,
    "mcp": {"mcp-gateway": {"type": "remote", "url": gateway_url, "enabled": True}},
    "agents": {
        "build": {"model": main_model},
        "plan": {"model": main_model},
        "general": {"model": subagent_model},
        "explore": {"model": subagent_model},
    },
}
existed = source.exists()
if existed:
    with source.open(encoding="utf-8", newline="") as handle:
        original = handle.read()
else:
    original = '{\n  "$schema": "https://opencode.ai/config.json"\n}\n'

Path(str(staged) + '.input').write_bytes(original.encode('utf-8') if existed else b'')
Path(str(staged) + '.exists').write_text(str(existed))

# Match strings first so comment markers inside strings remain untouched.
tokens = r'"(?:\\.|[^"\\])*"|//[^\r\n]*|/\*[\s\S]*?\*/'
clean = re.sub(tokens, lambda m: m[0] if m[0].startswith('"') else
               re.sub(r'[^\r\n]', ' ', m[0]), original)
clean = re.sub(r'"(?:\\.|[^"\\])*"|,(\s*[}\]])',
               lambda m: ' ' + m[1] if m[1] is not None else m[0], clean)
try:
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate configuration key. Remove duplicate keys before rerun.')
            result[key] = value
        return result
    data = json.loads(clean, object_pairs_hook=unique_object)
except ValueError as error:
    sys.exit(f"Cannot parse OpenCode configuration {source}: {error}")
if not isinstance(data, dict):
    sys.exit(f"OpenCode configuration must contain an object: {source}")

gateway = data.get('mcp', {}).get('mcp-gateway', {}) if isinstance(data.get('mcp', {}), dict) else {}
if isinstance(gateway, dict) and ('command' in gateway or gateway.get('type', 'remote') != 'remote'):
    if any(key.startswith('mcp.mcp-gateway.') for key in ownership.settings):
        del desired['mcp']
    else:
        ownership.unknown('mcp.mcp-gateway')
desired = ownership.select(data, desired)

# Visit only managed object paths. Preserve other settings.
# Stop if a managed object has an unexpected type.
decoder = json.JSONDecoder()
edits = []
newline = '\r\n' if '\r\n' in original else '\n'

def skip_space(position):
    while clean[position].isspace():
        position += 1
    return position

def update_object(start, wanted):
    if clean[start] != '{':
        sys.exit(f"Expected an object for managed settings in {source}")
    position = start + 1
    seen = set()
    has_members = False
    while True:
        position = skip_space(position)
        if clean[position] == '}':
            break
        key, position = decoder.raw_decode(clean, position)
        position = skip_space(position) + 1  # Validated colon.
        value_start = skip_space(position)
        value, position = decoder.raw_decode(clean, value_start)
        seen.add(key)
        has_members = True
        if key in wanted:
            replacement = wanted[key]
            if isinstance(replacement, dict):
                update_object(value_start, replacement)
            elif value != replacement:
                edits.append((value_start, position, json.dumps(replacement)))
        position = skip_space(position)
        if clean[position] == ',':
            position += 1
    missing = {key: value for key, value in wanted.items() if key not in seen}
    if missing:
        members = (json.dumps(key) + ': ' + json.dumps(value)
                   for key, value in missing.items())
        addition = newline + '  ' + (',' + newline + '  ').join(members)
        addition += ',' if has_members else ''
        edits.append((start + 1, start + 1, addition))

update_object(clean.index('{'), desired)
updated = original
for start, end, replacement in sorted(edits, reverse=True):
    updated = updated[:start] + replacement + updated[end:]
if updated != original or not source.exists():
    with staged.open('w', encoding='utf-8', newline='') as handle:
        handle.write(updated)
ownership.prepare(staged)
SBX_OPENCODE_MODEL
install_opencode_model() (
    local staged=
    trap 'if [[ -n $staged ]]; then rm -f -- "$staged"; fi' EXIT
    if exists "$opencode_config"; then
        replace_system_file "$work_dir/opencode-model.json" "$opencode_config" '' "$work_dir/opencode-model.json.input" "$work_dir/opencode-model.json.exists"
    else
        mkdir -p -- "$opencode_config_dir"
        staged=$(umask 077; mktemp -- "$opencode_config.tmp.XXXXXX")
        cat -- "$work_dir/opencode-model.json" > "$staged"
        # Publish without overwriting a concurrently created configuration.
        # Keep a new config private and owned by the invoking sandbox user.
        ln -T -- "$staged" "$opencode_config"
    fi
)
if [[ -f $work_dir/opencode-model.json ]]; then
    install_opencode_model
    stage_done changed 'Owned defaults updated; overrides preserved'
else
    stage_done unchanged 'Owned defaults checked; overrides preserved'
fi
python3 "$work_dir/config_ownership.py" "$opencode_config" "$log_dir/config-ownership"

stage_begin 'Codex defaults' 'Checking models, host OAuth and MCP gateway'
codex_config_dir="${CODEX_HOME:-$HOME/.codex}"
[[ $codex_config_dir == /* ]] || die 'Codex configuration directory must be absolute.'
codex_config="$codex_config_dir/config.toml"
if exists "$codex_config"; then
    [[ -f $codex_config && -r $codex_config && ! -L $codex_config ]] ||
        die "Codex configuration must be a readable regular file, not a symlink: $codex_config"
fi
# TOMLKit preserves comments and unrelated settings, including other MCP servers.
# Parse before publishing; matching settings leave the existing file untouched.
PYTHONPATH="$work_dir${PYTHONPATH:+:$PYTHONPATH}" python3 - "$codex_config" "$work_dir/codex-model.toml" "$main_model" "$subagent_model" \
    "$host_oauth" "$oauth_provider" "$oauth_base_url" "$oauth_access" "$mcp_gateway_url" "$log_dir/config-ownership" <<'SBX_CODEX_MODEL'
from pathlib import Path
import sys
import tomlkit

source, staged = map(Path, sys.argv[1:3])
main_model, subagent_model = sys.argv[3:5]
host_oauth, provider_id, base_url, access = sys.argv[5:9]
gateway_url = sys.argv[9]
from config_ownership import Ownership
ownership = Ownership(source, sys.argv[10])
existed = source.exists()
original = source.read_bytes().decode('utf-8') if existed else ''
Path(str(staged) + '.input').write_bytes(original.encode('utf-8'))
Path(str(staged) + '.exists').write_text(str(existed))
try:
    config = tomlkit.parse(original)
except tomlkit.exceptions.ParseError:
    sys.exit(f'Cannot parse Codex configuration: {source}')
servers = config.get('mcp_servers', {})
gateway = servers.get('mcp-gateway', {}) if hasattr(servers, 'get') else {}
desired = {
    'model': main_model,
    'agents': {'enabled': True, 'default_subagent_model': subagent_model},
    'mcp_servers': {'mcp-gateway': {'url': gateway_url, 'enabled': True}},
}
if hasattr(gateway, 'get') and 'command' in gateway:
    if any(key.startswith('mcp_servers.mcp-gateway.') for key in ownership.settings):
        del desired['mcp_servers']
    else:
        ownership.unknown('mcp_servers.mcp-gateway')
# Unwrap TOMLKit values for ownership checks. Keep its document for editing.
selected = ownership.select(config.unwrap(), desired)
changed = False

def apply(table, wanted):
    global changed
    for key, value in wanted.items():
        if isinstance(value, dict):
            if key not in table:
                table[key] = tomlkit.table()
            apply(table[key], value)
        elif table.get(key) != value:
            table[key] = value
            changed = True

apply(config, selected)
if host_oauth == 'true':
    if 'model_providers' not in config:
        config['model_providers'] = tomlkit.table()
    providers = config['model_providers']
    if not isinstance(providers, (tomlkit.items.Table, tomlkit.items.InlineTable)):
        sys.exit('Codex model_providers must be a table.')
    desired = dict(name='SBX host ChatGPT OAuth', base_url=base_url,
                   wire_api='responses', experimental_bearer_token=access,
                   requires_openai_auth=False)
    if provider_id in providers:
        provider = providers[provider_id]
        if (not isinstance(provider, (tomlkit.items.Table, tomlkit.items.InlineTable))
                or dict(provider) != desired):
            sys.exit('Existing sbx-chatgpt provider differs; refusing to replace user settings.')
    if provider_id not in providers:
        providers[provider_id] = desired
        changed = True
    # An explicit provider is a saved choice. A local auth file also preserves
    # the built-in provider when model_provider is absent. Do not read its tokens.
    auth_file = source.parent / 'auth.json'
    if 'model_provider' not in config and not (auth_file.exists() or auth_file.is_symlink()):
        config['model_provider'] = provider_id
        changed = True
# Do not create or copy auth.json. The provider contains only the shared Docker placeholder.
# The host proxy manages real tokens and refresh. Successful local login restores the built-in provider.
if changed or not source.exists():
    staged.write_text(tomlkit.dumps(config), encoding='utf-8', newline='')
ownership.prepare(staged)
SBX_CODEX_MODEL
install_codex_model() (
    local staged=
    trap 'if [[ -n $staged ]]; then rm -f -- "$staged"; fi' EXIT
    if exists "$codex_config"; then
        replace_system_file "$work_dir/codex-model.toml" "$codex_config" '' "$work_dir/codex-model.toml.input" "$work_dir/codex-model.toml.exists"
    else
        mkdir -p -- "$codex_config_dir"
        staged=$(umask 077; mktemp -- "$codex_config.tmp.XXXXXX")
        cat -- "$work_dir/codex-model.toml" > "$staged"
        # Publish privately without overwriting a concurrently created config.
        ln -T -- "$staged" "$codex_config"
    fi
)
if [[ -f $work_dir/codex-model.toml ]]; then
    install_codex_model
    stage_done changed 'Owned defaults updated; saved authentication preserved'
else
    stage_done unchanged 'Owned defaults checked; overrides preserved'
fi

python3 "$work_dir/config_ownership.py" "$codex_config" "$log_dir/config-ownership"

# Read-only probes cache successes by local setup. Store hashes, never credential values.
# Host secrets can change without detection. SBX_CHECK_AUTH=1 repeats cached checks.
# Never cache failures. Keep probe output private and out of installer logs.
# Report only statuses and known commands.
case ${SBX_CHECK_AUTH:-0} in
    0|1) ;;
    *) die 'SBX_CHECK_AUTH must be 0 or 1.' ;;
esac
check_credential() {
    local service=$1 cache fingerprint output status code binary codex_binary path
    stage_begin "$2" 'Checking credentials through the host proxy'
    cache="$log_dir/auth-$service.sha256"
    if exists "$cache"; then
        [[ -f $cache && ! -L $cache && -r $cache ]] || die "Cannot read credential-check cache: $cache"
    fi
    binary=$(type -P gh || :)
    codex_binary=$(PATH="$HOME/.local/bin:$PATH" type -P codex || :)
    # Hash routing, modes, binaries, and managed configuration.
    # Hash token variables directly. Never print or store their values.
    fingerprint=$({
        printf '%s\0' 'sbx-auth-check-v1' "$service" \
            "${SBX_CRED_OPENAI_MODE:-none}" "${SBX_CRED_GITHUB_MODE:-none}" \
            "${GH_TOKEN-}" "${GITHUB_TOKEN-}" "${GH_HOST-}" "${GH_CONFIG_DIR-}" \
            "${HTTPS_PROXY-}" "${https_proxy-}" "${HTTP_PROXY-}" "${http_proxy-}" \
            "${NO_PROXY-}" "${no_proxy-}" "$oauth_base_url" "$oauth_access"
        for path in "$binary" "$codex_binary" "$opencode_binary" "$codex_config" "$opencode_config" \
            "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"; do
            if [[ -f $path ]]; then sha256sum -- "$path"; fi
        done
    } | sha256sum)
    if [[ ${SBX_CHECK_AUTH:-0} != 1 && -f $cache && $(< "$cache") == "$fingerprint" ]]; then
        printf -v "${service}_auth_status" '%s' 'previously verified (cached)'
        stage_done unchanged 'Previously verified (cached)'
        return 0
    fi
    # Invalidate old success before a fresh probe, including failures or interruption.
    if exists "$cache"; then
        rm -f -- "$cache"
    fi
    code= status=0
    if [[ $service == github ]]; then
        if output=$(timeout --kill-after="${kill_seconds}s" 25s env GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 GH_DEBUG= \
            gh api --hostname github.com user --jq .login 2> "$work_dir/auth-probe.stderr"); then
            if [[ -n $output && $output != *$'\n'* && $output != *[!a-zA-Z0-9-]* ]]; then
                code=200
            else
                code=unexpected
            fi
        else
            status=$?
            code=$(sed -nE 's/.*HTTP ([0-9]{3}).*/\1/p' "$work_dir/auth-probe.stderr" | tail -n 1)
        fi
    elif ! "$host_oauth"; then
        openai_auth_status='needs attention'
        record_issue openai OpenAI 'Host OAuth is not configured.' $'Windows PowerShell:\n  sbx secret set openai --oauth\nConfigure the OAuth binding using HOST_SETUP_WIN.md, then restart the sandbox.\nSandbox Bash after repair:\n  SBX_CHECK_AUTH=1 bash ~/sbx_local_opencode_deploy.sh'
        stage_done attention 'Host OAuth needs setup; see final actions'
        return 0
    else
        # Use Codex's authenticated model-list route. This generates no text or agent task.
        # It does not verify inference permissions.
        output=$(timeout --kill-after="${kill_seconds}s" "${version_seconds}s" env PATH="$HOME/.local/bin:$PATH" codex --version)
        if [[ $output =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            output=${BASH_REMATCH[1]}
        else
            die 'Cannot determine the Codex version for the OAuth credential check.'
        fi
        if code=$(curl --disable --silent --show-error --connect-timeout 10 --max-time 25 \
            --output /dev/null --write-out '%{http_code}' \
            --header "Authorization: Bearer $oauth_access" \
            "$oauth_base_url/models?client_version=$output" 2> "$work_dir/auth-probe.stderr"); then
            :
        else
            status=$?
        fi
    fi
    if [[ $code == 200 && $status == 0 ]]; then
        auth_cache_staged=$(umask 077; mktemp -- "$cache.tmp.XXXXXX")
        printf '%s\n' "$fingerprint" > "$auth_cache_staged"
        mv -fT -- "$auth_cache_staged" "$cache"
        auth_cache_staged=
        printf -v "${service}_auth_status" '%s' verified
        if [[ $service == github ]]; then
            stage_done verified 'GitHub account request accepted'
        else
            stage_done verified 'Shared OpenAI OAuth accepts model-list requests'
        fi
        return 0
    fi
    local detail="$service credential check failed (HTTP ${code:-unknown}, exit $status)." actions
    printf -v "${service}_auth_status" '%s' 'needs attention'
    case $code in
        401)
            if [[ $service == github ]]; then
                actions=$'Windows PowerShell:\n  gh api user --jq .login\nIf the host check succeeds, restart the daemon:\n  sbx daemon restart\nRestarting can interrupt sandbox sessions.\nIf the host check fails, repair host login using HOST_SETUP_WIN.md.'
            else
                actions=$'Windows PowerShell:\n  sbx secret ls\nIf OAuth needs renewal:\n  sbx secret set openai --oauth\nCheck the OAuth binding using HOST_SETUP_WIN.md.'
            fi ;;
        403) actions='Check host credential permissions and sandbox network policy; see HOST_SETUP_WIN.md.' ;;
        429) actions='Rate limit reached; retry later.' ;;
        5??) actions='Service or proxy error; retry later. If it persists, inspect host proxy logs using HOST_SETUP_WIN.md.' ;;
        *) actions='Check sandbox connectivity, proxy and CA trust using HOST_SETUP_WIN.md. A timeout does not prove bad credentials.' ;;
    esac
    actions+=$'\nSandbox Bash after repair:\n  SBX_CHECK_AUTH=1 bash ~/sbx_local_opencode_deploy.sh'
    record_issue "$service" "$2" "$detail" "$actions"
    stage_done attention 'Authentication unverified; see final actions'
}
check_credential github 'GitHub auth'
check_credential openai 'OpenAI auth'

stage_begin 'Webtop' 'Checking optional desktop'
webtop_choice=n
webtop_image=lscr.io/linuxserver/webtop:ubuntu-xfce
webtop_id=
webtop_docker_available=false
if command -v docker >/dev/null 2>&1; then
    # Read local state before prompting. Do not start or configure Docker here.
    if docker info >/dev/null 2> "$work_dir/webtop-docker.stderr"; then
        webtop_docker_available=true
        webtop_id=$(docker container ls -a --filter 'name=^/webtop$' --format '{{.ID}}')
    fi
fi
if [[ -n $webtop_id ]]; then
    docker inspect "$webtop_id" > "$work_dir/webtop-container.json"
    # Preserve existing containers and volumes, including incomplete user deployments.
    # Stop if the name conflicts.
    webtop_status=$(python3 - "$work_dir/webtop-container.json" "$webtop_image" <<'SBX_WEBTOP_INSPECT'
import json
from pathlib import Path
import sys

container = json.loads(Path(sys.argv[1]).read_text())[0]
if container['Config']['Image'] != sys.argv[2]:
    sys.exit('Existing webtop uses a different image; preserve it and resolve the name conflict manually.')
mounts = container.get('Mounts', [])
if not any(m.get('Destination') == '/config' and m.get('Type') == 'volume'
           and m.get('Name') == 'webtop-config' and m.get('RW') for m in mounts):
    sys.exit('Existing webtop has different config storage; preserve it and resolve the conflict manually.')
bindings = container['HostConfig'].get('PortBindings') or {}
if not any(p.get('HostPort') == '3001' and p.get('HostIp', '') in ('', '0.0.0.0')
           for p in (bindings.get('3001/tcp') or [])):
    sys.exit('Existing webtop needs sandbox port 3001 mapped to container port 3001; no container was replaced.')
state = container['State']
if state.get('Paused') or state.get('Restarting') or state.get('Dead'):
    sys.exit('Existing webtop is paused, restarting or dead; repair it before rerunning.')
print('running' if state['Running'] else 'stopped')
SBX_WEBTOP_INSPECT
    )
fi
if [[ -z $webtop_id ]]; then
    # Descriptor 6 holds the caller's stdin. It excludes the literal installer heredoc.
    # Never read pasted payloads or pending shell commands as answers.
    stop_spinner
    drain_output
    prompt_fd=
    if [[ -t 6 ]]; then
        prompt_fd=6
    elif { exec 7</dev/tty; } 2>/dev/null; then
        prompt_fd=7
    fi
    if [[ -n $prompt_fd ]]; then
        while :; do
            printf '\nDeploy Webtop desktop? [y/N]: ' >&3
            if ! IFS= read -r -u "$prompt_fd" webtop_choice; then
                webtop_choice=n
                printf '\n' >&3
                break
            fi
            case ${webtop_choice,,} in
                y|yes) webtop_choice=y; break ;;
                n|no|'') webtop_choice=n; break ;;
                *) printf 'Please enter y or n.\n' >&3 ;;
            esac
        done
        [[ $prompt_fd != 7 ]] || exec 7<&-
    else
        printf '\nNo terminal input; optional Webtop deployment skipped.\n' >&3
    fi
    capture_output
    start_spinner
fi
printf 'Webtop deployment requested: %s\n' "$webtop_choice" >> "$log_file"
if [[ $webtop_docker_available != true ]]; then
    if [[ $webtop_choice == y ]]; then
        if command -v docker >/dev/null 2>&1; then
            cat -- "$work_dir/webtop-docker.stderr" >&2
            die 'Webtop needs access to the sandbox Docker Engine; repair Docker and rerun.'
        fi
        die 'Webtop needs Docker inside the sandbox; use an SBX image with Docker and rerun.'
    elif command -v docker >/dev/null 2>&1; then
        warn 'Docker unavailable; existing Webtop status could not be checked.'
    fi
fi
if [[ $webtop_choice == y ]]; then
    stage_operation 'Creating Ubuntu XFCE desktop (first download may take time)'
    # Docker reuses a local image; never pull/update it on an identical rerun.
    # If a failed start leaves a matching container, use docker start webtop.
    if docker run -d --name webtop --shm-size=1gb --restart unless-stopped \
        -p 3001:3001 -v webtop-config:/config "$webtop_image" 2>&1 | tee -- "$work_dir/webtop-start.output"; then
        :
    else
        status=$?
        if grep -Fq '403 Forbidden' "$work_dir/webtop-start.output"; then
            record_issue webtop-registry 'Webtop registry access' \
                'Registry access returned 403 Forbidden. The host network policy can block Webtop downloads.' \
                $'Windows PowerShell:\n  sbx policy check network lscr.io:443\nIf no allow rule matches:\n  sbx policy allow network lscr.io:443\nThis changes the global policy. An explicit deny takes precedence.\nSee HOST_SETUP_WIN.md for other registry domains.\nSandbox Bash after repair:\n  bash ~/sbx_local_opencode_deploy.sh'
        fi
        die 'Webtop could not start; see the Docker error and final actions.' "$status"
    fi
    webtop_status=running
    stage_done changed 'Deployed Ubuntu XFCE desktop'
elif [[ -n $webtop_id ]]; then
    stage_done unchanged "Existing desktop $webtop_status; prompt skipped"
else
    stage_done unchanged 'Optional desktop skipped'
fi
)
SBX_DEPLOY_PAYLOAD
)
# Do not guard the installer with if or &&. That disables errexit inside.
# Bash parses the outer brace before execution to protect pasted input.
case $? in
    0)
        if [[ $- == *i* && ${BASH_SOURCE[0]:-} != "$0" ]]; then
            case ${PATH-} in
                "$HOME/.local/bin"|"$HOME/.local/bin:"*) ;;
                *) export PATH="$HOME/.local/bin${PATH:+:$PATH}" ;;
            esac
            hash -r
            if source /etc/bash.bashrc; then
                :
            else
                printf '\nWARN Could not reload shell setup; run: source /etc/bash.bashrc\n' >&2
            fi
        fi
        ;;
    *) (exit "$?") ;; # Preserve failure status without exiting a pasted shell.
esac
}
