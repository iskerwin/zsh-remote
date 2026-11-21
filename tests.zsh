#!/bin/zsh
# A local fake ssh plays the device for the real Expect script; no network, no real credentials.
emulate -L zsh
setopt err_return pipe_fail
unsetopt bgnice
local here=${${(%):-%x}:A:h}
source $here/util.zsh
source $here/ui-fallback.zsh
local tmp=$(mktemp -d)
trap 'command rm -rf -- "$tmp"' EXIT
# Load the protocol files in the plugin's order; not agent.zsh (it checks and starts ssh-agent on load); compdef is a no-op
print -r -- "compdef() { :; }
source ${(q)here}/lib.zsh
for f in picker ssh sftp telnet ftp; do source ${(q)here}/\$f.zsh; done" > $tmp/load.zsh
local -i passed=0
assert() {
    [[ $2 == $3 ]] || { print -ru2 -- "$1: expected ${(qqq)2}, got ${(qqq)3}"; exit 1; }
    (( ++passed ))
}
mkdir -p $tmp/bin
cat > $tmp/bin/ssh <<'EOF'
#!/bin/zsh -f
stty -echo
local prompt='sw#' line
[[ $DEVICE_CASE == vrp ]] && prompt='<sw>'
[[ $DEVICE_CASE == enable-eof ]] && prompt='sw>'
print -n -- "$prompt"
while IFS= read -r line; do
    line=${line%$'\r'}
    print -r -- "$line"
    case $line in
        enable) exit 0 ;;
        'show running-config'|'display current-configuration')
            case $DEVICE_CASE in
                denied) print -r -- '% Permission denied' ;;
                eof) exit 0 ;;
                full)
                    # echo 21 + config 3997 + prompt 3 = 4021 characters in one write: the last read takes expect's
                    # buffer just past 4000 (twice the default match_max of 2000), with the prompt right at the end
                    local i block=''
                    for i in {1..99}; do block+="description ${(l:26::0:)i}"$'\n'; done
                    print -rn -- "${block}${(l:30::x:):-}"$'\n'"end"$'\n'"$prompt"
                    continue ;;
                more*)
                    # The pager prompt arrives in two pieces; after one key the device erases it with backspaces, extra keys echo as a line
                    local key cut=5
                    [[ $DEVICE_CASE == more-late ]] && cut=8
                    print -r -- 'hostname sw'
                    print -rn -- "${${:- --More-- }[1,cut]}"
                    sleep 0.2
                    print -rn -- "${${:- --More-- }[cut+1,-1]}"
                    read -k 1 key
                    print -rn -- "${(pl:10::\b:):-}${(l:10:: :):-}${(pl:10::\b:):-}"
                    read -t 0.3 -k 1 key && print -r -- 'extra key'
                    print -r -- 'interface vlan 1'
                    print -r -- end ;;
                large)
                    local i
                    for i in {1..9000}; do print -r -- "description test-interface-$i"; done
                    print -r -- end ;;
                *) print -r -- 'hostname sw'
                   if [[ $DEVICE_CASE == vrp ]]; then print -r -- return; else print -r -- end; fi ;;
            esac
            ;;
        exit|quit) exit 0 ;;
    esac
    print -n -- "$prompt"
done
EOF
chmod +x $tmp/bin/ssh
# Homebrew's and macOS's expect behave differently when the buffer fills, so test both
local out rc scenario expect
local -a expects=( $commands[expect] )
[[ -x /usr/bin/expect && $commands[expect] != /usr/bin/expect ]] && expects+=( /usr/bin/expect )
for expect in $expects; do
    for scenario in ios vrp large full more more-late denied eof enable-eof; do
        rc=0
        out=$(PATH="$tmp/bin:$PATH" DEVICE_CASE=$scenario NETBAK_PASS=test-only \
            _rmt_timeout 15 $expect "$here/net-backup.exp" demo 2>"$tmp/error") || rc=$?
        case $scenario in
            ios) assert "$expect: IOS config" $'hostname sw\nend' "$out" ;;
            vrp) assert "$expect: VRP config" $'hostname sw\nreturn' "$out" ;;
            large)
                assert "$expect: large config first line" 'description test-interface-1' "${${(f)out}[1]}"
                assert "$expect: large config last line" end "${${(f)out}[-1]}"
                assert "$expect: large config no buffer loss" 9001 "${#${(f)out}}" ;;
            full) assert "$expect: prompt arriving as the buffer fills" 101 "${#${(f)out}}" ;;
            more*) assert "$expect: $scenario pages once" $'hostname sw\ninterface vlan 1\nend' "$out" ;;
            *) assert "$expect: $scenario fails" 1 "$rc" ;;
        esac
        if [[ $scenario == (ios|vrp|large|full|more*) ]]; then assert "$expect: $scenario succeeds" 0 "$rc"; fi
    done
