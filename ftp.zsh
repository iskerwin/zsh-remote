# ══════════════════════════════════════════════
# ftp.zsh — FTP / FTPS servers from ~/.ssh/ftp_config (ssh config syntax,
# never Included; a block may say `#_Proto ftps` for implicit TLS)
#   ftp-pick [query]          fzf picker, Enter runs ftp-open
#   ftp-cfg                   edit ~/.ssh/ftp_config
#   ftp-open <alias>          lftp, password from the keychain
#   ftp-open --tui <alias>    mc, two panes (^O in the picker; not FTPS)
#   ftp-open --forget <alias> drop the stored password
#   ftp \<Tab>, ftp-open \<Tab>   the picker as fzf completion
# ══════════════════════════════════════════════

_rmt_kind ftp FTP ftp-open Open 'ftp lftp mc' 'Pick an FTP server with fzf, transfer files in lftp'
_rmt_kind_tui[ftp]=mc

_rmt_help_ftp() {
    _ui_sect 'ftp config' '~/.ssh/ftp_config (^E in ftp-pick edits it), ssh config syntax'
    _ui_cmd 'Host / HostName / Port / User' 'alias, address, port (ftp 21, ftps 990 by default), user; no User means anonymous' 38
    _ui_cmd '#_Proto ftps' 'implicit TLS; without it ftp, which lftp upgrades to TLS when the server supports it' 38
    _ui_cmd 'ftp-open --forget <alias>' 'after a wrong password, delete the saved one and enter it again next time' 38
    _ui_cmd 'set ssl:verify-certificate/<address> no' 'in ~/.lftprc: skip certificate checks for this self-signed server only' 38
}

# @desc: Pick an FTP server with fzf, browse its files in lftp
# @usage: ftp-pick [query]
ftp-pick() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_pick_help ftp; return 0; }
    _rmt_pick ftp "$@"
}

# HostName / Port / User from the FTP file; no User means anonymous. The
# password comes from the keychain (service ftp-open, asked once and stored
# on first use) and reaches lftp through LFTP_PASSWORD, never argv. Without
# a keychain lftp asks for it every time.
# --tui opens mc instead, which asks for the password in a dialog (handing
# it the stored one would put it in argv). mc has no TLS: FTPS hosts stay in lftp.
# @desc: Browse an FTP or FTPS server from ~/.ssh/ftp_config in lftp (password in the keychain), or two-pane in mc
# @usage: ftp-open <alias> | ftp-open --tui <alias> | ftp-open --forget <alias>
ftp-open() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_help $0; _rmt_help_ftp; _rmt_help_lftp; _rmt_help_mc; return 0; }
    local mode=lftp
    case ${1-} in
        --forget|--tui)
            mode=${1#--}
            (( $# == 2 )) || { _ui_usage ftp-open "$1 <alias>"; return 2; }
            shift ;;
        *)  (( $# == 1 )) || { _ui_usage ftp-open '<alias> | --tui <alias> | --forget <alias>'; return 2; } ;;
    esac
    local name=$1 proto url
    if [[ $mode == forget ]]; then
        if _rmt_secret_delete ftp-open "$name"; then
            _ui_ok "Deleted the saved password for $name; you will be asked again next time"
        else
            _ui_warn "No saved password for $name"
        fi
        return 0
    fi
    if [[ $mode == tui ]]; then
        _rmt_need mc 'ftp-open --tui' || return 1
    else
        _rmt_need lftp ftp-open || return 1
    fi
    if ! _rmt_proto "$name" ftp; then
        _ui_err "$name is not in ${(D)REMOTE_FTP_CONFIG} (ftp-cfg adds it)"
        return 1
    fi
    proto=$REPLY
    _rmt_resolve "$name" $proto || { _ui_err "Cannot parse $name in ${(D)REMOTE_FTP_CONFIG}"; return 1; }
    url=$_rmt_g[hostname]
    _rmt_default_port $proto
    [[ $_rmt_g[port] == $REPLY ]] || url+=":$_rmt_g[port]"
    if [[ $mode == tui ]]; then
        if [[ $proto == ftps ]]; then
            _ui_err "mc has no FTPS (TLS) — open $name with ftp-open $name (lftp)"
            return 1
        fi
        # The trailing / makes mc open the URL as a directory; no user = anonymous
        mc -u "$PWD" "ftp://${_rmt_g[user]:+$_rmt_g[user]@}$url/"
        return
    fi
    url="$proto://$url"
    _rmt_lftp_hint ftp
    if [[ -z $_rmt_g[user] ]]; then
        lftp "$url"
        return
    fi
    if ! _rmt_keychain; then
        lftp -u "$_rmt_g[user]" "$url"
        return
    fi
    if ! _rmt_secret ftp-open "$name"; then
        _ui_hint "First connection: enter $_rmt_g[user]'s password for $name (twice), kept in the keychain"
        if ! _rmt_secret_store ftp-open "$name" || ! _rmt_secret ftp-open "$name"; then
            _ui_warn "Password not stored — lftp will ask for it"
            lftp -u "$_rmt_g[user]" "$url"
            return
        fi
    fi
    LFTP_PASSWORD=$REPLY lftp --env-password -u "$_rmt_g[user]" "$url"
}

_ftp-open() {
    _arguments \
        '(- *)--forget[delete the saved password]:FTP host:{_rmt_cmp_hosts ftp}' \
        '(- *)--tui[open two-pane in mc]:FTP host:{_rmt_cmp_hosts ftp}' \
        '1:FTP host:{_rmt_cmp_hosts ftp}'
}
# @desc: Edit the FTP host file (~/.ssh/ftp_config), through chezmoi when it manages it
# @usage: ftp-cfg
ftp-cfg() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_help $0; return 0; }
    _rmt_edit_config ftp
}

compdef _rmt_pick_complete ftp-pick
compdef _nothing ftp-cfg
compdef _ftp-open ftp-open

_fzf_complete_ftp()           { _rmt_fzf_complete_open ftp "$@"; }
_fzf_complete_ftp-open()      { _rmt_fzf_complete_open ftp "$@"; }
_fzf_complete_ftp_post()      { _rmt_fzf_complete_post; }
_fzf_complete_ftp-open_post() { _rmt_fzf_complete_post; }
