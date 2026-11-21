# ══════════════════════════════════════════════
# agent.zsh — ssh-agent key management with fzf
#
# Usage:
#   ssh-ag             — key picker: Enter adds/removes the key, list stays open
#   ssh-ag status      — agent socket and loaded keys
#   ssh-ag clear       — remove all keys from the agent
#   ssh-ag help
#
# Agent lifecycle: use the launchd agent (SSH_AUTH_SOCK from launchd). With
# `AddKeysToAgent yes` + `UseKeychain yes` in ssh config, keys are added on
# first use and passphrases live in the Keychain, so nothing needs to be started
# here. If launchd's agent is unreachable, one agent on a fixed socket
# ($HOME/.ssh/agent.sock) is reused by every shell.
#
# Lists, previews and actions live in ./helper; shared code in ./lib.zsh
# (init.zsh loads it first).
# ══════════════════════════════════════════════

# ══════════════════════════════════════════════
# Agent
# `ssh-add -l` exits 1 when the agent is fine but holds no keys; only 2
# means "no agent". Treating 1 as dead used to spawn a new agent per shell.
# ══════════════════════════════════════════════
_ssha_ensure_agent() {
    emulate -L zsh
    _rmt_agent_status; (( $? != 2 )) && return 0

    local sock
    # A stale SSH_AUTH_SOCK (e.g. inherited from a killed agent): fall back to launchd's
    if sock=$(launchctl getenv SSH_AUTH_SOCK 2>/dev/null) && [[ -n $sock ]]; then
        export SSH_AUTH_SOCK=$sock
        _rmt_agent_status; (( $? != 2 )) && return 0
    fi

    sock=$HOME/.ssh/agent.sock
    export SSH_AUTH_SOCK=$sock
    _rmt_agent_status; (( $? != 2 )) && return 0

    # Checking, cleaning up and starting the fixed socket must be serialized, or a concurrent terminal may delete a socket just created.
    zmodload zsh/system || return 1
    local lock
    ( umask 077; command mkdir -p "$HOME/.ssh" && : >> "$sock.lock" ) || return 1
    zsystem flock -t 3 -i 0.01 -f lock "$sock.lock" || {
        _ui_err 'ssh-ag: timed out waiting for agent startup'; return 1
    }
    {
        _rmt_agent_status; (( $? != 2 )) && return 0
        command rm -f -- "$sock" || return 1
        command ssh-agent -a "$sock" >/dev/null || { _ui_err 'ssh-ag: failed to start ssh-agent'; return 1; }
    } always {
        zsystem flock -u $lock
    }
}

# ══════════════════════════════════════════════
# Key picker
# ══════════════════════════════════════════════
_ssha_picker() {
    _rmt_need fzf ssh-ag || return 1
    local h=${(q)_RMT_HELPER} label
    _ui_fzf_label grn " $_rmt_i[key]  ssh-agent"; label=$REPLY
    local pkeys; _ui_fzf_keys cyn '^/' Hide; pkeys=$REPLY
    _ui_fzf_keys blu '↵' 'Add/Remove' '^X' 'Remove all' Esc Quit
    "$_RMT_HELPER" keys | fzf "${_rmt_fzf_opts[@]}" \
        --with-nth=3 \
        --input-label="$label" \
        --ghost='key name, type or comment' \
        --list-label="$REPLY" \
        --preview-label="$pkeys" \
        --preview="$h key {1} {2}" \
        --info-command='n=$FZF_MATCH_COUNT; [ "$n" = 1 ] && echo "1 key" || echo "$n keys"' \
        --bind="enter:execute($h toggle {1} {2})+reload($h keys)" \
        --bind="ctrl-x:execute-silent(ssh-add -D)+reload($h keys)" \
        >/dev/null
    return 0
}

# ══════════════════════════════════════════════
# Entry point
# ══════════════════════════════════════════════
# @desc: Manage ssh-agent keys with fzf
# @usage: ssh-ag [status | clear]
ssh-ag() {
    case ${1:-} in
        "")     _ssha_ensure_agent && _ssha_picker ;;
        status) "$_RMT_HELPER" status ;;
        clear)  ssh-add -D ;;
        help|-h|--help)
            _ui_head ssh-ag 'ssh-agent key manager'
            _ui_cmd ssh-ag 'pick keys to add / remove (fzf)' 16
            _ui_cmd 'ssh-ag status' 'agent socket and loaded keys' 16
            _ui_cmd 'ssh-ag clear' 'remove all keys from the agent' 16
            ;;
        *)
            _ui_err "ssh-ag: unknown command '$1'"
            _ui_usage ssh-ag '[status | clear | help]'
            return 1
            ;;
    esac
}

_ssha_complete() {
    local -a cmds=(
        'status:Show agent status and loaded keys'
        'clear:Remove all keys from the agent'
        'help:Show help'
    )
    _describe 'command' cmds
}
compdef _ssha_complete ssh-ag

_ssha_ensure_agent
