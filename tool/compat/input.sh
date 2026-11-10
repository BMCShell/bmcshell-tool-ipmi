# Input editing shared by connection/library credential prompts.
# Bash read manages its own terminal mode; no persistent stty/bind/trap changes.
_bmc_prompt_output() { printf "$@" >/dev/tty; }
_bmc_prompt_read_key() {
    if (( $# )); then IFS= read -r -s -n 1 -t "$1" _bmc_prompt_key </dev/tty
    else IFS= read -r -s -n 1 _bmc_prompt_key </dev/tty; fi
}
_bmc_prompt_line() {
    local _bmc_prompt_target=$1 _bmc_prompt_text=$2 _bmc_prompt_hidden=$3 _bmc_prompt_limit=$4
    local +x _bmc_prompt_value='' _bmc_prompt_key=''
    local _bmc_prompt_i _bmc_prompt_sequence
    # Only known caller-local destinations; never evaluate arbitrary variable names.
    [[ $_bmc_prompt_target == _bmc_new_username || $_bmc_prompt_target == _bmc_new_password || $_bmc_prompt_target == _bmc_new_tags || $_bmc_prompt_target == _bmc_new_brief ]] || return 2
    printf -v "$_bmc_prompt_target" '%s' ''
    _bmc_prompt_output '%s' "$_bmc_prompt_text"
    while :; do
        _bmc_prompt_key=''
        if _bmc_prompt_read_key; then :
        else _bmc_prompt_output '\n'; return 130; fi
        case $_bmc_prompt_key in
            ''|$'\r')
                _bmc_prompt_output '\n'
                printf -v "$_bmc_prompt_target" '%s' "$_bmc_prompt_value"
                return 0 ;;
            $'\010'|$'\177')
                _bmc_prompt_value=${_bmc_prompt_value%?}
                if [[ $_bmc_prompt_hidden == 0 ]]; then
                    _bmc_prompt_output '\r\033[2K%s%s' "$_bmc_prompt_text" "$_bmc_prompt_value"
                fi ;;
            $'\025')
                _bmc_prompt_value=''
                if [[ $_bmc_prompt_hidden == 0 ]]; then _bmc_prompt_output '\r\033[2K%s' "$_bmc_prompt_text"; fi ;;
            $'\003'|$'\004') _bmc_prompt_output '\n'; return 130 ;;
            $'\033')
                # Ignore complete arrow/function-key sequences; lone Esc cancels.
                if _bmc_prompt_read_key 0.08 && [[ $_bmc_prompt_key == '[' || $_bmc_prompt_key == O ]]; then
                    _bmc_prompt_sequence=0
                    for ((_bmc_prompt_i=0; _bmc_prompt_i<16; _bmc_prompt_i++)); do
                        _bmc_prompt_read_key 0.08 || break
                        if [[ $_bmc_prompt_key == [a-zA-Z~] ]]; then _bmc_prompt_sequence=1; break; fi
                    done
                    if (( _bmc_prompt_sequence )); then continue; fi
                fi
                _bmc_prompt_output '\n'; return 130 ;;
            *[[:cntrl:]]*) ;; # Never put terminal control bytes into a credential.
            *)
                if (( ${#_bmc_prompt_value} >= _bmc_prompt_limit )); then
                    _bmc_prompt_output '\n'; return 2
                fi
                _bmc_prompt_value+=$_bmc_prompt_key
                if [[ $_bmc_prompt_hidden == 0 ]]; then _bmc_prompt_output '%s' "$_bmc_prompt_key"; fi ;;
        esac
    done
}
