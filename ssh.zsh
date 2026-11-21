# ══════════════════════════════════════════════
# ssh.zsh — SSH hosts from ~/.ssh/config (+ Includes)
#   ssh-pick [query]   fzf picker, Enter runs ssh-to
#   ssh-cfg            edit ~/.ssh/config
#   ssh-to <host> ...  ssh highlighted by tinge (network rules for devices, server rules otherwise)
#   ssh \<Tab>, ssh-to \<Tab>   the picker as fzf completion
# ══════════════════════════════════════════════

_rmt_kind ssh SSH ssh-to Connect ssh 'Pick an SSH host with fzf, connect via ssh-to'

_rmt_help_ssh() {
    _ui_sect ssh 'while connected: press Enter, then a ~ escape'
    _ui_cmd '~.' 'drop a hung connection' 36
    _ui_cmd '~^Z' 'suspend ssh; fg brings it back' 36
    _ui_cmd '~#' 'list the current port forwards' 36
    _ui_cmd '~C' 'open a command line to add a forward, e.g. -L 8080:localhost:80' 36
    _ui_cmd '~?' 'list all escapes' 36
    _ui_sect 'ssh options' 'arguments after ssh-to <alias> go to ssh unchanged'
    _ui_cmd 'ssh-to <alias> <command>' 'run one command on the host' 36
    _ui_cmd '-J <jump host>' 'connect through a jump host' 36
    _ui_cmd '-L 8080:localhost:80' "local 8080 to the host's port 80" 36
    _ui_cmd '-R 9000:localhost:3000' "the host's 9000 to local port 3000" 36
    _ui_cmd '-D 1080' 'a local SOCKS5 proxy' 36
    _ui_cmd '-N' 'forward only, no shell' 36
    _ui_cmd '-p <port> · -i <key> · -l <user>' 'override ssh config for this connection' 36
    _ui_cmd '-v · -vvv' 'show connection and auth details, for troubleshooting' 36
    _ui_sect 'ssh tools'
    _ui_cmd 'ssh-copy-id <alias>' 'install your public key for passwordless login' 36
    _ui_cmd 'scp <file> <alias>:<path>' 'copy a file; -r for a directory' 36
    _ui_cmd 'rsync -avP <dir>/ <alias>:<path>/' 'sync a directory, resumable' 36
    _ui_cmd 'ssh-ag' 'manage the keys in ssh-agent' 36
}

# @desc: Pick an SSH host with fzf, connect via ssh-to
# @usage: ssh-pick [query]
ssh-pick() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_pick_help ssh; return 0; }
    _rmt_pick ssh "$@"
}

# @desc: SSH with tinge highlighting, falls back to plain ssh
# @usage: ssh-to <host> | ssh-to user@ip -p port [ssh options...]
ssh-to() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_help $0; _rmt_help_ssh; return 0; }
    if _rmt_tinge; then
        _rmt_tinge_rules "$@"
        command tinge -c $REPLY ssh "$@"
    else
        command ssh "$@"
    fi
}

# @desc: Edit the SSH host file (~/.ssh/config), through chezmoi when it manages it
# @usage: ssh-cfg
ssh-cfg() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_help $0; return 0; }
    _rmt_edit_config ssh
}

compdef _rmt_pick_complete ssh-pick
compdef _rmt_cmp_help ssh-cfg
compdef ssh-to=ssh

# ssh \<Tab> keeps the arguments already typed: ssh -p 2222 \<Tab> → ssh-to -p 2222 <host>
_rmt_fzf_complete_ssh() {
    _rmt_fzf_complete ssh "$@" || return
    # Only a line that starts with ssh (not FOO=1 ssh, or leading spaces) is rewritten
    [[ $LBUFFER == ssh[[:space:]]* ]] && LBUFFER="ssh-to${LBUFFER#ssh}"
    return 0
}
_rmt_fzf_claim ssh
_fzf_complete_ssh-to()      { _rmt_fzf_complete ssh "$@"; }
_fzf_complete_ssh_post()    { _rmt_fzf_complete_post; }
_fzf_complete_ssh-to_post() { _rmt_fzf_complete_post; }