done

# Concurrent terminals share one fallback agent; fake ssh-add / ssh-agent, no real processes.
mkdir -p $tmp/agent-bin $tmp/agent-home/.ssh
cat > $tmp/agent-bin/agent-stub <<'EOF'
#!/bin/zsh -f
case ${0:t} in
    launchctl) exit 1 ;;
    ssh-add) [[ -f $SSH_AUTH_SOCK ]] && exit 1; exit 2 ;;
    ssh-agent)
        sleep 0.05
        print -r -- start >> "$AGENT_TEST_LOG"
        : > "$2"
        ;;
esac
EOF
chmod +x $tmp/agent-bin/agent-stub
for scenario in ssh-add ssh-agent launchctl; do ln -s agent-stub $tmp/agent-bin/$scenario; done
cat > $tmp/agent-worker.zsh <<'EOF'
compdef() { :; }
source "$AGENT_TEST_SOURCE/lib.zsh" && source "$AGENT_TEST_SOURCE/agent.zsh" || exit 1
[[ $SSH_AUTH_SOCK == "$HOME/.ssh/agent.sock" ]]
EOF
local -a workers
local worker
for worker in {1..12}; do
    env HOME="$tmp/agent-home" SSH_AUTH_SOCK="$tmp/no-agent" \
        PATH="$tmp/agent-bin:$PATH" AGENT_TEST_SOURCE="$here" AGENT_TEST_LOG="$tmp/agent-log" \
        zsh -f "$tmp/agent-worker.zsh" &
    workers+=( $! )
done
for worker in $workers; do wait $worker; done
assert 'concurrent agent starts once' 1 "$(wc -l < "$tmp/agent-log" | tr -d ' ')"
assert 'agent lock is private' 600 "$(zmodload -F zsh/stat b:zstat; m=$(zstat -o +mode -- "$tmp/agent-home/.ssh/agent.sock.lock"); print -r -- ${m[-3,-1]})"
# File transfer (sftp-open in sftp.zsh, ftp-open in ftp.zsh):
# - sftp-open: hosts with key login pass only the alias to lftp; password-only hosts add -u <user> so lftp prompts; sftp without lftp
# - ftp-open: address, port and user from ftp_config; the password comes from the keychain via LFTP_PASSWORD, never in arguments; no User means anonymous
# Fake ssh: -F (telnet / ftp files) goes to the real ssh for parsing, other -G returns a fixed user and refuses keys for pw; no network.
# Fake keychain (security / secret-tool) stores passwords as $KC_DIR/<service>.<account>, never the real keychain.
mkdir -p $tmp/sftp-bin $tmp/sftp-nolftp $tmp/kc
print -r -- $'Host web pw\n    HostName 192.0.2.10' > $tmp/sftp-config
print -r -- $'Host sw\n    HostName 192.0.2.20' > $tmp/sftp-telnet
print -r -- $'Host nas\n    HostName 192.0.2.30\n    User admin\n    #_Proto ftps\nHost pub\n    HostName 192.0.2.31\n    Port 2121\nHost plain\n    HostName 192.0.2.32\n    User bob' > $tmp/sftp-ftp
for worker in lftp sftp mc; do
    print -r -- $'#!/bin/sh\necho "${0##*/} $* | pw=$LFTP_PASSWORD" > "$SFTP_TEST_LOG"' > $tmp/sftp-bin/$worker
    chmod +x $tmp/sftp-bin/$worker
