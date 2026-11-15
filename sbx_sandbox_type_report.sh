#!/usr/bin/env bash
# Collect clues to compare local and cloud SBX sandboxes. Do not select a type.
# Paste this complete file into sandbox Bash in one local and one cloud sandbox.
# Label each report LOCAL or CLOUD before sharing. Leave SBX_ENV unchanged.
# Install nothing, write no files, and make no network requests.
# Print selected variable names and fixed categories, not raw variable values.
# Do not read credential files or print tokens, sandbox IDs, or mount sources.
# Use a subshell to keep strict mode and report variables out of the caller shell.
(
set -euo pipefail
printf 'SBX local/cloud sandbox type report v1\n'
# Check the hostname pattern without printing the hostname.
case ${HOSTNAME:-} in
    '') printf 'hostname: unset\n' ;;
    *)
        if [[ $HOSTNAME =~ ^sbx-[a-z0-9]{27}$ ]]; then
            printf 'hostname: cloud-pattern\n'
        else
            printf 'hostname: other\n'
        fi ;;
esac
printf '\nExported variable names (no values):\n'
# List relevant exported names. A name alone does not prove the sandbox type.
while IFS= read -r sbx_report_name; do
    [[ $sbx_report_name =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,79}$ ]] || continue
    case $sbx_report_name in
        SBX_*|SANDBOX*|MCP_*|DOCKER_*|DHI_*|CLOUD_*|KUBERNETES_*|AWS_*|ECS_*|NOMAD_*|KATA_*|CONTAINER*|container|HOSTNAME|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|http_proxy|https_proxy|all_proxy|no_proxy)
            printf '  %s\n' "$sbx_report_name" ;;
    esac
done < <(compgen -e | LC_ALL=C sort)
printf '\nCredential mode categories:\n'
# Convert credential mode labels to fixed categories. Do not inspect credentials.
for sbx_report_name in SBX_CRED_OPENAI_MODE SBX_CRED_GITHUB_MODE; do
    case ${!sbx_report_name-unset} in
        oauth) sbx_report_category=oauth ;;
        apiKey|apikey) sbx_report_category=api-key ;;
        none) sbx_report_category=none ;;
        unset) sbx_report_category=unset ;;
        *) sbx_report_category=other ;;
    esac
    printf '  %s: %s\n' "$sbx_report_name" "$sbx_report_category"
done
printf '\nPath markers (no file contents):\n'
# Check marker paths without reading their contents.
for sbx_report_path in /.dockerenv /run/.containerenv /etc/sandbox-persistent.sh /run/ssh-agent.sock /sys/hypervisor/type /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name; do
    sbx_report_category=absent
    if [[ -e $sbx_report_path || -L $sbx_report_path ]]; then sbx_report_category=present; fi
    printf '  %s: %s\n' "$sbx_report_path" "$sbx_report_category"
done
printf '\nVirtual machine categories:\n'
# Read machine labels and print only the matching category.
for sbx_report_path in /sys/hypervisor/type /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name; do
    sbx_report_value=
    if [[ -r $sbx_report_path ]]; then IFS= read -r sbx_report_value < "$sbx_report_path" || :; fi
    case ${sbx_report_value,,} in
        *amazon*|*ec2*) sbx_report_category=amazon ;;
        *firecracker*) sbx_report_category=firecracker ;;
        *cloud*hypervisor*) sbx_report_category=cloud-hypervisor ;;
        *docker*) sbx_report_category=docker ;;
        *qemu*|*kvm*) sbx_report_category=qemu-kvm ;;
        *microsoft*|*hyper-v*) sbx_report_category=microsoft ;;
        *xen*) sbx_report_category=xen ;;
        '') sbx_report_category=unavailable ;;
        *) sbx_report_category=other ;;
    esac
    printf '  %s: %s\n' "$sbx_report_path" "$sbx_report_category"
done
printf '\nFilesystem types (no mount sources):\n'
# Print filesystem types for fixed locations. Keep home paths out of the output.
for sbx_report_path in / "$HOME" "$HOME/workspace"; do
    sbx_report_category=unavailable
    if [[ -d $sbx_report_path ]] && command -v stat >/dev/null 2>&1; then
        sbx_report_category=$(stat -f -c '%T' -- "$sbx_report_path" 2>/dev/null) || sbx_report_category=unavailable
    fi
    [[ $sbx_report_category =~ ^[a-zA-Z0-9_.-]{1,64}$ ]] || sbx_report_category=other
    case $sbx_report_path in
        /) sbx_report_label=root ;;
        "$HOME") sbx_report_label=home ;;
        *) sbx_report_label=workspace ;;
    esac
    printf '  %s: %s\n' "$sbx_report_label" "$sbx_report_category"
done
printf '\nEnd of report. Label this output LOCAL or CLOUD before sharing.\n'
)
