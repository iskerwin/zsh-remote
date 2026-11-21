# ══════════════════════════════════════════════
# lib.zsh — shared by the protocol files (ssh / sftp / telnet / ftp .zsh),
# picker.zsh, agent.zsh, helper and net-backup (netbak.zsh)
#
# Only defines variables and functions (no side effects), so it is safe
# to source both in the interactive shell and in helper subprocesses.
# helper runs in its own process and sources only this file, so everything
# the list, preview and probe need (config files, ports, parsing) lives here.
# Everything is prefixed with _rmt_ to stay out of the global namespace.
# ══════════════════════════════════════════════

# ══════════════════════════════════════════════
# Configuration (override in ~/.zshrc before sourcing the plugins)
# Exported so helper processes spawned by fzf see the same values.
# ══════════════════════════════════════════════
export SSH_KEY_DIR=${SSH_KEY_DIR:-$HOME/.ssh}
export REMOTE_SSH_CONFIG=${REMOTE_SSH_CONFIG:-$HOME/.ssh/config}
export REMOTE_TELNET_CONFIG=${REMOTE_TELNET_CONFIG:-$HOME/.ssh/telnet_config}
export REMOTE_FTP_CONFIG=${REMOTE_FTP_CONFIG:-$HOME/.ssh/ftp_config}
export REMOTE_CONNECT_TIMEOUT=${REMOTE_CONNECT_TIMEOUT:-3}
export REMOTE_PREVIEW_WIDTH=${REMOTE_PREVIEW_WIDTH:-55}

zmodload -F zsh/stat b:zstat 2>/dev/null

# ══════════════════════════════════════════════
# Output: the _ui_* helpers of zsh-ui (https://github.com/iskerwin/zsh-ui) when it is loaded, otherwise
# the plain ui-fallback.zsh. helper runs in its own process, so it loads zsh-ui from ZSH_UI_DIR.
# Colors follow the terminal's 16-color ANSI theme; fzf lists and previews aren't a tty,
# so helper sets UI_COLOR=always for those.
# ══════════════════════════════════════════════
[[ -n ${ZSH_UI_DIR-} && -f $ZSH_UI_DIR/ui.zsh ]] && ! (( $+functions[_ui_palette] )) && source $ZSH_UI_DIR/ui.zsh
source "${${(%):-%x}:A:h}/ui-fallback.zsh"
source "${${(%):-%x}:A:h}/util.zsh"

# Nerd Font glyphs (Font Awesome range, present in every Nerd Font)
# helper: the commands fzf runs for lists, previews and actions
typeset -g _RMT_HELPER="${${(%):-%x}:A:h}/helper"

typeset -gA _rmt_i=(
    server  $''  github  $''  ubuntu  $''  debian $''
    centos  $''  docker  $''  apple   $''  net    $''
    link    $''  key     $''  info    $''  lock   $''
    bolt    $''  plug    $''
)

# Status lines inside preview cards: stdout (fzf shows it), indented like _ui_kv
_rmt_ok()   { _ui_palette; print -r -- "  ${_ui[grn]}✓${_ui[r]} $*"; }
_rmt_warn() { _ui_palette; print -r -- "  ${_ui[ylw]}!${_ui[r]} $*"; }
_rmt_err()  { _ui_palette; print -r -- "  ${_ui[red]}✗${_ui[r]} $*"; }
_rmt_info() { _ui_palette; print -r -- "  ${_ui[cyn]}i${_ui[r]} $*"; }

# "prod,backend" -> colored "#prod #backend"
_rmt_tags() { [[ -n $1 ]] && print -r -- "${_ui[blu]}#${(j: #:)${(s:,:)1// /}}${_ui[r]}"; }

# user@host, plus :port when it isn't the default (22, or the 4th argument)
_rmt_target() { print -r -- "${1:+$1@}$2${${3:#${4:-22}}:+:$3}"; }