done
print -r -- '#!/bin/sh
case " $* " in
    *" -F "*) exec "$REAL_SSH" "$@" ;;
    *" -G "*) printf "user root\nhostname 192.0.2.10\nport 22\n" ;;
    *" pw true ") echo "root@192.0.2.10: Permission denied (publickey,password)." >&2; exit 255 ;;
esac' > $tmp/sftp-bin/ssh
print -r -- '#!/bin/sh
# security {find,add,delete}-generic-password -s <service> -a <account> [-w]
cmd=$1; shift; s=; a=; w=
while [ $# -gt 0 ]; do
    case $1 in -s) s=$2; shift ;; -a) a=$2; shift ;; -l) shift ;; -w) w=1 ;; esac
    shift
done
f="$KC_DIR/$s.$a"
case $cmd in
    find-generic-password) [ -f "$f" ] || exit 44; [ -n "$w" ] && cat "$f"; exit 0 ;;
    add-generic-password) IFS= read -r pw && printf %s "$pw" > "$f" ;;
    delete-generic-password) [ -f "$f" ] && rm -f "$f" ;;
esac' > $tmp/sftp-bin/security
print -r -- '#!/bin/sh
# secret-tool {lookup,store [--label=…],clear} service <service> account <account>
cmd=$1; shift; [ "${1#--label}" != "$1" ] && shift
f="$KC_DIR/$2.$4"
case $cmd in
    lookup) [ -f "$f" ] && cat "$f" ;;
    store) IFS= read -r pw && printf %s "$pw" > "$f" ;;
    clear) rm -f "$f" ;;
esac' > $tmp/sftp-bin/secret-tool
chmod +x $tmp/sftp-bin/ssh $tmp/sftp-bin/security $tmp/sftp-bin/secret-tool
ln -s $tmp/sftp-bin/sftp $tmp/sftp-nolftp/sftp
for worker in zsh ssh; do ln -s $commands[$worker] $tmp/sftp-nolftp/$worker; done
export REAL_SSH=$commands[ssh] KC_DIR=$tmp/kc SFTP_TEST_LOG=$tmp/sftp-log \
    REMOTE_SSH_CONFIG=$tmp/sftp-config REMOTE_TELNET_CONFIG=$tmp/sftp-telnet REMOTE_FTP_CONFIG=$tmp/sftp-ftp
# open_run <PATH> <command> <args…>: run under zsh -f with the files loaded, print what fake lftp / sftp recorded; stdin from the caller
open_run() {
    local path_=$1; shift
    command rm -f -- "$tmp/sftp-log"
    PATH=$path_ zsh -f -c 'source "$1"; shift; "$@"' _ "$tmp/load.zsh" "$@" &>/dev/null || return
    [[ ! -e $tmp/sftp-log ]] || command cat -- "$tmp/sftp-log"
}
local bin="$tmp/sftp-bin:$PATH"
assert 'sftp-open: key host gets the bare alias' 'lftp sftp://web | pw=' "$(open_run $bin sftp-open web </dev/null)"
assert 'sftp-open: password host makes lftp prompt' 'lftp -u root sftp://pw | pw=' "$(open_run $bin sftp-open pw </dev/null)"
assert 'sftp-open: falls back to sftp without lftp' 'sftp web | pw=' "$(open_run $tmp/sftp-nolftp sftp-open web </dev/null)"
rc=0; open_run $tmp/sftp-nolftp ssh-pick </dev/null >/dev/null || rc=$?
assert 'pick: without fzf the picker fails, the open commands still load' 1 "$rc"
assert 'ftp-open: anonymous, non-default port in the URL' 'lftp ftp://192.0.2.31:2121 | pw=' "$(open_run $bin ftp-open pub </dev/null)"
rc=0; open_run $bin ftp-open web </dev/null >/dev/null || rc=$?
assert 'ftp-open: an SSH host is not an FTP host' 1 "$rc"
assert 'ftp-open: first login stores the password, lftp gets it via env' \
    'lftp --env-password -u admin ftps://192.0.2.30 | pw=first pw' "$(print -r -- 'first pw' | open_run $bin ftp-open nas)"
