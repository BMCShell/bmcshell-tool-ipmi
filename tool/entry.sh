#!/usr/bin/env bash
# Run through the trusted BMCShell Bash-tool bridge.

_bmcshell_v2tools_read_auth() (
    local root=$1 _BMC_ACTIVE=1
    local +x _BMC_INPUT_USER='' _BMC_INPUT_PASSWORD=''
    builtin source "$root/compat/common.sh" || return
    builtin source "$root/compat/input.sh" || return
    builtin source "$root/compat/auth.sh" || return
    _bmc_read_credentials || return
    builtin printf '%s\n%s' "$_BMC_INPUT_USER" "$_BMC_INPUT_PASSWORD"
)

_bmcshell_v2tools_auth() {
    local root=$1 tls=verify
    local +x payload
    shift
    case $#:${1-} in
        0:) ;;
        1:--tls-insecure) tls=insecure ;;
        1:--clear)
            builtin unset '_BMCSHELL_SESSION_STATE[v2.user]' '_BMCSHELL_SESSION_STATE[v2.password]' '_BMCSHELL_SESSION_STATE[v2.tls]'
            builtin printf '已清除当前会话的 V2 登录凭据。\n'
            return 0
            ;;
        *) builtin printf '用法：bmc_v2_auth [--tls-insecure|--clear]\n' >&2; return 2 ;;
    esac
    payload=$(_bmcshell_v2tools_read_auth "$root") || return
    _BMCSHELL_SESSION_STATE[v2.user]=${payload%%$'\n'*}
    _BMCSHELL_SESSION_STATE[v2.password]=${payload#*$'\n'}
    _BMCSHELL_SESSION_STATE[v2.tls]=$tls
    builtin printf 'V2 登录凭据已载入当前会话，等待工具实际验证。\n'
}

_bmcshell_v2tools_register_shims() {
    _bmc_register_plugin() { :; }
    _bmc_register_verifier() { :; }
    _bmc_register_tool() { :; }
    _bmc_require_plugin() { [[ $1 == ipmi ]] && builtin declare -F _bmc_ipmi_wrapper >/dev/null; }
    _bmc_require_active() { [[ $_BMC_ACTIVE == 1 ]]; }
    _bmc_preview_enabled() { return 1; }
    _bmc_show_command() { :; }
    _bmc_tool() { bmc tool "$1"; }
    _bmc_exit() { :; } # The caller exits the parent shell session after a successful reset.
    _bmc_winpath() { command cygpath -aw -- "$1"; }
    _bmc_config_dir() {
        local path=${BMC_CONFIG_DIR:-$HOME/.config/bmc-shell}
        if [[ $path =~ ^[a-zA-Z]: ]]; then command cygpath -u -- "$path"
        else builtin printf '%s\n' "$path"; fi
    }
}