# Colored icon for a host, guessed from "alias hostname tags" -> REPLY
_rmt_host_icon() {
    case ${(L)1} in
        *github*|*gitlab*|*gitea*)         REPLY="${_ui[fg]}$_rmt_i[github]" ;;
        *orb*|*docker*|*container*)        REPLY="${_ui[cyn]}$_rmt_i[docker]" ;;
        *ubuntu*)                          REPLY="${_ui[ylw]}$_rmt_i[ubuntu]" ;;
        *debian*)                          REPLY="${_ui[red]}$_rmt_i[debian]" ;;
        *centos*|*rhel*|*rocky*)           REPLY="${_ui[blu]}$_rmt_i[centos]" ;;
        *mac*|*apple*)                     REPLY="${_ui[fg]}$_rmt_i[apple]" ;;
        *ruijie*|*huawei*|*h3c*|*cisco*|*switch*|*router*|*firewall*|*network*)
                                           REPLY="${_ui[ylw]}$_rmt_i[net]" ;;
        *)                                 REPLY="${_ui[grn]}$_rmt_i[server]" ;;
    esac
    REPLY+=${_ui[r]}
}

# Shared look from _ui_fzf_opts (ui.zsh) plus the ssh pickers' own options;
# ctrl-o from FZF_DEFAULT_OPTS opens files, which means nothing here.
typeset -ga _rmt_fzf_opts=(
    "${_ui_fzf_opts[@]}"
    --height=100%
    --delimiter=$'\t'
    --preview-window="right,${REMOTE_PREVIEW_WIDTH}%,wrap,<90(down,50%,wrap)"
    --bind='ctrl-o:ignore'
)

# ══════════════════════════════════════════════
# Files (zstat builtin: no stat(1) BSD/GNU differences, no forks)
# ══════════════════════════════════════════════
_rmt_perms() { local m; m=$(zstat -o +mode -- "$1" 2>/dev/null) && print -r -- ${m[-3,-1]}; }
_rmt_mtime() { zstat -F '%Y-%m-%d %H:%M' +mtime -- "$1" 2>/dev/null; }

# Private keys should be readable by the owner only -> REPLY (colored), status 1 if too open
_rmt_perm_badge() {
    local p; p=$(_rmt_perms "$1")
    if [[ $p == (600|400) ]]; then
        REPLY="${_ui[grn]}$p ✓${_ui[r]}"
    else
        REPLY="${_ui[red]}$p ✗${_ui[r]} ${_ui[gry]}chmod 600 ${(D)1}${_ui[r]}"
        return 1
    fi
}

# ══════════════════════════════════════════════
# Keys & agent
# ══════════════════════════════════════════════

