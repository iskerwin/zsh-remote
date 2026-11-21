#!/bin/zsh
# Config parsing (lib.zsh) and net-backup (netbak.zsh) tests: sample files in a temporary HOME only,
# never the real ~/.ssh or keychain, and the Expect script is replaced by stubs.
emulate -L zsh
setopt err_return no_unset pipe_fail
local here=${${(%):-%x}:A:h}
local tmp=$(mktemp -d) || exit 1
trap 'command rm -rf -- $tmp' EXIT

local -i passed=0 failed=0
t_eq() {   # t_eq <name> <expected> <actual>
    if [[ $2 == $3 ]]; then
        (( ++passed ))
    else
        (( ++failed ))
        print -r -- "✗ $1"
        print -r -- "    expected: ${(q+)2}"
        print -r -- "    actual:   ${(q+)3}"
    fi
}

mkdir -p $tmp/home/.ssh/conf.d
cat > $tmp/home/.ssh/config <<'EOF'
Include conf.d/*
Host *
    ServerAliveInterval 30

Host core-sw sw-alias
    HostName 10.0.0.1
    #_Desc core switch
    #_Tags ruijie, switch
    #_Group site-a

HOST web
    HostName 10.0.0.2

Match host foo
    #_Desc belongs to no host

Host *.corp !bad
    User nobody
EOF
cat > $tmp/home/.ssh/conf.d/extra <<'EOF'
Host db
  #_desc database
EOF
cat > $tmp/home/.ssh/telnet_config <<'EOF'
Host old-router
    HostName 10.0.0.9
    #_Group site-a

Host web
    HostName 10.9.9.9

Host plain
    HostName 10.0.0.10
    Port 2323
    User admin
EOF
cat > $tmp/home/.ssh/ftp_config <<'EOF'
Host nas
    HostName 192.0.2.30
    User admin
    #_Proto FTPS
    #_Tags switch
    #_Group site-a
Host pub db
    HostName 192.0.2.31
    Port 2121
Host odd
    HostName 192.0.2.32
    #_Proto sftp
EOF


HOME=$tmp/home
REMOTE_SSH_CONFIG=$HOME/.ssh/config
REMOTE_TELNET_CONFIG=$HOME/.ssh/telnet_config
REMOTE_FTP_CONFIG=$HOME/.ssh/ftp_config
compdef() { :; }
source $here/lib.zsh
ZSH_REMOTE_DIR=$here
source $here/netbak.zsh
setopt no_err_return   # functions return 1 for "none"; that must not stop the script

# ── ssh / telnet / ftp config ────────────────
local sep=$'\x1f'
# Each picker reads its own config file; sftp shares the ssh config
for v in ssh:ssh sftp:ssh telnet:telnet ftp:ftp; do
    _rmt_kind_file ${v%%:*}
    t_eq "kind_file ${v%%:*}" ${v#*:} "$REPLY"
done
t_eq 'config_files: main file + relative Include (relative to ~/.ssh)' \
    "$HOME/.ssh/config"$'\n'"$HOME/.ssh/conf.d/extra" "$(_rmt_config_files)"

t_eq 'host_entries all: skip wildcards / Match, read #_Desc #_Tags #_Group, skip names already seen' \
    "core-sw${sep}core switch${sep}ruijie, switch${sep}ssh${sep}site-a
sw-alias${sep}core switch${sep}ruijie, switch${sep}ssh${sep}site-a
web${sep}${sep}${sep}ssh${sep}
db${sep}database${sep}${sep}ssh${sep}
old-router${sep}${sep}${sep}telnet${sep}site-a
plain${sep}${sep}${sep}telnet${sep}
nas${sep}${sep}switch${sep}ftps${sep}site-a
pub${sep}${sep}${sep}ftp${sep}
odd${sep}${sep}${sep}ftp${sep}" "$(_rmt_host_entries)"

t_eq 'host_entries ssh telnet: the two net-backup reads, no FTP' \
    'core-sw sw-alias web db old-router plain' "${(j: :)${(f)$(_rmt_host_entries ssh telnet | cut -d$sep -f1)}}"
t_eq 'host_entries ftp: #_Proto accepts only ftp / ftps, reset per Host block' \
    "nas:ftps pub:ftp db:ftp odd:ftp" "${(j: :)${(f)$(_rmt_host_entries ftp | awk -F$sep '{print $1 ":" $4}')}}"

t_eq 'host_entries telnet: telnet file only' \
    'old-router web plain' "${(j: :)${(f)$(_rmt_host_entries telnet | cut -d$sep -f1)}}"

local h
for h in old-router:telnet plain:telnet core-sw:ssh web:ssh no-such-host:ssh nas:ftps pub:ftp db:ssh; do
    _rmt_proto ${h%%:*}
    t_eq "proto ${h%%:*}" ${h#*:} $REPLY
done
_rmt_proto web telnet
t_eq 'proto limited to a file: web in the telnet file' telnet $REPLY
_rmt_proto nas ssh
t_eq 'proto limited to a file: status 1 when not in the ssh config' '1 ssh' "$? $REPLY"
_rmt_proto db ftp
t_eq 'proto limited to a file: db in the ftp file' ftp $REPLY
_rmt_resolve nas ftps
t_eq 'resolve ftps: no Port means 990' '192.0.2.30 990 admin' "$_rmt_g[hostname] $_rmt_g[port] $_rmt_g[user]"
_rmt_resolve pub ftp
t_eq 'resolve ftp: explicit Port, no User means anonymous' '192.0.2.31 2121 ' "$_rmt_g[hostname] $_rmt_g[port] $_rmt_g[user]"
_rmt_resolve odd ftp
t_eq 'resolve ftp: no Port means 21' 21 "$_rmt_g[port]"

_rmt_resolve plain telnet
t_eq 'resolve telnet: HostName / Port / User' '10.0.0.10 2323 admin' "$_rmt_g[hostname] $_rmt_g[port] $_rmt_g[user]"
_rmt_resolve old-router telnet
t_eq 'resolve telnet: no Port means 23, no User means empty' '10.0.0.9 23 ' "$_rmt_g[hostname] $_rmt_g[port] $_rmt_g[user]"
# Local user from id -un: containers and CI often lack $USER
local me=$(id -un)
print -rl -- 'Host explicit' ' HostName 192.0.2.1' ' Port 22' " User $me" >> $REMOTE_TELNET_CONFIG
_rmt_resolve explicit telnet
t_eq 'resolve telnet: keep an explicit Port 22 and a User equal to the local user' "22 $me" "$_rmt_g[port] $_rmt_g[user]"
mkdir -p "$HOME/.ssh/with space"
print -r -- 'Host quoted-include' > "$HOME/.ssh/with space/extra"
print -r -- 'Include "with space/*" # comment' > "$HOME/.ssh/quoted"
t_eq 'config_files: quoted Include path' "$HOME/.ssh/quoted"$'\n'"$HOME/.ssh/with space/extra" "$(_rmt_config_files "$HOME/.ssh/quoted")"

# ── net-backup device selection ──────────────
local -a reply
# ssh -G would read the real ~/.ssh/config, so ssh devices resolve to samples; telnet devices resolve for real
functions[_rmt_resolve_real]=$functions[_rmt_resolve]
_rmt_resolve() {
    [[ $2 == telnet ]] && { _rmt_resolve_real "$@"; return; }
    _rmt_g=( hostname ${${1:#sw-alias}:-core-sw} port 22 user u )
}
_netbak_hosts
t_eq 'netbak_hosts: keep every alias for groups and the picker' 'core-sw sw-alias old-router' "$reply"
t_eq 'netbak_info: group / description / protocol' "site-a${sep}core switch${sep}ssh" "$_netbak_info[core-sw]"
_netbak_unique "${reply[@]}"
t_eq 'netbak_unique: aliases of the same destination count once' 'core-sw old-router' "$reply"
print -rl -- 'Host router1 router2' '    User admin' 'Host router3' '    HostName router1' '    User admin' >> $REMOTE_TELNET_CONFIG
_netbak_hosts
_netbak_unique "${reply[@]}"
t_eq 'netbak_unique: one Host line without HostName keeps each target; same HostName is deduplicated' 'core-sw old-router router1 router2' "$reply"

# Aliases of one device in different groups: a group filter must not miss it because the other alias comes first.
cat >> $REMOTE_TELNET_CONFIG <<'EOF'
Host group-a
    HostName 192.0.2.10
    #_Tags network
    #_Group A
Host group-b
    HostName 192.0.2.10
    #_Tags network
    #_Group B
EOF
functions[_netbak_fetch_real]=$functions[_netbak_fetch]
local -a fetched
_netbak_fetch() { fetched+=( "$1" ); return 0; }
net-backup @B >/dev/null 2>&1
t_eq 'net-backup: the second group alias can still be selected' 0 $?
t_eq 'net-backup: selecting group B uses its alias' group-b "$fetched"
fetched=()
net-backup @A @B >/dev/null 2>&1
t_eq 'net-backup: one destination across groups is fetched once' group-a "$fetched"
fetched=()
net-backup @B @A >/dev/null 2>&1
t_eq 'net-backup: deduplication keeps the selection order' group-b "$fetched"
fetched=()
net-backup group-b @A group-b >/dev/null 2>&1
t_eq 'net-backup: aliases mixed with groups are deduplicated by destination' group-b "$fetched"
fetched=()
net-backup router1 router2 >/dev/null 2>&1
t_eq 'net-backup: different destinations are backed up separately' 'router1 router2' "$fetched"
fetched=()
hash fzf=${commands[true]:-/bin/true}   # the fzf check looks at commands; the function below does the picking
fzf() { command cat > "$tmp/netbak-picker"; print -rl -- group-a group-b; }
net-backup >/dev/null 2>&1
t_eq 'net-backup: picking one destination twice fetches once' group-a "$fetched"
t_eq 'net-backup: the picker list keeps the group B alias' 1 "$(command grep -c '^group-b' "$tmp/netbak-picker")"
unfunction fzf
functions[_netbak_fetch]=$functions[_netbak_fetch_real]
unfunction _netbak_fetch_real

# ── net-backup files and permissions ─────────
mkdir -p $tmp/fakedir
local real_dir=$ZSH_REMOTE_DIR
ZSH_REMOTE_DIR=$tmp/fakedir
print -r -- $'#!/bin/sh\nprintf "hostname sw\\nend\\n"' > $ZSH_REMOTE_DIR/net-backup.exp
chmod +x $ZSH_REMOTE_DIR/net-backup.exp
# The keychain differs per system (security / secret-tool), so replace the read function
functions[_rmt_secret_real]=$functions[_rmt_secret]
_rmt_secret() { REPLY=secret }
NET_BACKUP_DIR=$tmp/bak net-backup core-sw >/dev/null 2>&1
t_eq 'net-backup: succeeds' 0 $?
local -a bak=( $tmp/bak/core-sw/*.txt(N) )
t_eq 'net-backup: writes one backup file' 1 $#bak
t_eq 'net-backup: file is owner-only' 600 "$(_rmt_perms $bak[1])"
t_eq 'net-backup: directory is owner-only' 700 "$(_rmt_perms $tmp/bak/core-sw)"
mkdir -p $tmp/fixed-date
print -r -- $'#!/bin/sh\necho 20260101-000000' > $tmp/fixed-date/date
chmod +x $tmp/fixed-date/date
PATH=$tmp/fixed-date:$PATH NET_BACKUP_DIR=$tmp/same-second net-backup core-sw >/dev/null 2>&1
PATH=$tmp/fixed-date:$PATH NET_BACKUP_DIR=$tmp/same-second net-backup core-sw >/dev/null 2>&1
t_eq 'net-backup: a second backup in the same second succeeds' 0 $?
bak=( $tmp/same-second/core-sw/*.txt(N) )
t_eq 'net-backup: same-second backups get different files' 2 $#bak
print -r -- $'#!/bin/sh\nprintf "hostname sw\\ntruncated\\n"' > $ZSH_REMOTE_DIR/net-backup.exp
NET_BACKUP_DIR=$tmp/incomplete net-backup core-sw >$tmp/incomplete-result 2>&1
t_eq 'net-backup: an incomplete config fails' 1 $?
bak=( $tmp/incomplete/core-sw/*.txt(N) )
t_eq 'net-backup: an incomplete config is not published' 0 $#bak
bak=( $tmp/incomplete/core-sw/*.incomplete(N) )
t_eq 'net-backup: the incomplete config is kept for inspection' 1 $#bak
t_eq 'net-backup: the summary counts it as incomplete' 1 "$(command grep -c 'incomplete 1' $tmp/incomplete-result)"
print -r -- $'#!/bin/sh\nprintf "partial\\n"\nexit 1' > $ZSH_REMOTE_DIR/net-backup.exp
NET_BACKUP_DIR=$tmp/failed net-backup core-sw >/dev/null 2>&1
t_eq 'net-backup: a failed capture returns nonzero' 1 $?
bak=( $tmp/failed/core-sw/*(N) )
t_eq 'net-backup: a failed capture removes the temporary file' 0 $#bak
NET_BACKUP_DIR=$tmp/invalid net-backup ../escape >/dev/null 2>&1
t_eq 'net-backup: rejects a device name that is a path' 1 $?
# An existing backup with the same name is not overwritten, and the capture is kept
print -r -- $'#!/bin/sh\nprintf "hostname sw\\nend\\n"' > $ZSH_REMOTE_DIR/net-backup.exp
_rmt_private_new() { REPLY=$tmp/collide/core-sw/fixed.part; : > $REPLY; }
mkdir -p $tmp/collide/core-sw
print -r -- old > $tmp/collide/core-sw/fixed.txt
NET_BACKUP_DIR=$tmp/collide net-backup core-sw >/dev/null 2>&1
t_eq 'net-backup: fails when the backup name exists' 1 $?
t_eq 'net-backup: does not overwrite the existing backup' old "$(<$tmp/collide/core-sw/fixed.txt)"
t_eq 'net-backup: keeps the capture when publishing fails' end "$(command tail -n1 $tmp/collide/core-sw/fixed.part)"
unfunction _rmt_private_new
source $here/util.zsh
ZSH_REMOTE_DIR=$real_dir
functions[_rmt_secret]=$functions[_rmt_secret_real]
unfunction _rmt_secret_real
functions[_rmt_resolve]=$functions[_rmt_resolve_real]
unfunction _rmt_resolve_real


print -r -- "$passed passed"; (( failed )) && print -r -- "$failed failed"
(( failed == 0 ))