_bmcshell_v2tools_snmp_setup() {
    local root=$1 ip=$2 action=$3 version=${4:-2c}
    local +x community
    if [[ $action == -r || $action == --clear ]]; then
        (( $# == 3 )) || { builtin printf '用法：snmp -r\n' >&2; return 2; }
        builtin unset '_BMCSHELL_SESSION_STATE[v2.snmp_version]' '_BMCSHELL_SESSION_STATE[v2.snmp_community]'
        builtin printf 'Current SNMP community cleared.\n'
        return 0
    fi
    if (( $# > 4 )) || [[ $version != 1 && $version != 2c ]]; then
        builtin printf '用法：snmp -c [1|2c]\n' >&2
        return 2
    fi
    community=$(
        builtin source "$root/compat/common.sh" || return
        _bmcshell_v2tools_register_shims
        builtin source "$root/compat/snmp.sh" || return
        _bmc_snmp_read_community || return
        builtin printf '%s' "$_BMC_SNMP_COMMUNITY"
    ) || return
    _BMCSHELL_SESSION_STATE[v2.snmp_version]=$version
    _BMCSHELL_SESSION_STATE[v2.snmp_community]=$community
    builtin printf 'SNMPv%s community configured for %s (current BMC session only).\n' "$version" "$ip"
}

_bmcshell_v2tools_run() (
    local _BMC_INSTALL_DIR=$1 tool=$2 _BMC_IP=$3 _BMC_ACTIVE=1
    local _BMC_TLS=${_BMCSHELL_SESSION_STATE[v2.tls]:-verify} _BMC_PLATFORM_NOTE=''
    local +x _BMC_USER=${_BMCSHELL_SESSION_STATE[v2.user]-} _BMC_PASSWORD=${_BMCSHELL_SESSION_STATE[v2.password]-}
    local arg implementation
    shift 3
    builtin source "$_BMC_INSTALL_DIR/compat/common.sh" || return
    _bmcshell_v2tools_register_shims
    case $tool in
        getcid|setcid|smash|redfish)
            if ! _bmc_credentials_valid "$_BMC_USER" "$_BMC_PASSWORD"; then
                implementation="$tool --auth"
                _bmc_error "请先执行 $implementation 为当前会话输入登录凭据。"
                return 2
            fi
            ;;
        bssh)
            for arg in "$@"; do
                case $arg in
                    --user)
                        if ! _bmc_credentials_valid "$_BMC_USER" "$_BMC_PASSWORD"; then
                            _bmc_error 'bssh --user 需要会话凭据，请先执行 bssh --auth。'
                            return 2
                        fi ;;
                    --root|--manual) ;;
                    *) break ;;
                esac
            done
            ;;
    esac
    case $tool in
        ipmitool|getcid|setcid|smash) builtin source "$_BMC_INSTALL_DIR/compat/ipmi.sh" || return ;;
    esac
    case $tool in
        ipmitool) _bmc_ipmi_wrapper "$@" ;;
        getcid|setcid)
            builtin source "$_BMC_INSTALL_DIR/compat/cid.sh" || return
            "_bmc_tool_$tool" "$@" ;;
        smash)
            builtin source "$_BMC_INSTALL_DIR/compat/smash.sh" || return
            _bmc_tool_smash "$@" ;;
        redfish)
            builtin source "$_BMC_INSTALL_DIR/compat/transport.sh" || return
            builtin source "$_BMC_INSTALL_DIR/compat/redfish.sh" || return
            _bmc_tool_redfish "$@" ;;
        bssh)
            builtin source "$_BMC_INSTALL_DIR/compat/ssh.sh" || return
            _bmc_tool_bssh "$@" ;;
        snmp|snmpget|snmpgetnext|snmpwalk|snmpbulkwalk|snmpbulkget|snmpset|snmp2get|snmp2getnext|snmp2walk|snmp2bulkwalk|snmp2bulkget|snmp2set|snmp3get|snmp3getnext|snmp3walk|snmp3bulkwalk|snmp3bulkget|snmp3set)
            builtin source "$_BMC_INSTALL_DIR/compat/snmp.sh" || return
            local _BMC_SNMP_VERSION=${_BMCSHELL_SESSION_STATE[v2.snmp_version]:-2c}
            local +x _BMC_SNMP_COMMUNITY=${_BMCSHELL_SESSION_STATE[v2.snmp_community]-}
            if [[ $tool == snmp ]]; then _bmc_snmp_command "$@"
            else "_bmc_tool_$tool" "$@"; fi ;;
        *) _bmc_error "未知 V2 工具：$tool"; return 2 ;;
    esac
)

_bmcshell_v2tools_entry() {
    local root=${BASH_SOURCE[0]%/*} tool=$1 ip
    shift
    if [[ $- == *x* || $- == *a* || -o functrace || -n $(builtin trap -p DEBUG) ]]; then
        builtin printf 'V2 工具需要关闭命令跟踪和自动导出后才能读取会话凭据。\n' >&2
        return 2
    fi
    if (( $# == 1 )) && [[ $1 == -h || $1 == --help ]]; then
        case $tool in
            ipmitool) if [[ $1 == --help ]]; then bmc tool "$tool" --help; return; fi ;;
            bmc_v2_auth|redfish|bssh|getcid|setcid|smash|snmp) bmc tool "$tool"; return ;;
        esac
    fi
    ip=$(bmc bridge field target.ip) || return
    if [[ -z $ip || ( $tool != ipmitool && $tool != bmc_v2_auth && ! $ip =~ ^[0-9]+(\.[0-9]+){3}$ ) ]]; then
        builtin printf 'V2 工具需要当前会话中的 IPv4 目标。\n' >&2
        return 2
    fi
    case $tool:${1-} in
        bmc_v2_auth:*) _bmcshell_v2tools_auth "$root" "$@"; return ;;
        redfish:--auth|bssh:--auth|getcid:--auth|smash:--auth)
            shift; _bmcshell_v2tools_auth "$root" "$@"; return ;;
        snmp:-c|snmp:--configure|snmp:-r|snmp:--clear)
            _bmcshell_v2tools_snmp_setup "$root" "$ip" "$@"; return ;;
    esac
    if _bmcshell_v2tools_run "$root" "$tool" "$ip" "$@"; then
        if [[ $tool == setcid && ${2-} == --now ]]; then _bmcshell_exit; fi
    else
        return $?
    fi
}

_bmcshell_v2tools_entry "$@"