# Private key files under $SSH_KEY_DIR, identified by their PEM/OpenSSH header
_rmt_find_keys() {
    setopt local_options extended_glob
    local -a files=( $SSH_KEY_DIR/**/*~*.pub~*/known_hosts*~*/config~*/.DS_Store(.N) )
    (( $#files )) && grep -l -e 'BEGIN.*PRIVATE KEY' -- $files 2>/dev/null
}

# Parse one `ssh-keygen -l` / `ssh-add -l` line into reply=(bits fp comment type).
# The comment may contain spaces, so take type from the end instead of by index.
_rmt_parse_l() {
    local -a w=( ${=1} )
    (( $#w >= 3 )) || return 1
    reply=( "$w[1]" "$w[2]" "${(j: :)w[3,-2]}" "${${w[-1]#\(}%\)}" )
}

# Key file -> reply=(bits fp comment type)
_rmt_keyinfo() {
    local out; out=$(ssh-keygen -lf "$1" 2>/dev/null </dev/null) || return 1
    _rmt_parse_l "$out"
}

# Exit status: 0 = agent has keys, 1 = agent reachable but empty, 2 = no agent
_rmt_agent_status() { ssh-add -l &>/dev/null; }

# Fingerprints currently held by the agent, one per line
_rmt_loaded_fps() { ssh-add -l 2>/dev/null | awk '$2 ~ /:/ {print $2}'; }

# Fingerprint -> public key line as held by the agent (works for keys with no local file)
_rmt_agent_pubkey() {
    local line
    ssh-add -L 2>/dev/null | while IFS= read -r line; do
        [[ $(ssh-keygen -lf - <<<"$line" 2>/dev/null) == *" $1 "* ]] && { print -r -- "$line"; return 0; }
    done
    return 1
}

# Add a key; on macOS the passphrase is stored in the Keychain
_rmt_add_key() {
    if [[ $OSTYPE == darwin* ]]; then ssh-add --apple-use-keychain "$1"; else ssh-add "$1"; fi
}

# Remove a key from the agent by fingerprint
_rmt_remove_key() {
    local pub; pub=$(_rmt_agent_pubkey "$1") || { _ui_err "Key $1 is not in the agent"; return 1; }
    ssh-add -d =(print -r -- "$pub")
}

# ══════════════════════════════════════════════
# ssh config
# ══════════════════════════════════════════════

# The main config plus every file it Includes (recursively, globs expanded)
_rmt_config_files() {
    setopt local_options extended_glob
    local file=${1:-$REMOTE_SSH_CONFIG} depth=${2:-0} line pat f
    [[ -r $file ]] && (( depth < 16 )) || return
    print -r -- "$file"
    while IFS= read -r line; do
        [[ $line == [[:space:]]#(#i)include[[:space:]=]* ]] || continue
        # zsh only splits words and removes quotes, never runs config content; Include paths may contain spaces.
        for pat in ${(z)${line#*(#i)include[[:space:]=]}}; do
            [[ $pat == \#* ]] && break
            pat=${(Q)pat}
            pat=${pat/#\~/$HOME}
            [[ $pat == /* ]] || pat=$HOME/.ssh/$pat
            for f in ${~pat}(N.); do _rmt_config_files "$f" $(( depth + 1 )); done
        done
    done < "$file"
}

# One config file per protocol, all in ssh config syntax: SSH hosts in
# ~/.ssh/config (and its Includes), telnet devices in $REMOTE_TELNET_CONFIG,
# FTP servers in $REMOTE_FTP_CONFIG. The last two are never Included, so ssh,
# scp and other tools don't see them and they don't inherit Host * from the
# main config. In the FTP file a block may say `#_Proto ftps` (implicit TLS).
#
# A kind is what a picker lists (ssh, sftp, telnet, ftp; see init.zsh);
# sftp lists the ssh config hosts.
# A host's protocol (ssh | telnet | ftp | ftps) decides how it is resolved.

# Config file of a kind or protocol -> REPLY
_rmt_cfg_file() {
    case $1 in
        telnet) REPLY=$REMOTE_TELNET_CONFIG ;;
        ftp*)   REPLY=$REMOTE_FTP_CONFIG ;;
        *)      REPLY=$REMOTE_SSH_CONFIG ;;
    esac
}

# _rmt_edit_config <kind>: edit that protocol's config file. A file managed by
# chezmoi goes through `chezmoi edit --apply` (editing the target would be
# overwritten on the next apply, and an encrypted source is re-encrypted).
_rmt_edit_config() {
    _rmt_cfg_file "$1"
    if (( $+commands[chezmoi] )) && chezmoi source-path "$REPLY" &>/dev/null; then
        chezmoi edit --apply "$REPLY"
    else
        ${=VISUAL:-${EDITOR:-vi}} "$REPLY"
    fi
}

# File a kind's hosts come from (ssh | telnet | ftp) -> REPLY
_rmt_kind_file() {
    case $1 in
        telnet|ftp) REPLY=$1 ;;
        *)          REPLY=ssh ;;
    esac
}

# Default port of a protocol -> REPLY
_rmt_default_port() {
    case $1 in
        telnet) REPLY=23 ;;
        ftp)    REPLY=21 ;;
        ftps)   REPLY=990 ;;
        *)      REPLY=22 ;;
    esac
}

# One line per concrete host: alias \x1f desc \x1f tags \x1f proto \x1f group
# Arguments pick the files, in order: ssh, telnet, ftp (default: all three).
# Every concrete alias of each Host line is listed; #_Desc / #_Tags / #_Group
# (and #_Proto in the FTP file) are read from inside the block. An alias
# already listed from an earlier file is skipped.
# \x1f (not tab) as separator so `read` keeps empty fields.
_rmt_host_entries() {
    setopt local_options extended_glob
    local p
    local -a args=() files=( "${@:-ssh telnet ftp}" )
    files=( ${=files} )
    for p in $files; do
        _rmt_cfg_file $p
        args+=( proto=$p ${(f)"$(_rmt_config_files "$REPLY")"} )
    done
    (( ${#args:#proto=*} )) || return 1
    awk '
    function flush() {
        for (j = 1; j <= count; j++)
            if (!seen[names[j]]++) printf "%s\037%s\037%s\037%s\037%s\n", names[j], desc, tags, (bproto != "" ? bproto : cur), group
        count = 0; desc = tags = group = bproto = ""
    }
    FNR == 1 { flush(); cur = proto }
    { key = tolower($1) }
    key == "host" || key == "match" {
        flush()
        if (key == "host")
            for (i = 2; i <= NF; i++) {
                if ($i ~ /^#/) break
                if ($i !~ /[*?!]/) names[++count] = $i
            }
        next
    }
    key == "#_desc" { sub(/^[ \t]*#_[Dd]esc[ \t]*/, ""); desc = $0; next }
    key == "#_tags" { sub(/^[ \t]*#_[Tt]ags[ \t]*/, ""); tags = $0; next }
    key == "#_group" { sub(/^[ \t]*#_[Gg]roup[ \t]*/, ""); sub(/[ \t]+$/, ""); group = $0; next }
    key == "#_proto" { if (cur == "ftp" && tolower($2) ~ /^ftps?$/) bproto = tolower($2); next }
    END { flush() }
    ' $args 2>/dev/null
}

# Protocol of a host -> REPLY (ssh | telnet | ftp | ftps), from the first of
# the given files (default ssh, telnet, ftp) that defines it. Not found:
# REPLY=ssh, status 1.
_rmt_proto() {
    local name desc tags proto group
    REPLY=ssh
    _rmt_host_entries "${@[2,-1]}" | while IFS=$'\x1f' read -r name desc tags proto group; do
        [[ $name == $1 ]] || continue
        REPLY=$proto
        return 0
    done
    return 1
}

# `ssh -G host` (canonical: handles Include, Match, wildcards) -> _rmt_g.
# Repeated keys such as identityfile are joined with newlines.
# _rmt_resolve <alias> telnet|ftp|ftps reads that protocol's file instead
# (ssh -F), where ssh's defaults don't apply: no Port means the protocol's
# port (23, 21, 990), no User means none (anonymous for FTP).
typeset -gA _rmt_g
_rmt_resolve() {
    local line k cfg proto=${2:-ssh}
    local missing_user=__user_unset_${$}__
    _rmt_g=()
    if [[ $proto != ssh ]]; then
        _rmt_cfg_file $proto
        local file=$REPLY
        _rmt_default_port $proto
        [[ -r $file ]] || return 1
        # Append defaults after the config and rely on OpenSSH's first-value-wins: the parsed result
        # cannot tell an omitted Port 22 or User from an explicit one.
        # =() is a plain temporary file, so Match final can read it twice; zsh deletes it afterwards.
        cfg=$(umask 077; ssh -F =(command cat -- "$file"
            print -rl -- '' 'Host *' "    Port $REPLY" "    User $missing_user"
        ) -G "$1" 2>/dev/null </dev/null) || return 1
    else
        cfg=$(ssh -G "$1" 2>/dev/null </dev/null) || return 1
    fi
    for line in ${(f)cfg}; do
        k=${line%% *}
        _rmt_g[$k]+=${_rmt_g[$k]:+$'\n'}${line#* }
    done
    [[ $_rmt_g[user] == $missing_user ]] && _rmt_g[user]=''
    return 0
}

# Existing identity files ssh would use for a host (absolute paths)
_rmt_host_keys() {
    _rmt_resolve "$1" || return 1
    local f
    for f in ${(f)_rmt_g[identityfile]}; do
        f=${f/#\~/$HOME}
        [[ -f $f ]] && print -r -- "$f"
    done
}

# ══════════════════════════════════════════════
# lftp, shared by sftp-open and ftp-open: the session commands their -h and
# the pickers' -h show, and the one-line hint printed before lftp starts
# ══════════════════════════════════════════════
_rmt_help_lftp() {
    _ui_sect lftp 'in lftp (help <command> for details)'
    _ui_cmd 'ls · cd <dir> · pwd' 'browse the remote side' 36
    _ui_cmd '!ls · lcd <dir> · lpwd' 'browse the local side (starts in your current directory)' 36
    _ui_cmd 'get <file> [-o <local name>]' 'download; get -c resumes' 36
    _ui_cmd 'put <file>' 'upload' 36
    _ui_cmd 'mget <glob> · mput <glob>' 'download / upload many, e.g. mget *.log' 36
    _ui_cmd 'mirror <remote dir> [local dir]' 'download a directory; -c resumes, --only-newer skips old files' 36
    _ui_cmd 'mirror -R <local dir> [remote dir]' 'upload a directory' 36
    _ui_cmd 'pget -n 4 <file>' 'download a large file in parallel' 36
    _ui_cmd 'rm · mkdir · mv · chmod' 'remote file operations; rm -r for directories' 36
    _ui_cmd 'cat <file> · more <file>' 'view a remote file' 36
    _ui_cmd 'jobs · wait · kill' 'manage background transfers (end a command with & to background it)' 36
    _ui_cmd 'bookmark add <name>' 'save a bookmark; lftp <name> connects next time' 36
    _ui_cmd 'exit' 'quit, back to the shell' 36
}

# mc (Midnight Commander) for --tui (^O in sftp-pick / ftp-pick): local cwd
# on the left, the host on the right. Its sh:// runs the system ssh, so ssh
# config, ssh-agent, ProxyJump and password prompts all work; its ftp:// asks
# for the password in a dialog. mc has no TLS, so no FTPS.
_rmt_help_mc() {
    _ui_sect mc 'in mc (local left, remote right; on a Mac hold fn for F keys, or press Esc then the digit)'
    _ui_cmd 'Tab' 'switch panes' 36
    _ui_cmd '↑ ↓ · Enter' 'select a file · enter a directory' 36
    _ui_cmd 'Insert or Ctrl-T' 'mark several' 36
    _ui_cmd 'F5 · F6' 'copy · move to the other pane (upload / download)' 36
    _ui_cmd 'F3 · F4' 'view · edit a file' 36
    _ui_cmd 'F7 · F8' 'new directory · delete' 36
    _ui_cmd 'F10' 'quit' 36
}

# ── Helper tools ──────────────────────────────
# Package per tool: Homebrew formula, then the Debian / Ubuntu / Fedora package.
# A value with a space is a full install command for every platform.
typeset -gA _rmt_pkg_brew=( fzf fzf lftp lftp mc midnight-commander expect expect telnet telnet nc netcat tinge 'brew install iskerwin/tap/tinge' )
typeset -gA _rmt_pkg_apt=( fzf fzf lftp lftp mc mc expect expect telnet telnet nc netcat-openbsd tinge 'brew install iskerwin/tap/tinge' secret-tool libsecret-tools )
typeset -gA _rmt_pkg_dnf=( fzf fzf lftp lftp mc mc expect expect telnet telnet nc nmap-ncat tinge 'brew install iskerwin/tap/tinge' secret-tool libsecret )

# _rmt_install_cmd <tool>: how to install it here -> REPLY
_rmt_install_cmd() {
    local p
    if [[ ${_rmt_pkg_brew[$1]-} == *' '* ]]; then REPLY=$_rmt_pkg_brew[$1]
    elif [[ -n ${_rmt_pkg_brew[$1]-} ]] && (( $+commands[brew] )); then REPLY="brew install $_rmt_pkg_brew[$1]"
    elif [[ -n ${p::=${_rmt_pkg_apt[$1]-}} ]] && (( $+commands[apt-get] )); then REPLY="sudo apt install $p"
    elif [[ -n ${p::=${_rmt_pkg_dnf[$1]-}} ]] && (( $+commands[dnf] )); then REPLY="sudo dnf install $p"
    elif [[ -n ${_rmt_pkg_brew[$1]-} ]]; then REPLY="brew install $_rmt_pkg_brew[$1]"
    else REPLY="install $1 with your package manager"
    fi
}

# _rmt_need <tool> <caller>: a tool the caller cannot work without; missing -> error with the install command
_rmt_need() {
    (( $+commands[$1] )) && return 0
    _rmt_install_cmd $1
    _ui_err "$2 needs $1 — $REPLY"
    return 1
}

# _rmt_need_fzf <caller>: fzf 0.58+ (input / list / preview boxes); options newer than that are
# added only when the installed fzf has them (_ui_fzf_since)
_rmt_need_fzf() {
    _rmt_need fzf $1 || return 1
    _ui_fzf_since 0.58 && return 0
    _ui_fzf_ver
    local found=$(( REPLY / 1000000 )).$(( REPLY / 1000 % 1000 )).$(( REPLY % 1000 ))
    if (( $+commands[brew] )); then REPLY='brew upgrade fzf'
    else REPLY='https://github.com/junegunn/fzf/releases (distribution packages are often older)'
    fi
    _ui_err "$1 needs fzf 0.58 or newer, found $found — $REPLY"
    return 1
}

# _rmt_tip <tool> <what it adds>: an optional tool is missing; say so once per shell.
# REMOTE_TIPS=0 turns the tips off; remote-doctor lists every tool.
typeset -gA _rmt_tipped
_rmt_tip() {
    [[ ${REMOTE_TIPS-1} == 0 || -n ${_rmt_tipped[$1]-} ]] && return 0
    _rmt_tipped[$1]=1
    _rmt_install_cmd $1
    _ui_hint "Tip: $1 adds $2 — $REPLY  (remote-doctor lists all, REMOTE_TIPS=0 hides tips)"
}

_rmt_lftp_hint() {
    _ui_hint "lftp: ls · cd · get/put · mirror [-R] · lcd · help · exit   ${_ui[r]}(${1}-open -h lists more)"
}

# ══════════════════════════════════════════════
# Passwords in the system keychain: macOS Keychain (security), Linux Secret
# Service (secret-tool). Entries are <service, account>: net-backup keeps
# device passwords under service net-backup, ftp-open under service ftp-open.
# ══════════════════════════════════════════════
_rmt_keychain() { [[ $OSTYPE == darwin* ]] || (( $+commands[secret-tool] )); }

# _rmt_secret <service> <account> -> REPLY; status 1 when there is none
_rmt_secret() {
    REPLY=''
    if [[ $OSTYPE == darwin* ]]; then
        REPLY=$(security find-generic-password -s "$1" -a "$2" -w 2>/dev/null)
    elif (( $+commands[secret-tool] )); then
        REPLY=$(secret-tool lookup service "$1" account "$2" 2>/dev/null)
    fi
    [[ -n $REPLY ]]
}

# Whether an entry exists, without reading the secret (macOS)
_rmt_secret_has() {
    if [[ $OSTYPE == darwin* ]]; then
        security find-generic-password -s "$1" -a "$2" &>/dev/null
    else
        _rmt_secret "$1" "$2"
    fi
}

# Ask for a password and store it: _rmt_secret_store <service> <account>
_rmt_secret_store() {
    if [[ $OSTYPE == darwin* ]]; then
        security add-generic-password -s "$1" -a "$2" -l "$1 $2" -w
    elif (( $+commands[secret-tool] )); then
        secret-tool store --label="$1 $2" service "$1" account "$2"
    else
        _ui_err 'No keychain: macOS uses security, Linux needs secret-tool (libsecret-tools)'
        return 1
    fi
}

# _rmt_secret_delete <service> <account>; status 1 when there was none
_rmt_secret_delete() {
    if [[ $OSTYPE == darwin* ]]; then
        security delete-generic-password -s "$1" -a "$2" &>/dev/null
    elif (( $+commands[secret-tool] )); then
        _rmt_secret "$1" "$2" || return 1
        secret-tool clear service "$1" account "$2"
    else
        return 1
    fi
}
