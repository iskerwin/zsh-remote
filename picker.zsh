# ══════════════════════════════════════════════
# picker.zsh — the fzf host picker every protocol file builds on
#
# A protocol file registers its kind with _rmt_kind and defines
# <kind>-pick() on top of _rmt_pick; list, preview, keys, look, -h and fzf
# completion (<command> \<Tab>, $FZF_COMPLETION_TRIGGER is '\') are shared.
#
# Keys in every picker: Enter open · ^T test · ^E edit the config ·
# ^Y copy alias · ^/ toggle preview; pickers of SSH hosts add ^A (add the
# host's keys to ssh-agent), sftp-pick and ftp-pick add ^O (two-pane browser).
#
# Lists, previews and actions live in ./helper; shared code in ./lib.zsh.
# ══════════════════════════════════════════════


# Clipboard command for ^Y, override with REMOTE_CLIP: the first of clip-copy, pbcopy, wl-copy, xclip, xsel
if [[ -z ${REMOTE_CLIP-} ]]; then
    if (( $+commands[clip-copy] )); then REMOTE_CLIP=clip-copy
    elif (( $+commands[pbcopy] )); then REMOTE_CLIP=pbcopy
    elif [[ -n ${WAYLAND_DISPLAY-} ]] && (( $+commands[wl-copy] )); then REMOTE_CLIP=wl-copy
    elif (( $+commands[xclip] )); then REMOTE_CLIP='xclip -selection clipboard'
    elif (( $+commands[xsel] )); then REMOTE_CLIP='xsel --clipboard --input'
    else REMOTE_CLIP=cat
    fi
fi

# Per kind, filled by _rmt_kind: search box title, the command Enter runs and
# its label, the help sections <kind>-pick -h shows, the -h description.
# _rmt_kind_tui[<kind>]=<tool> (set by the protocol file) adds ^O: the open
# command with --tui, a two-pane file browser (mc).
typeset -gA _rmt_kind_title _rmt_kind_open _rmt_kind_enter _rmt_kind_help _rmt_kind_desc _rmt_kind_tui

# _rmt_kind <kind> <title> <open command> <Enter label> <help sections> <description>
# Help sections are words, each naming a _rmt_help_<word> function.
_rmt_kind() {
    _rmt_kind_title[$1]=$2
    _rmt_kind_open[$1]=$3
    _rmt_kind_enter[$1]=$4
    _rmt_kind_help[$1]=$5
    _rmt_kind_desc[$1]=$6
}

# Whether a kind lists SSH hosts (so ^A can load their keys)
_rmt_kind_ssh() { _rmt_kind_file $1; [[ $REPLY == ssh ]]; }

# fzf options of a kind's picker -> reply; shared by the pickers and fzf
# completion. A second argument "pick" adds ^O, which completion can't use
# (it only inserts the alias).
_rmt_pick_fzf_args() {
    local kind=$1 h=${(q)_RMT_HELPER}
    local -a keys=( '↵' $_rmt_kind_enter[$kind] )
    _ui_fzf_label grn " $_rmt_i[server]  $_rmt_kind_title[$kind]"
    reply=(
        "${_rmt_fzf_opts[@]}"
        --with-nth=4
        --input-label="$REPLY"
        --ghost='alias, host, @group, #tag or description'
        --preview="$h host $kind {1} {2} {3} {5}"
        # Group separator rows have an empty alias: not counted, skipped, Enter ignored
        --info-command='n=$(grep -c . {*f1}); [ "$n" = 1 ] && echo "1 host" || echo "$n hosts"'
        --bind='result:transform:[ -z {1} ] && grep -q . {*f1} && echo down'
        # Tree layout while browsing, flat (with an @group column) while searching:
        # reload when the query empties or fills (field 6 is the current layout); first replaces the shared change:first
        --bind="change:first+transform:m=t; [ -n \"\$FZF_QUERY\" ] && m=f; [ {6} = \$m ] || echo 'reload($h hosts $kind)'"
        --bind='enter:transform:[ -n {1} ] && echo accept'
        --bind='down,ctrl-j,ctrl-n:down+transform:[ -z {1} ] && echo down'
        --bind='up,ctrl-k,ctrl-p:up+transform:[ -z {1} ] && echo up'
        --bind="ctrl-t:preview($h probe $kind {1})"
        --bind="ctrl-e:execute($h edit-config $kind)+reload($h hosts $kind)"
        --bind="ctrl-y:execute-silent([ -n {1} ] && printf %s {1} | $REMOTE_CLIP)"
    )
    # ^O prints a marker line before the row; _rmt_pick reads it
    if [[ ${2-} == pick && -n ${_rmt_kind_tui[$kind]-} ]]; then
        reply+=( --bind="ctrl-o:transform:[ -n {1} ] && echo 'print(tui)+accept'" )
        keys+=( '^O' TUI )
    fi
    keys+=( '^T' Test )
    if _rmt_kind_ssh $kind; then
        reply+=( --bind="ctrl-a:execute($h host-addkey {1})+refresh-preview" )
        keys+=( '^A' 'Add key' )
    fi
    keys+=( '^E' Edit '^Y' Copy )
    _ui_fzf_keys blu $keys
    reply+=( --list-label="$REPLY" )
    _ui_fzf_keys cyn '^/' Hide
    reply+=( --preview-label="$REPLY" )
}

