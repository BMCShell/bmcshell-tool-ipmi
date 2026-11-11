# BMC Shell 2.0 - core/common.sh

_bmc_error() { printf 'BMCShell：%s\n' "$*" >&2; }

_bmc_secret_guard() {
    case $- in
        *x*) _bmc_error '请先运行 set +x 关闭命令跟踪，再使用凭据。'; return 2 ;;
        *a*) _bmc_error '请先运行 set +a 关闭变量自动导出，再使用凭据。'; return 2 ;;
    esac
    # Assignments made by a previous set -a session can leave empty variables
    # exported even after set +a. Remove those attributes before storing secrets.
    export -n _BMC_PASSWORD _BMC_INPUT_PASSWORD _BMC_INPUT_USER _BMC_PLATFORM_JSON _BMC_OEM_JSON 2>/dev/null
}


_bmc_cid_valid() { local LC_ALL=C; [[ $1 =~ ^[A-Za-z0-9]{3}$ ]]; }

_bmc_ipv4_valid() {
    local part
    local -a parts
    [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r -a parts <<< "$1"
    for part in "${parts[@]}"; do
        [[ $part == 0 || $part != 0* ]] || return 1
        (( 10#$part <= 255 )) || return 1
    done
}

_bmc_credentials_valid() {
    [[ -n $1 && -n $2 && ${#1} -le 128 && ${#2} -le 4096 && $1 != *:* && $1 != *[[:cntrl:]]* && $2 != *[[:cntrl:]]* ]]
}

_bmc_settings_valid() {
    [[ ${BMC_CONNECT_TIMEOUT:-5} =~ ^[1-9][0-9]{0,2}$ && ${BMC_HTTP_TIMEOUT:-15} =~ ^[1-9][0-9]{0,2}$ ]] || {
        _bmc_error '连接和请求超时必须为 1 至 999 秒的整数。'; return 2;
    }
    [[ -z ${BMC_CA_BUNDLE-} || -r $BMC_CA_BUNDLE ]] || {
        _bmc_error '无法读取 BMC_CA_BUNDLE 指定的 CA 证书文件。'; return 2;
    }
}
