# ══════════════════════════════════════════════
# telnet.zsh — telnet devices from ~/.ssh/telnet_config (ssh config syntax,
# never Included, so ssh doesn't see them)
#   telnet-pick [query]   fzf picker, Enter runs telnet-to
#   telnet-cfg            edit ~/.ssh/telnet_config
#   telnet-to <alias> | <host> [port]   telnet highlighted by tinge
#   telnet \<Tab>, telnet-to \<Tab>     the picker as fzf completion
# ══════════════════════════════════════════════

_rmt_kind telnet Telnet telnet-to Connect telnet 'Pick a telnet device with fzf, connect via telnet-to'

_rmt_help_telnet() {
    _ui_sect telnet 'while connected: Ctrl-] opens the telnet> prompt'
    _ui_cmd 'Ctrl-] quit' 'disconnect and exit (works when the device hangs)' 36
    _ui_cmd 'Ctrl-] send brk' 'send a break' 36
    _ui_cmd 'Ctrl-] status' 'show the connection status' 36
    _ui_cmd 'Ctrl-] Enter' 'back to the session' 36
    _ui_sect 'telnet usage'
    _ui_cmd 'telnet-to <alias>' 'connect to a device in ~/.ssh/telnet_config' 36
    _ui_cmd 'telnet-to <address> [port]' 'connect directly, port 23 by default' 36
    _ui_cmd 'net-backup [alias|@group]' 'back up network device configs' 36
}

# @desc: Pick a telnet device with fzf, connect via telnet-to
# @usage: telnet-pick [query]
telnet-pick() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_pick_help telnet; return 0; }
    _rmt_pick telnet "$@"
}

# @desc: Telnet with tinge highlighting, falls back to plain telnet; accepts aliases from ~/.ssh/telnet_config
# @usage: telnet-to <host> [port] | telnet-to <alias>
telnet-to() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_help $0; _rmt_help_telnet; return 0; }
    # An alias from telnet_config: use its HostName / Port (23 when no Port)
    if (( $# == 1 )) && _rmt_proto "$1" telnet; then
        _rmt_resolve "$1" telnet || return 1
        set -- "$_rmt_g[hostname]" "$_rmt_g[port]"
    fi
    _rmt_need telnet telnet-to || return 1
    if _rmt_tinge; then
        command tinge telnet "$@"
    else
        command telnet "$@"
    fi
}

# @desc: Edit the Telnet host file (~/.ssh/telnet_config), through chezmoi when it manages it
# @usage: telnet-cfg
telnet-cfg() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_help $0; return 0; }
    _rmt_edit_config telnet
}

compdef _rmt_pick_complete telnet-pick
compdef _rmt_cmp_help telnet-cfg
compdef telnet-to=telnet

_rmt_fzf_complete_telnet()     { _rmt_fzf_complete_open telnet "$@"; }
_rmt_fzf_claim telnet
_fzf_complete_telnet-to()      { _rmt_fzf_complete_open telnet "$@"; }
_fzf_complete_telnet_post()    { _rmt_fzf_complete_post; }
_fzf_complete_telnet-to_post() { _rmt_fzf_complete_post; }
