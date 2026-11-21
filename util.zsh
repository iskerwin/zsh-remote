# zsh-remote/util.zsh — internal helpers (no side effects; helper processes source it too)

# Run a command with a time limit; status 142 (SIGALRM) on timeout: _rmt_timeout <seconds> <command...>
# macOS has no timeout(1); an alarm survives exec, and exec's block form passes arguments untouched
_rmt_timeout() {
    local -i seconds=$1
    shift
    command perl -e 'alarm shift; exec { $ARGV[0] } @ARGV or die "$ARGV[0]: $!\n"' $seconds "$@"
}

# Atomically create a new owner-only file: _rmt_private_new <dir> <stem> <suffix> [final suffixes...] → REPLY
# Creates the directory as 700 if missing; on a clash the stem gets -1, -2, … O_EXCL keeps concurrent
# callers apart. Pass the suffixes the file will later be renamed to, so those names are skipped as well
_rmt_private_new() {
    emulate -L zsh
    zmodload zsh/system || return 1
    ( umask 077; command mkdir -p -- "$1" ) || return 1
    local file fd stem done
    local -i n
    for (( n = 0; n < 100; n++ )); do
        stem=$1/$2${${n:#0}:+-$n}
        file=$stem$3
        for done in "${@[4,-1]}"; do
            [[ -e $stem$done || -L $stem$done ]] && continue 2
        done
        if sysopen -w -o excl -m 600 -u fd "$file" 2>/dev/null; then
            exec {fd}>&-
            REPLY=$file
            return 0
        fi
        [[ -e $file ]] || return 1
    done
    return 1
}

# -h / --help of a public command, from the "# @desc:" and "# @usage:" comments above it: _rmt_help <command>
_rmt_help() {
    emulate -L zsh
    zmodload zsh/parameter
    local name=$1 desc= usage= line
    local file=${functions_source[$name]-}
    if [[ -r $file ]]; then
        for line in ${(f)"$(command awk -v n="$name" '
            /^[[:space:]]*#[[:space:]]*@desc:/  { sub(/^[[:space:]]*#[[:space:]]*@desc:[[:space:]]*/, ""); d = $0; next }
            /^[[:space:]]*#[[:space:]]*@usage:/ { sub(/^[[:space:]]*#[[:space:]]*@usage:[[:space:]]*/, ""); u = $0; next }
            /^[[:space:]]*#/ { next }
            $0 ~ "^" n "[[:space:]]*\\(\\)" { print d; print u; exit }
            { d = u = "" }' "$file")"}; do
            if [[ -z $desc ]]; then desc=$line; else usage=$line; fi
        done
    fi
    _ui_head $name "$desc"
    _ui_palette
    usage=${usage:-$name}
    print -r -- "  ${_ui[grn]}${usage%% *}${_ui[r]}${_ui[cyn]}${usage#${usage%% *}}${_ui[r]}"
}

# Whether tinge is installed for highlighting; if not, tip once and let the caller fall back
_rmt_tinge() {
    (( $+commands[tinge] )) || { _rmt_tip tinge 'highlighting'; return 1; }
}
