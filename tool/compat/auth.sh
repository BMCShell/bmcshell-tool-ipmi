_bmc_read_credentials() {
    local +x _bmc_new_username='' _bmc_new_password=''
    local rc=0
    _BMC_INPUT_USER=''; _BMC_INPUT_PASSWORD=''
    _bmc_secret_guard || return
    [[ -r /dev/tty && -w /dev/tty ]] || { _bmc_error '需要交互终端输入凭据。'; return 2; }
    _bmc_prompt_output '%s\n' '退格删除；Ctrl+U 清空当前项；Esc/Ctrl+C/Ctrl+D 取消。密码不回显。'
    if _bmc_prompt_line _bmc_new_username 'BMC 用户名 [Admin]：' 0 128 &&
        _bmc_prompt_line _bmc_new_password 'BMC 密码：' 1 4096; then :
    else
        rc=$?
        if (( rc == 130 )); then
            if [[ ${_BMC_ACTIVE:-0} == 1 ]]; then _bmc_error '已取消输入，保留当前 BMC 连接。'
            else _bmc_error '已取消输入。'; fi
        else _bmc_error '输入过长，请重新输入。'; fi
        return "$rc"
    fi
    _bmc_new_username=${_bmc_new_username:-Admin}
    _bmc_credentials_valid "$_bmc_new_username" "$_bmc_new_password" || {
        _bmc_error '凭据格式无效：密码不能为空，用户名不能包含冒号或控制字符。'; return 2;
    }
    # Publish both fields only after the complete prompt succeeded.
    _BMC_INPUT_USER=$_bmc_new_username; _BMC_INPUT_PASSWORD=$_bmc_new_password
}