assert 'ftp-open: password stored under service ftp-open' 'first pw' "$(<$tmp/kc/ftp-open.nas)"
print -rn -- s3cret > $tmp/kc/ftp-open.nas
assert 'ftp-open: stored password reused, never in argv' \
    'lftp --env-password -u admin ftps://192.0.2.30 | pw=s3cret' "$(open_run $bin ftp-open nas </dev/null)"
open_run $bin ftp-open --forget nas </dev/null >/dev/null
assert 'ftp-open --forget removes the stored password' no "$([[ -e $tmp/kc/ftp-open.nas ]] && print yes || print no)"
# --tui: mc with the current directory left and the host right; SFTP via sh:// (system ssh), FTP via ftp:// (mc asks for the password, the keychain one never goes into arguments), no FTPS
assert 'sftp-open --tui: mc, local cwd left, host right' "mc -u $PWD sh://web | pw=" "$(open_run $bin sftp-open --tui web </dev/null)"
rc=0; open_run $tmp/sftp-nolftp sftp-open --tui web </dev/null >/dev/null || rc=$?
assert 'sftp-open --tui: fails without mc' 1 "$rc"
print -rn -- s3cret > $tmp/kc/ftp-open.plain
assert 'ftp-open --tui: mc gets user and host, no password' "mc -u $PWD ftp://bob@192.0.2.32/ | pw=" "$(open_run $bin ftp-open --tui plain </dev/null)"
command rm -f -- $tmp/kc/ftp-open.plain
assert 'ftp-open --tui: anonymous, non-default port' "mc -u $PWD ftp://192.0.2.31:2121/ | pw=" "$(open_run $bin ftp-open --tui pub </dev/null)"
rc=0; open_run $bin ftp-open --tui nas </dev/null >/dev/null || rc=$?
assert 'ftp-open --tui: FTPS refused (mc has no TLS)' 1 "$rc"

