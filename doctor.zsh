# ══════════════════════════════════════════════
# doctor.zsh — remote-doctor: which helper tools are installed, and how to get the missing ones
# ══════════════════════════════════════════════

# @desc: List the tools zsh-remote uses, which are installed, and how to install the missing ones
# @usage: remote-doctor
remote-doctor() {
    [[ ${1-} == (-h|--help) ]] && { _rmt_help $0; return 0; }
    local -i missing=0
    local t what
    _ui_head remote-doctor 'helper tools'
    _ui_sect required
    for t what in \
        ssh 'every command' \
        fzf 'the pickers (*-pick, ssh-ag, net-backup without arguments)'; do
        _rmt_doctor_row $t "$what" || (( ++missing ))
    done
    _ui_sect optional 'commands work without them, minus what they add'
    for t what in \
        ct 'ChromaTerm highlighting in ssh-ct / telnet-ct' \
        lftp 'sftp-open (falls back to sftp); ftp-open needs it' \
        mc 'two-pane browser: ^O, --tui' \
        telnet 'telnet-ct and telnet devices in net-backup' \
        expect 'net-backup' \
        nc '^T banner for Telnet / FTP (the port check works without it)'; do
        _rmt_doctor_row $t "$what"
    done
    if [[ $OSTYPE == darwin* ]]; then
        _ui_ok "keychain  ${_ui[gry]}saved FTP / net-backup passwords (macOS Keychain)${_ui[r]}"
    else
        _rmt_doctor_row secret-tool 'saved FTP / net-backup passwords (asked every time without it)'
    fi
    _ui_sect look
    if (( $+functions[_ui_palette] )) && [[ ${functions_source[_ui_palette]:t} != ui-fallback.zsh ]]; then
        _ui_ok "zsh-ui  ${_ui[gry]}shared look with your other tools${_ui[r]}"
    else
        _ui_hint "zsh-ui not loaded — plain built-in look; github.com/iskerwin/zsh-ui for the shared one"
    fi
    (( missing == 0 ))
}

# _rmt_doctor_row <tool> <what it is for>: ✓ or ✗ with the install command
_rmt_doctor_row() {
    if (( $+commands[$1] )); then
        _ui_ok "$1  ${_ui[gry]}$2${_ui[r]}"
    else
        _rmt_install_cmd $1
        _ui_warn "$1  ${_ui[gry]}$2${_ui[r]}  → $REPLY"
        return 1
    fi
}

compdef _nothing remote-doctor