# <kind>-pick -h: usage, keys, the protocol's help sections, its config file
_rmt_pick_help() {
    local kind=$1 cmd=$1-pick open=$_rmt_kind_open[$1] s
    _ui_head $cmd "$_rmt_kind_desc[$kind]"
    _ui_sect usage
    _ui_cmd "$cmd [query]" 'initial search over alias, address, @group, #tag, description' 24
    _ui_cmd "$cmd -- <query>" 'for a query starting with -' 24
    _ui_cmd "$open <alias>" 'open directly, without the picker' 24
    [[ -n ${_rmt_kind_tui[$kind]-} ]] && _ui_cmd "$open --tui <alias>" "open in $_rmt_kind_tui[$kind], without the picker" 24
    _ui_sect keys 'in the picker'
    _ui_cmd '↵' "open with $open" 10
    [[ -n ${_rmt_kind_tui[$kind]-} ]] && _ui_cmd '^O' "open in $_rmt_kind_tui[$kind]: local on the left, remote on the right" 10
    _ui_cmd '^T' 'test the connection (SSH also tests key auth; never sends a password)' 10
    _rmt_kind_ssh $kind && _ui_cmd '^A' "add the host's keys to ssh-agent" 10
    _ui_cmd '^E' 'edit the config file' 10
    _ui_cmd '^Y' 'copy the alias' 10
    _ui_cmd '^/' 'show / hide the preview' 10
    for s in ${=_rmt_kind_help[$kind]}; do _rmt_help_$s; done
    _ui_sect config
    _rmt_kind_file $kind
    if [[ $REPLY == ssh ]]; then
        _rmt_cfg_file ssh
        _ui_hint "${(D)REPLY} and the files it Includes (^E edits)"
    else
        _rmt_cfg_file $kind
        _ui_hint "${(D)REPLY} (^E edits), ssh config syntax"
    fi
    _ui_hint 'in a Host block: #_Desc description · #_Tags a,b · #_Group group'
}

# _rmt_pick <kind> [query...]: pick a host of the kind, open it with the kind's command
_rmt_pick() {
    local kind=$1 cmd=$1-pick sel
    local -a reply out open=( $_rmt_kind_open[$1] )
    shift
    case ${1-} in
        --) shift ;;
        -?*)
            _ui_err "$cmd: unknown option '$1'"
            _ui_usage $cmd '[query] | -- <query> | -h'
            return 2 ;;
    esac
    (( $+commands[fzf] )) || { _ui_err "$cmd: fzf not found"; _ui_hint "brew install fzf, or $_rmt_kind_open[$kind] <alias>"; return 1; }
    _rmt_pick_fzf_args $kind pick
    sel=$(FZF_QUERY="$*" "$_RMT_HELPER" hosts $kind | fzf "${reply[@]}" --query="$*") || return
    out=( "${(@f)sel}" )
    if [[ $out[1] == tui ]]; then
        open+=( --tui )
        shift out
    fi
    $open "${out[1]%%$'\t'*}"
}

# Query words are free text; -h / --help is added by _cmp_add_help (init.zsh)
_rmt_pick_complete() { _message 'query'; }

# Alias completion for open commands: hosts of a kind's file, with descriptions
_rmt_cmp_hosts() {
    local name desc tags proto group
    local -a hosts
    _rmt_kind_file $1
    _rmt_host_entries $REPLY | while IFS=$'\x1f' read -r name desc tags proto group; do
        hosts+=( "${name//:/\\:}${desc:+:$desc}" )
    done
    _describe -t hosts 'host' hosts
}

# ══════════════════════════════════════════════
# fzf completion (<command> \<Tab>)
# ══════════════════════════════════════════════
# _rmt_fzf_complete <kind> <args...>: the kind's picker as completion;
# status 1 when nothing was picked
_rmt_fzf_complete() {
    local kind=$1 before=$LBUFFER
    local -a reply
    shift
    _rmt_pick_fzf_args $kind
    _fzf_complete "${reply[@]}" -- "$@" < <(FZF_QUERY=${(Q)prefix} "$_RMT_HELPER" hosts $kind)
    [[ $LBUFFER != "$before" ]]
}

# Same, and the picked host turns the line into "<open command> <alias> "
_rmt_fzf_complete_open() {
    _rmt_fzf_complete "$@" || return
    local -a w=( ${(z)LBUFFER} )
    LBUFFER="$_rmt_kind_open[$1] $w[-1] "
}

# fzf hands back the whole row; keep the alias
_rmt_fzf_complete_post() { cut -f1; }