# Pickers: a fake fzf records its arguments and input and selects $PICK; the four open commands are replaced by recorders
print -r -- '#!/bin/sh
printf "%s\n" "$@" > "$PICK_ARGS"
# $PICK_TUI simulates ^O: the print(tui) action outputs a tui line first
[ -n "$PICK_TUI" ] && echo tui
tee "$PICK_LIST" | awk -F "\t" -v p="$PICK" "\$1 == p && !done { print; done = 1 }"' > $tmp/sftp-bin/fzf
print -r -- "#!/bin/sh
exec zsh -f ${(q)here}/helper \"\$@\"" > $tmp/pick-helper
chmod +x $tmp/sftp-bin/fzf $tmp/pick-helper
# pick_run <picked alias> <picker> [args…] → the open command called and its arguments
pick_run() {
    command rm -f -- "$tmp/sftp-log"
    (
        export PATH="$tmp/sftp-bin:$PATH" PICK_ARGS=$tmp/pick-args PICK_LIST=$tmp/pick-list PICK=$1
        shift
        source $tmp/load.zsh
        _RMT_HELPER=$tmp/pick-helper
        for f in ssh-ct sftp-open telnet-ct ftp-open; do
            functions[$f]="print -r -- \"$f \$*\" > \"\$SFTP_TEST_LOG\""
        done
        "$@" </dev/null
    ) &>$tmp/pick-out
    local rc=$?
    [[ -e $tmp/sftp-log ]] && command cat -- "$tmp/sftp-log"
    return rc
}
listed() { print -r -- ${(j: :)${(f)"$(cut -f1 $tmp/pick-list | command grep .)"}}; }
has_arg() { command grep -qx -e "$1" $tmp/pick-args && print yes; }
assert 'ssh-pick: Enter runs ssh-ct' 'ssh-ct web' "$(pick_run web ssh-pick we)"
assert 'ssh-pick: lists ssh config hosts only' 'web pw' "$(listed)"
assert 'ssh-pick: query reaches fzf' yes "$(has_arg --query=we)"
assert 'ssh-pick: has ^A' yes "$(command grep -q '^--bind=ctrl-a:' $tmp/pick-args && print yes)"
assert 'sftp-pick: Enter runs sftp-open' 'sftp-open pw' "$(pick_run pw sftp-pick)"
assert 'sftp-pick: lists ssh config hosts' 'web pw' "$(listed)"
assert 'telnet-pick: Enter runs telnet-ct' 'telnet-ct sw' "$(pick_run sw telnet-pick)"
assert 'telnet-pick: lists telnet_config only' sw "$(listed)"
assert 'telnet-pick: no ^A' no "$(command grep -q '^--bind=ctrl-a:' $tmp/pick-args && print yes || print no)"
assert 'ftp-pick: Enter runs ftp-open' 'ftp-open nas' "$(pick_run nas ftp-pick)"
assert 'ftp-pick: lists ftp_config only' 'nas pub plain' "$(listed)"
assert 'ftp-pick: FTP rows show the icon, not the port' no "$(cut -f4 $tmp/pick-list | command grep -qE '(^|─ )(990|21) ' && print yes || print no)"
assert 'ftp-pick: ^E edits the ftp file' yes "$(has_arg "--bind=ctrl-e:execute($tmp/pick-helper edit-config ftp)+reload($tmp/pick-helper hosts ftp)")"
assert 'pick: -- keeps a dash query' 'ssh-ct web' "$(pick_run web ssh-pick -- -x)"
assert 'pick: dash query reaches fzf' yes "$(has_arg --query=-x)"
rc=0; pick_run '' ssh-pick -x >/dev/null || rc=$?
assert 'pick: unknown option fails' 2 "$rc"
assert 'sftp-pick: ^O opens with sftp-open --tui' 'sftp-open --tui pw' "$(PICK_TUI=1 pick_run pw sftp-pick)"
assert 'sftp-pick: ^O is bound' yes "$(command grep -q '^--bind=ctrl-o:transform:' $tmp/pick-args && print yes)"
assert 'ftp-pick: ^O opens with ftp-open --tui' 'ftp-open --tui nas' "$(PICK_TUI=1 pick_run nas ftp-pick)"
pick_run web ssh-pick >/dev/null
assert 'ssh-pick: no ^O' no "$(command grep -q '^--bind=ctrl-o:transform:' $tmp/pick-args && print yes || print no)"
assert '\\<Tab> completion: no ^O' no "$(source $tmp/load.zsh; local -a reply; _rmt_pick_fzf_args sftp; [[ ${(M)reply:#--bind=ctrl-o:transform:*} != '' ]] && print yes || print no)"
local help
help=$(pick_run '' ftp-pick -h; command cat -- $tmp/pick-out)
assert 'ftp-pick -h: keys, ftp config and lftp commands' yes "${${(M)help:#*ftp-open*'^T'*'#_Proto ftps'*'mirror -R'*}:+yes}"
assert 'ftp-pick -h: no ^A' no "$([[ $help == *'^A'* ]] && print yes || print no)"
assert 'ftp-pick -h: ^O and mc keys' yes "${${(M)help:#*'^O'*mc*F5*}:+yes}"
help=$(pick_run '' ssh-pick -h; command cat -- $tmp/pick-out)
assert 'ssh-pick -h: ssh session commands' yes "$([[ $help == *'~.'* ]] && print yes)"
assert 'ssh-pick -h: no lftp or telnet commands' no "$([[ $help == *(mirror|'Ctrl-] quit')* ]] && print yes || print no)"
assert 'ssh-pick -h: no ^O' no "$([[ $help == *'^O'* ]] && print yes || print no)"
help=$(pick_run '' telnet-pick -h; command cat -- $tmp/pick-out)
assert 'telnet-pick -h: telnet session commands' yes "${${(M)help:#*'Ctrl-] quit'*}:+yes}"
# \<Tab> completion: _fzf_complete appends $PICK to the line (no fzf needed); check the rewritten line
# tab_run <picked alias> <completion function> <text before the cursor> → the rewritten LBUFFER
tab_run() {
    ( source $tmp/load.zsh
      _RMT_HELPER=$tmp/pick-helper
      _fzf_complete() { command cat >/dev/null; LBUFFER+=$PICK; }
      PICK=$1 LBUFFER=$3 prefix=
      $2 >/dev/null 2>&1 || :   # returns 1 when nothing is picked
      print -r -- "$LBUFFER" )
}
export PATH="$tmp/sftp-bin:$PATH"
assert 'ftp \<Tab>: line becomes ftp-open <alias>' 'ftp-open nas ' "$(tab_run nas _fzf_complete_ftp 'ftp ')"
assert 'sftp-open \<Tab>: line becomes sftp-open <alias>' 'sftp-open web ' "$(tab_run web _fzf_complete_sftp-open 'sftp-open ')"
assert 'ssh \<Tab>: keeps typed arguments, ssh becomes ssh-ct' 'ssh-ct -p 2222 web' "$(tab_run web _fzf_complete_ssh 'ssh -p 2222 ')"
assert 'ssh-ct \<Tab>: line kept' 'ssh-ct web' "$(tab_run web _fzf_complete_ssh-ct 'ssh-ct ')"
assert 'ssh \<Tab>: an assignment before ssh is not rewritten' 'FOO=1 ssh web' "$(tab_run web _fzf_complete_ssh 'FOO=1 ssh ')"
assert '\<Tab>: nothing picked leaves the line' 'ftp ' "$(tab_run '' _fzf_complete_ftp 'ftp ')"
help=$(source $tmp/load.zsh; ssh-ct -h; telnet-ct --help; sftp-open -h; ftp-open -h)
assert 'open commands -h list their session commands' yes \
    "${${(M)help:#*ssh-ct*'~.'*telnet-ct*'Ctrl-] quit'*sftp-open*mirror*ftp-open*'#_Proto ftps'*}:+yes}"

