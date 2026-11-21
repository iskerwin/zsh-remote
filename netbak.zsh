#!/bin/zsh
# netbak.zsh — net-backup: back up network device configs. Loaded by zsh-remote.plugin.zsh after lib.zsh,
# whose host parsing and keychain helpers it uses.
#
# Login and capture are done by net-backup.exp, which recognizes Ruijie / Cisco / Huawei / H3C by their prompt.
# Devices in ~/.ssh/telnet_config log in over telnet (address, port and user from that file).
# Passwords live in the keychain (service net-backup, account = device alias; the enable / super password
# under <alias>:enable), read and written with lib.zsh's _rmt_secret* (shared with ftp-open).

# Network devices in the ssh and telnet configs (~/.ssh/config with its Includes, ~/.ssh/telnet_config) → reply
# (aliases), _netbak_info[alias]=group \x1f description \x1f protocol; status 1 when there are none.
# Same rule as the network device icon in the pickers: alias or #_Tags match $_rmt_device_pat
typeset -gA _netbak_info
_netbak_hosts() {
        local name desc tags proto group
    reply=()
    _netbak_info=()
    # The list keeps every alias and group; targets are deduplicated by real destination after selection.
    _rmt_host_entries ssh telnet | while IFS=$'\x1f' read -r name desc tags proto group; do
        [[ "${(L)name} ${(L)tags}" == *${~_rmt_device_pat}* ]] || continue
        reply+=( $name )
        _netbak_info[$name]=$group$'\x1f'$desc$'\x1f'$proto
    done
    (( $#reply ))
}

# A device alias becomes a command argument and a backup directory: no options, paths or control characters.
_netbak_valid_host() {
    [[ -n $1 && $1 != -* && $1 != *[/[:space:][:cntrl:]]* && $1 != (.|..) ]]
}

# Deduplicate the selected aliases by real destination → reply, keeping the first alias in selection order.
# Aliases that fail to resolve or are invalid are kept so _netbak_fetch reports them instead of silently dropping them.
_netbak_unique() {
    local host proto target k
    local -A seen
    local -a hosts=( "$@" )
    hosts=( "${(@u)hosts}" )
    reply=()
    for host in "${hosts[@]}"; do
        target=alias$'\x1f'$host
        if _netbak_valid_host "$host"; then
            _rmt_proto "$host" ssh telnet
            proto=$REPLY
            if _rmt_resolve "$host" "$proto"; then
                target=$proto
                for k in hostname port user proxyjump proxycommand; do
                    target+=$'\x1f'${_rmt_g[$k]-}
                done
            fi
        fi
        (( seen[$target]++ )) && continue
        reply+=( "$host" )
    done
}

# Back up one device: _netbak_fetch <alias> <backup root>; status 0 done, 1 failed, 2 config incomplete
# Writes .part first (named clear of existing .txt / .txt.incomplete), publishes it by hard link once complete
# (failing rather than overwriting on a clash); the always block removes .part on interruption
_netbak_fetch() {
    emulate -L zsh
    local host=$1 dir=$2/$1 proto=ssh pass enpass part out
    local -a args=( "$host" ) prev
    if ! _netbak_valid_host "$host"; then
        _ui_err "Invalid device alias: $host"
        return 1
    fi
    # Telnet devices: address, port and user resolved with ssh -F ~/.ssh/telnet_config -G, passed to the script
    if _rmt_proto "$host" ssh telnet && [[ $REPLY == telnet ]]; then
        proto=telnet
        _rmt_need telnet "net-backup $host" || return 1
        _rmt_resolve "$host" telnet || { _ui_err "$host: cannot resolve it in the telnet config"; return 1; }
        args=( -telnet "$_rmt_g[hostname]" "$_rmt_g[port]" "$_rmt_g[user]" )
    fi
    _ui_step "$host${${proto:#ssh}:+ ${_ui[gry]}· telnet${_ui[r]}}"
    if ! _rmt_secret net-backup "$host"; then
        _ui_hint "First backup: enter the login password for $host (twice) to save it in the keychain"
        if ! _rmt_secret_store net-backup "$host" || ! _rmt_secret net-backup "$host"; then
            _ui_err "$host: password not saved, skipped"
            return 1
        fi
    fi
    pass=$REPLY
    _rmt_secret net-backup "$host:enable" && enpass=$REPLY || enpass=$pass

    # Configs often hold password hashes and SNMP communities, so the directory and files are owner-only
    _rmt_private_new "$dir" "${host}_$(command date +%Y%m%d-%H%M%S)" .part .txt .txt.incomplete || {
        _ui_err "$host: cannot create a backup file in $dir"
        return 1
    }
    part=$REPLY out=${REPLY%.part}.txt
    {
        if ! NETBAK_PASS=$pass NETBAK_ENABLE=$enpass $ZSH_REMOTE_DIR/net-backup.exp $args > "$part"; then
            _ui_hint "If the password changed or was saved wrong: net-backup --forget $host"
            return 1
        fi
        # Ruijie / Cisco configs end with end, Huawei / H3C with return
        if [[ ! -s $part || $(command tail -n1 "$part") != (end|return) ]]; then
            if command ln -- "$part" "$out.incomplete"; then
                _ui_warn "$host: config incomplete: ${out/#$HOME/~}.incomplete"
                return 2
            fi
            _ui_err "$host: cannot save the incomplete result, kept in $part"
            part=''
            return 1
        fi
        if ! command ln -- "$part" "$out"; then
            _ui_err "$host: cannot publish the backup, capture kept in $part"
            part=''
            return 1
        fi
    } always {
        [[ -n $part ]] && command rm -f -- "$part"
    }
    _ui_ok "${out/#$HOME/~}  ${_ui[gry]}$(wc -l < "$out" | tr -d ' ') lines${_ui[r]}"
    prev=( "$dir"/${host}_*.txt(N.om[2]) )
    if (( $#prev )); then
        if cmp -s "$prev[1]" "$out"; then
            _ui_hint "Same as the last backup (${prev[1]:t})"
        else
            _ui_hint "Changed since the last backup: diff ${prev[1]/#$HOME/~} ${out/#$HOME/~}"
        fi
    fi
}

# @desc: Back up switch, router and firewall configs (Ruijie / Cisco / Huawei / H3C), passwords kept in the keychain
# @usage: net-backup [alias|@group...] | net-backup --forget <alias> (no arguments: pick with fzf)
net-backup() {
    emulate -L zsh
    setopt extended_glob
    local dir=${NET_BACKUP_DIR:-~/Backups/network}
    local -a reply hosts grp line
    local host a
    local -i fails=0 incomplete=0 succeeded=0

    case ${1-} in
        -h|--help)
            _rmt_help net-backup
            _ui_hint 'Ruijie RGOS, Cisco IOS, Huawei VRP and H3C Comware, recognized by the prompt after login'
            _ui_hint 'SSH or Telnet: devices in ~/.ssh/telnet_config log in over telnet'
            _ui_hint '@group backs up every network device in that #_Group, e.g. net-backup @site-a'
            _ui_hint "Backups go to ${dir/#$HOME/~}/<alias>/ (set NET_BACKUP_DIR to change)"
            _ui_hint 'The first backup of a device asks for its login password and saves it in the keychain;'
            _ui_hint 'the enable / super password defaults to the login password. If it differs:'
            if [[ $OSTYPE == darwin* ]]; then
                _ui_hint '  security add-generic-password -s net-backup -a <alias>:enable -w'
            else
                _ui_hint '  secret-tool store --label=net-backup service net-backup account <alias>:enable'
            fi
            return 0
            ;;
        --forget)
            if [[ -z ${2-} ]]; then
                _ui_usage net-backup '--forget <alias>'
                return 1
            fi
            _rmt_secret_delete net-backup "$2:enable"
            if _rmt_secret_delete net-backup "$2"; then
                _ui_ok "Deleted the saved passwords for $2; you will be asked again next backup"
            else
                _ui_warn "No saved password for $2"
            fi
            return 0
            ;;
    esac

    if (( $# )); then
        for a in "$@"; do
            if [[ $a == @?* ]]; then
                _netbak_hosts
                grp=()
                for host in $reply; do
                    [[ ${_netbak_info[$host]%%$'\x1f'*} == ${a#@} ]] && grp+=( $host )
                done
                (( $#grp )) || { _ui_err "Group $a has no network devices"; return 1 }
                hosts+=( $grp )
            else
                hosts+=( $a )
            fi
        done
    else
        if ! _netbak_hosts; then
            _ui_err 'No network devices in the ssh or telnet config (alias or #_Tags containing ruijie, cisco, huawei, h3c, switch, router, firewall, network)'
            return 1
        fi
        # List: alias  @group  description  · telnet; Enter returns the aliases only
        local -i w=0
        local label keys
        for host in $reply; do (( ${(m)#host} > w )) && w=${(m)#host}; done
        _rmt_need_fzf net-backup || { _ui_hint 'or name the devices: net-backup <alias|@group...>'; return 1; }
        local -a newer
        _ui_fzf_since 0.61 && newer=( --ghost='alias, @group or description' )
        _ui_fzf_label grn ' net-backup'; label=$REPLY
        _ui_fzf_keys blu Tab Select '↵' 'Back up'; keys=$REPLY
        hosts=( ${(f)"$(for host in $reply; do
            line=( "${(@ps:\x1f:)_netbak_info[$host]}" )
            print -r -- "$host"$'\t'"${(mr:w:)host}  ${line[1]:+@$line[1]  }$line[2]${${(M)line[3]:#telnet}:+  · telnet}"
        done | fzf "${_ui_fzf_opts[@]}" --multi --height=~40% --delimiter=$'\t' --with-nth=2 --accept-nth=1 \
            --input-label="$label" --list-label="$keys" "${newer[@]}")"} )
        (( $#hosts )) || return 1
    fi

    _rmt_need expect net-backup || return 1
    _netbak_unique "${hosts[@]}"
    hosts=( "${reply[@]}" )
    for host in $hosts; do
        _netbak_fetch "$host" "$dir"
        case $? in
            0) (( ++succeeded )) ;;
            2) (( ++incomplete )) ;;
            *) (( ++fails )) ;;
        esac
    done
    _ui_kv result "done $succeeded · incomplete $incomplete · failed $fails"
    (( fails == 0 && incomplete == 0 ))
}

# ── Completion ────────────────────────────────

# Network device aliases from the ssh / telnet configs, with descriptions
_rmt_cmp_netbak_hosts() {
    local -a reply hosts
    local h
    _netbak_hosts || return 1
    for h in $reply; do
        hosts+=( "${h//:/\\:}:${${_netbak_info[$h]#*$'\x1f'}%%$'\x1f'*}" )
    done
    _describe -t hosts 'network device' hosts
}

# Device aliases plus @group (every network device in the group)
_rmt_cmp_netbak_targets() {
    local -a reply groups
    local h
    _rmt_cmp_netbak_hosts
    _netbak_hosts || return 1
    for h in $reply; do
        h=${_netbak_info[$h]%%$'\x1f'*}
        [[ -n $h ]] && groups+=( "@$h" )
    done
    groups=( ${(u)groups} )
    (( $#groups )) && _wanted groups expl 'group (every network device in it)' compadd -a groups
}

_net-backup() {
    _arguments \
        '(- *)'{-h,--help}'[show help]' \
        '(- *)--forget[delete the passwords saved in the keychain]:device:_rmt_cmp_netbak_hosts' \
        '(- *)'{-h,--help}'[show usage]' \
        '*:device or @group:_rmt_cmp_netbak_targets'
}
compdef _net-backup net-backup
