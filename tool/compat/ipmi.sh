# BMC Shell 2.0 - plugins/ipmi.sh

_bmc_ipmi_color_enabled() {
    [[ ${BMCSHELL_IPMI_COLOR:-auto} == auto && -t $1 && ${TERM-} != dumb && -z ${NO_COLOR-} ]]
}

_bmc_ipmi_color_fields() {
    local line newline=$'\n'
    local field='^([[:blank:]]*)([[:alnum:]][^:[:cntrl:]]*)(:[[:space:]].*|:)$'
    while IFS= builtin read -r line || { newline=''; [[ -n $line ]]; }; do
        if [[ $line =~ $field ]]; then
            builtin printf '%s\033[36m%s\033[0m%s%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "$newline"
        else
            builtin printf '%s%s' "$line" "$newline"
        fi
    done
}

_bmc_ipmi_wrapper() {
    _bmc_secret_guard && _bmc_require_active || return
    local executable proxy_address arg flag index route_option name
    local host=$_BMC_IP interface=lanplus user='' port=623 family='' auth_type=''
    local explicit_host=0 explicit_interface=0 explicit_user=0 explicit_password=0
    local local_device=0 offline=0 command_seen=0 environment_password=0
    local binary=0 csv=0 prompt_password=0 color_fields=0 command_index=0
    local output rc token octal escaped='' echo_style='' echo_reset=''
    local +x value
    local -a options=() relay_options=() command_args=() operand=() defaults=() invoke=() display_args=() bytes=()
    executable=$(builtin type -P ipmitool) || {
        _bmc_error '找不到 ipmitool。安装适合当前终端的版本并加入 PATH，再运行 command ipmitool -V 和 bmc doctor -d。'
        return 69
    }
    while (( $# )); do
        arg=$1
        shift
        case $arg in
            --bin) binary=1; continue ;;
            --)
                if (( ! command_seen )) && [[ ${1-} == help ]]; then offline=1; fi
                command_args+=("$arg" "$@")
                break ;;
        esac
        if (( command_seen )) || [[ $arg != -?* ]]; then
            if (( ! command_seen )) && [[ $arg == help ]]; then offline=1; fi
            command_seen=1
            command_args+=("$arg")
            continue
        fi
        operand=()
        route_option=0
        if [[ $arg != --* ]]; then
            # Match upstream ipmitool's short options that consume an operand.
            for (( index = 1; index < ${#arg}; index++ )); do
                flag=${arg:index:1}
                case $flag in
                    h|V) offline=1 ;;
                    c) csv=1 ;;
                    a) explicit_password=1; prompt_password=1 ;;
                    E) explicit_password=1; environment_password=1 ;;
                    4|6) family=$flag ;;
                    [IodHPfUpCLAtTmzSlbBekyORND])
                        value=${arg:index+1}
                        if [[ -z $value ]]; then
                            if (( $# == 0 )); then offline=1; break; fi
                            value=$1
                            operand=("$1")
                            shift
                        fi
                        case $flag in
                            I) interface=$value; explicit_interface=1 ;;
                            H) host=$value; explicit_host=1; route_option=1 ;;
                            p) port=$value; route_option=1 ;;
                            U) user=$value; explicit_user=1 ;;
                            P|f) explicit_password=1 ;;
                            A) auth_type=$value ;;
                            d|D) local_device=1 ;;
                            o) if [[ $value == list || $value == help ]]; then offline=1; fi ;;
                        esac
                        break ;;
                esac
            done
        fi
        options+=("$arg" "${operand[@]}")
        if (( route_option )); then
            # Keep any flags that shared a token with -H or -p.
            if (( index > 1 )); then relay_options+=("${arg:0:index}"); fi
        else
            relay_options+=("$arg" "${operand[@]}")
        fi
    done

    if (( ! binary && ! csv && ! prompt_password && ! offline )) && _bmc_ipmi_color_enabled 1; then
        if [[ ${command_args[0]-} == -- ]]; then command_index=1; fi
        # Only pipe read-only reports with label/value output. Interactive
        # commands and other native output formats keep their original streams.
        case "${command_args[command_index]-} ${command_args[command_index+1]-}" in
            'lan print'|'lan6 print'|'mc info'|'chassis status'|'sensor get'|'sdr get'|'sdr info'|'fru print'|'sel info'|'channel info')
                color_fields=1 ;;
        esac
    fi

    if (( local_device && ! explicit_interface && ! explicit_host )); then interface=''; fi
    display_args=("${options[@]}" "${command_args[@]}")
    invoke=("$executable" "${display_args[@]}")
    if (( ! offline )) && [[ $interface == lan || $interface == lanplus ]]; then
        if (( ! explicit_interface )); then defaults+=(-I "$interface"); fi
        if [[ $host == "$_BMC_IP" ]] && _bmc_credentials_valid "$_BMC_USER" "$_BMC_PASSWORD"; then
            if (( ! explicit_user )); then
                user=$_BMC_USER
                defaults+=(-U "$user")
            fi
            if (( ! explicit_password )) && [[ $user == "$_BMC_USER" && ${auth_type,,} != none ]]; then
                defaults+=(-P "$_BMC_PASSWORD")
            fi
        fi
        display_args=("${defaults[@]}")
        if (( ! explicit_host )); then display_args+=(-H "$host"); fi
        display_args+=("${options[@]}" "${command_args[@]}")
        # Keep command operands from overriding managed connection options on
        # ipmitool builds that scan past the first positional argument.
        if (( command_seen )); then command_args=(-- "${command_args[@]}"); fi
        proxy_address=$(_bmcshell_bridge proxy-address ipmi) || return
        if [[ -n $proxy_address ]]; then
            executable=$(_bmc_winpath "$executable") || return
            invoke=(_bmcshell_bridge proxy-run ipmi-native "$host" "$port" "$family" "$executable"
                "${defaults[@]}" "${relay_options[@]}" "${command_args[@]}")
        else
            invoke=("$executable" "${defaults[@]}")
            if (( ! explicit_host )); then invoke+=(-H "$host"); fi
            invoke+=("${options[@]}" "${command_args[@]}")
        fi
    fi
    if (( binary == 0 )); then
        # Show the resolved remote command, including plaintext credentials.
        if _bmc_ipmi_color_enabled 2; then
            echo_style=$'\033[90m'
            echo_reset=$'\033[0m'
        fi
        {
            builtin printf '%s==> ' "$echo_style"
            if (( environment_password )); then
                for name in IPMITOOL_PASSWORD IPMI_PASSWORD; do
                    if [[ $(builtin declare -p "$name" 2>/dev/null) =~ ^declare\ -[a-zA-Z]*x ]]; then
                        builtin printf '%s=%q ' "$name" "${!name}"
                        break
                    fi
                done
            fi
            builtin printf 'ipmitool'
            if (( ${#display_args[@]} )); then builtin printf ' %q' "${display_args[@]}"; fi
            builtin printf '%s\n' "$echo_reset"
        } >&2
        if (( color_fields )); then
            "${invoke[@]}" | _bmc_ipmi_color_fields || return "${PIPESTATUS[0]}"
            return "${PIPESTATUS[0]}"
        fi
        "${invoke[@]}"
        return
    fi
    if output=$("${invoke[@]}"); then :
    else rc=$?; return "$rc"; fi
    # Validate the entire response before emitting bytes. Never store binary
    # output in Bash variables (NUL bytes would be lost).
    output=${output//$'\r'/ }; output=${output//$'\n'/ }
    IFS=$' \t\n' read -r -a bytes <<< "$output"
    for token in "${bytes[@]}"; do
        [[ $token =~ ^[0-9a-fA-F]{2}$ ]] || {
            _bmc_error '二进制转换需要空白分隔的两位十六进制字节。请使用 raw，若已启用 -v 可去掉后重试。'
            return 65
        }
        # Fixed-width octal avoids hexadecimal escape handling differences in
        # MobaXterm runtimes. Force Bash builtin, bypass printf wrappers.
        builtin printf -v octal '\\%03o' "$((16#$token))"
        escaped+=$octal
    done
    builtin printf '%b' "$escaped"
}


_bmc_verify_ipmi() {
    local _BMC_IP=$1 _BMC_USER=$4 _BMC_ACTIVE=1
    local +x _BMC_PASSWORD=$5
    if _bmc_ipmi_wrapper mc info >/dev/null; then return 0; fi
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
