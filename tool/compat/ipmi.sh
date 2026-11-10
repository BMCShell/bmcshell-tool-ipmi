# BMC Shell 2.0 - plugins/ipmi.sh

_bmc_ipmi_run() {
    local ip=$1 user=$2 executable proxy_address
    local +x password=$3
    shift 3
    executable=$(type -P ipmitool) || { _bmc_error 'ipmitool executable is not installed.'; return 69; }
    proxy_address=$(_bmcshell_bridge proxy-address ipmi) || return
    if [[ -n $proxy_address ]]; then
        executable=$(_bmc_winpath "$executable") || return
        IPMI_PASSWORD="$password" _bmcshell_bridge proxy-run ipmi "$ip" "$executable" "$user" "$@"
        return
    fi
    IPMI_PASSWORD="$password" command ipmitool -I lanplus -H "$ip" -U "$user" -E "$@"
}

_bmc_ipmi_wrapper() {
    _bmc_secret_guard && _bmc_require_active || return
    local arg binary=0 output rc token octal escaped=''
    local -a args=() bytes=()
    while (( $# )); do
        case $1 in
            --bin) binary=1; shift ;;
            *) args+=("$1"); shift ;;
        esac
    done
    # Native getopt also accepts clusters such as -vH, so allow only known safe flags.
    for arg in "${args[@]}"; do
        if [[ $arg == -* && ! $arg =~ ^-[46hVvcgsKYZ]+$ &&
              ! $arg =~ ^-[46hVvcgsKYZ]*[odCLAtTmzSlbBekyORND].*$ ]]; then
            _bmc_error 'Unsupported IPMI option. Use command ipmitool for an independent connection.'
            return 2
        fi
    done
    _bmc_show_command --env IPMI_PASSWORD "$_BMC_PASSWORD" command ipmitool -I lanplus -H "$_BMC_IP" -U "$_BMC_USER" -E "${args[@]}"
    if (( binary == 0 )); then
        _bmc_ipmi_run "$_BMC_IP" "$_BMC_USER" "$_BMC_PASSWORD" "${args[@]}"
        return
    fi
    if output=$(_bmc_ipmi_run "$_BMC_IP" "$_BMC_USER" "$_BMC_PASSWORD" "${args[@]}"); then :
    else rc=$?; return "$rc"; fi
    # Validate the entire response before emitting bytes. Never store binary
    # output in Bash variables (NUL bytes would be lost).
    output=${output//$'\r'/ }; output=${output//$'\n'/ }
    IFS=$' \t\n' read -r -a bytes <<< "$output"
    for token in "${bytes[@]}"; do
        [[ $token =~ ^[0-9a-fA-F]{2}$ ]] || { _bmc_error '二进制转换失败：输出必须是空白分隔的两位十六进制字节。'; return 65; }
        # Fixed-width octal avoids hexadecimal escape handling differences in
        # MobaXterm runtimes. Force Bash builtin, bypass printf wrappers.
        builtin printf -v octal '\\%03o' "$((16#$token))"
        escaped+=$octal
    done
    builtin printf '%b' "$escaped"
}


_bmc_verify_ipmi() {
    local ip=$1 user=$4
    local +x password=$5
    if _bmc_ipmi_run "$ip" "$user" "$password" mc info >/dev/null; then return 0; fi
    _bmc_error 'IPMI 验证失败；不能仅凭此判断密码错误。'; return 3
}
# All registered public tool names are checked centrally before activation.
_bmc_ipmi_preflight() { return 0; }
_bmc_ipmi_enter() {
    export -n _BMC_SAVED_IPMI_FUNCTION _BMC_SAVED_IPMI_ALIAS 2>/dev/null
    _BMC_SAVED_IPMI_FUNCTION=''
    if declare -F ipmitool >/dev/null; then _BMC_SAVED_IPMI_FUNCTION=$(declare -f ipmitool) || return; fi
    _BMC_SAVED_IPMI_ALIAS=''
    if alias ipmitool &>/dev/null; then _BMC_SAVED_IPMI_ALIAS=$(alias ipmitool) || return; fi
    _BMC_IPMI_SNAPSHOT_READY=1
    unalias ipmitool 2>/dev/null || :
    function ipmitool { _bmc_ipmi_wrapper "$@"; }
}
_bmc_ipmi_leave() {
    [[ ${_BMC_IPMI_SNAPSHOT_READY:-0} == 1 ]] || return 0
    unset -f ipmitool
    unalias ipmitool 2>/dev/null || :
    [[ -z ${_BMC_SAVED_IPMI_FUNCTION-} ]] || builtin eval -- "$_BMC_SAVED_IPMI_FUNCTION"
    [[ -z ${_BMC_SAVED_IPMI_ALIAS-} ]] || builtin eval -- "$_BMC_SAVED_IPMI_ALIAS"
    unset _BMC_SAVED_IPMI_FUNCTION _BMC_SAVED_IPMI_ALIAS
    _BMC_IPMI_SNAPSHOT_READY=0
    return 0
}
_bmc_register_plugin ipmi 'IPMI 命令与验证' _bmc_ipmi_preflight _bmc_ipmi_enter _bmc_ipmi_leave
_bmc_register_verifier ipmi _bmc_verify_ipmi


_bmc_register_tool ipmitool _bmc_ipmi_wrapper 'IPMI 命令；bmc tool ipmitool' plugin || return