# zsh-ui: the plugin works without it (ui-fallback.zsh) and zsh-ui wins in either load order;
# helper processes load zsh-ui from ZSH_UI_DIR when it is set.
# ssh-add reports a working agent and HOME is temporary, so loading agent.zsh never starts a real ssh-agent
# ssh-cfg / telnet-cfg / ftp-cfg open the protocol's file; not managed by chezmoi, so $VISUAL is used
for k f in ssh $tmp/cfg/ssh telnet $tmp/cfg/telnet ftp $tmp/cfg/ftp; do
    assert "$k-cfg: edits its file" $f "$(env -u ZSH_UI_DIR HOME=$tmp REMOTE_SSH_CONFIG=$tmp/cfg/ssh REMOTE_TELNET_CONFIG=$tmp/cfg/telnet REMOTE_FTP_CONFIG=$tmp/cfg/ftp VISUAL='print -r --' \
        zsh -f -c 'compdef() { :; }; ssh-add() { return 1; }; source $1/zsh-remote.plugin.zsh; $2-cfg' _ $here $k 2>/dev/null)"
done

print -r -- "compdef() { :; }; ssh-add() { return 1; }; HOME=${(q)tmp}" > $tmp/stub.zsh
assert 'fallback without zsh-ui' ui-fallback.zsh \
    "$(env -u ZSH_UI_DIR zsh -f -c 'source $1; source $2/zsh-remote.plugin.zsh 2>/dev/null; print -r -- ${functions_source[_ui_err]:t}' _ $tmp/stub.zsh $here)"
assert 'zsh-ui loaded first wins' zsh-ui \
    "$(env -u ZSH_UI_DIR zsh -f -c 'source $1; _ui_err() { print zsh-ui; }; source $2/zsh-remote.plugin.zsh 2>/dev/null; _ui_err' _ $tmp/stub.zsh $here)"
assert 'zsh-ui loaded later wins' zsh-ui \
    "$(env -u ZSH_UI_DIR zsh -f -c 'source $1; source $2/zsh-remote.plugin.zsh 2>/dev/null; _ui_err() { print zsh-ui; }; _ui_err' _ $tmp/stub.zsh $here)"
mkdir -p $tmp/fake-ui
print -r -- '_ui_err() { print fake-zsh-ui; }' > $tmp/fake-ui/ui.zsh
assert 'helper uses ZSH_UI_DIR' fake-zsh-ui "$(ZSH_UI_DIR=$tmp/fake-ui zsh -f -c 'source $1/lib.zsh; _ui_err' _ $here)"
assert 'helper falls back without ZSH_UI_DIR' ui-fallback.zsh "$(env -u ZSH_UI_DIR zsh -f -c 'source $1/lib.zsh; print -r -- ${functions_source[_ui_err]:t}' _ $here)"
print -r -- "$passed passed"
