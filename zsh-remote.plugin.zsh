# zsh-remote — SSH, SFTP, Telnet and FTP hosts in one fzf picker each, ssh-agent management,
# and network device config backups. One file per protocol, all on a shared picker:
#
#   file         hosts from                          picker        opens with
#   ssh.zsh      ~/.ssh/config (+ Includes)          ssh-pick      ssh-ct     (tinge, ssh fallback)
#   sftp.zsh     ~/.ssh/config (+ Includes)          sftp-pick     sftp-open  (lftp over SFTP)
#   telnet.zsh   ~/.ssh/telnet_config                telnet-pick   telnet-ct  (tinge, telnet fallback)
#   ftp.zsh      ~/.ssh/ftp_config                   ftp-pick      ftp-open   (lftp over FTP / FTPS)
#   agent.zsh    ssh-agent keys                      ssh-ag
#   netbak.zsh   network devices in the configs      net-backup (Expect: net-backup.exp)
#
# lib.zsh: config parsing, keychain, look (also used by helper and net-backup); picker.zsh: the shared
# fzf picker. The open commands work without fzf; the pickers say so when it is missing.
# Load after compinit: the files register their completions with compdef.
#
# A new protocol: a <kind>.zsh that calls _rmt_kind and defines <kind>-pick and its open command,
# plus its config file and default port in lib.zsh (_rmt_cfg_file / _rmt_kind_file / _rmt_default_port).

export ZSH_REMOTE_DIR=${${(%):-%x}:A:h}
() {
    local f
    source $ZSH_REMOTE_DIR/lib.zsh
    for f in picker ssh sftp telnet ftp agent netbak doctor; do source $ZSH_REMOTE_DIR/$f.zsh; done
}
