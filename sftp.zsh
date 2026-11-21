# ══════════════════════════════════════════════
# sftp.zsh — files on SSH hosts (~/.ssh/config + Includes) in lftp over SFTP
#   sftp-pick [query]   fzf picker, Enter runs sftp-open
#   sftp-open <alias>   lftp sftp://<alias>; plain sftp without lftp
#   sftp-open --tui <alias>   mc with the host in the right pane (^O in the picker)
#   sftp \<Tab>, sftp-open \<Tab>   the picker as fzf completion
# ══════════════════════════════════════════════

_rmt_kind sftp SFTP sftp-open Open 'lftp mc' 'Pick an SSH host with fzf, browse its files over SFTP in lftp'
_rmt_kind_tui[sftp]=mc

# @desc: Pick an SSH host with fzf, browse its files over SFTP in lftp
# @usage: sftp-pick [query]
sftp-pick() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_pick_help sftp; return 0; }
    _rmt_pick sftp "$@"
}

# lftp runs `ssh -s <alias> sftp`, so Port, ProxyJump and IdentityFile come
# from ssh config. lftp cannot answer ssh's own password prompt, so one
# BatchMode login checks key auth first; when the server refuses it, lftp
# gets -u <user> and asks for the password itself (given a user it always
# asks, so key hosts get the bare alias). Plain sftp, used without lftp,
# prompts through ssh and needs no check.
# --tui opens mc: local cwd on the left, sh://<alias> on the right. sh:// runs
# the system ssh, so ssh config, ssh-agent and password prompts work as usual.
# @desc: Browse an SSH host's files over SFTP in lftp, or two-pane in mc
# @usage: sftp-open <alias> | sftp-open --tui <alias>
sftp-open() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_help $0; _rmt_help_lftp; _rmt_help_mc; return 0; }
    if [[ ${1-} == --tui ]]; then
        (( $# == 2 )) || { _ui_usage sftp-open '--tui <alias>'; return 2; }
        _rmt_need mc 'sftp-open --tui' midnight-commander || return 1
        mc -u "$PWD" "sh://$2"   # -u: no subshell (mc's zsh subshell can hang on a customised zshrc)
        return
    fi
    (( $# == 1 )) || { _ui_usage sftp-open '<alias> | --tui <alias>'; return 2; }
    local name=$1 t=$REMOTE_CONNECT_TIMEOUT err
    if (( ! $+commands[lftp] )); then
        sftp "$name"
        return
    fi
    _rmt_lftp_hint sftp
    err=$(_rmt_timeout $(( t * 2 + 2 )) ssh -T -o BatchMode=yes -o ConnectTimeout=$t -o ControlPath=none \
        -o AddKeysToAgent=no "$name" true 2>&1 >/dev/null </dev/null)
    if [[ $err == *'Permission denied'* ]] && _rmt_resolve "$name" ssh && [[ -n $_rmt_g[user] ]]; then
        _ui_hint "$name has no key login — lftp asks for $_rmt_g[user]'s password (ssh-copy-id $name skips it)"
        lftp -u "$_rmt_g[user]" "sftp://$name"
    else
        lftp "sftp://$name"
    fi
}

_sftp-open() {
    _arguments \
        '(- *)--tui[open two-pane in mc]:SSH host:{_rmt_cmp_hosts sftp}' \
        '1:SSH host:{_rmt_cmp_hosts sftp}'
}
compdef _rmt_pick_complete sftp-pick
compdef _sftp-open sftp-open

_fzf_complete_sftp()           { _rmt_fzf_complete_open sftp "$@"; }
_fzf_complete_sftp-open()      { _rmt_fzf_complete_open sftp "$@"; }
_fzf_complete_sftp_post()      { _rmt_fzf_complete_post; }
_fzf_complete_sftp-open_post() { _rmt_fzf_complete_post; }
