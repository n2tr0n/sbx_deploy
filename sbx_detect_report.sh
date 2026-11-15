#!/usr/bin/env bash
# Paste this complete file into Bash in one local and one cloud sandbox.
# Report detection clues. Do not install tools, write files, or use the network.
# Print environment variable names and fixed categories. Never print their values.
(
set -euo pipefail
printf 'SBX detection report v1\n'
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
while IFS= read -r sbx_report_name; do
    [[ $sbx_report_name =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,79}$ ]] || continue
    case $sbx_report_name in
        SBX_*|SANDBOX*|MCP_*|DOCKER_*|DHI_*|CLOUD_*|KUBERNETES_*|AWS_*|ECS_*|NOMAD_*|KATA_*|CONTAINER*|container|HOSTNAME|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|http_proxy|https_proxy|all_proxy|no_proxy)
            printf '  %s\n' "$sbx_report_name" ;;
    esac
done < <(compgen -e | LC_ALL=C sort)
printf '\nCredential mode categories:\n'
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
for sbx_report_path in /.dockerenv /run/.containerenv /etc/sandbox-persistent.sh /run/ssh-agent.sock /sys/hypervisor/type /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name; do
    sbx_report_category=absent
    if [[ -e $sbx_report_path || -L $sbx_report_path ]]; then sbx_report_category=present; fi
    printf '  %s: %s\n' "$sbx_report_path" "$sbx_report_category"
done
printf '\nVirtual machine categories:\n'
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
