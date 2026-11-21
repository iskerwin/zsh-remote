# zsh-remote

Your SSH, SFTP, Telnet and FTP hosts in fzf pickers, read from ssh-config-style files, with a live preview, a connection test and one-key open. Plus an ssh-agent key manager and network device config backups.

| Command | What it does |
|---|---|
| `ssh-pick [query]` | Pick a host from `~/.ssh/config` (and its `Include`s), connect with `ssh-ct` |
| `ssh-ct <alias> [ssh options]` | ssh through [ChromaTerm](https://github.com/hSaria/ChromaTerm) highlighting, plain ssh if it is missing |
| `sftp-pick` · `sftp-open <alias>` | Browse an SSH host's files over SFTP in lftp; `--tui` opens two panes in mc |
| `telnet-pick` · `telnet-ct <alias>` | Telnet devices from `~/.ssh/telnet_config` |
| `ftp-pick` · `ftp-open <alias>` | FTP / FTPS servers from `~/.ssh/ftp_config`, password in the keychain |
| `ssh-ag [status \| clear]` | Add and remove ssh-agent keys with fzf |
| `net-backup [alias\|@group...]` | Back up switch, router and firewall configs (Ruijie, Cisco, Huawei, H3C) over SSH or Telnet |

Every command answers `-h`. In a picker: `↵` open, `^T` test the connection, `^E` edit the config file, `^Y` copy the alias, `^O` two-pane browser (SFTP / FTP), `^A` add the host's keys to ssh-agent (SSH), `^/` toggle the preview. `ssh \<Tab>` and friends open the picker as completion.

## Requirements

- zsh 5.8+, [fzf](https://github.com/junegunn/fzf) 0.61+ for the pickers (the open commands work without it)
- Optional: `lftp` (SFTP / FTP), `mc` (two-pane `--tui`), ChromaTerm `ct` (highlighting), `expect` (`net-backup`), `secret-tool` on Linux (saved passwords)
- A [Nerd Font](https://www.nerdfonts.com/) for the host icons

Install [zsh-ui](https://github.com/iskerwin/zsh-ui) for the same btop-style look as your other tools; without it zsh-remote uses a plain built-in look.

## Install

**Homebrew**

```sh
brew install iskerwin/tap/zsh-remote
echo 'source "$(brew --prefix)/share/zsh-remote/zsh-remote.plugin.zsh"' >> ~/.zshrc
```

**[zap](https://github.com/zap-zsh/zap)**

```zsh
plug "iskerwin/zsh-remote"
```

**Manual**

```sh
git clone https://github.com/iskerwin/zsh-remote ~/.local/share/zsh-remote
echo 'source ~/.local/share/zsh-remote/zsh-remote.plugin.zsh' >> ~/.zshrc
```

Load it after `compinit`; the commands register their completions.

## Host files

All three files use ssh config syntax. Telnet and FTP hosts live in their own files, which you should **not** `Include` from `~/.ssh/config`, so ssh never sees them.

```sshconfig
Host core-sw
    HostName 10.0.0.1
    User admin
    #_Desc Core switch
    #_Tags ruijie, switch
    #_Group site-a
```

- `#_Desc`, `#_Tags`, `#_Group` show in the list and are searchable (`@site-a`, `#switch`).
- In `~/.ssh/ftp_config`, `#_Proto ftps` means implicit TLS (port 990); without it, plain FTP that lftp upgrades to TLS when offered. No `User` means anonymous.
- Telnet and FTP default to ports 23 and 21 when there is no `Port`.

## Passwords

FTP and net-backup passwords are kept in the macOS Keychain (`security`) or, on Linux, the Secret Service (`secret-tool`); without either, you are asked each time. They are never put in command arguments. `ftp-open --forget <alias>` and `net-backup --forget <alias>` delete a saved one.

## net-backup

Devices are the hosts whose alias or `#_Tags` contain ruijie, cisco, huawei, h3c, switch, router, firewall or network. The vendor is recognized from the prompt after login; paging is turned off and the running config saved to `~/Backups/network/<alias>/<alias>_<time>.txt` (owner-only). An incomplete capture is kept as `.incomplete` instead. The first backup of a device asks for its password; an enable / super password that differs is saved under `<alias>:enable`. New host keys are never accepted automatically: ssh to a device once first.

## Configuration

| Variable | Default |
|---|---|
| `REMOTE_SSH_CONFIG` | `~/.ssh/config` |
| `REMOTE_TELNET_CONFIG` | `~/.ssh/telnet_config` |
| `REMOTE_FTP_CONFIG` | `~/.ssh/ftp_config` |
| `REMOTE_CONNECT_TIMEOUT` | `3` seconds for `^T` |
| `REMOTE_PREVIEW_WIDTH` | `55` (% of the picker) |
| `REMOTE_CLIP` | first of `clip-copy`, `pbcopy`, `wl-copy`, `xclip`, `xsel` |
| `NET_BACKUP_DIR` | `~/Backups/network` |

## Development

```sh
zsh -f tests.zsh && zsh -f tests-lib.zsh
```

The tests use fake `ssh`, `lftp`, `fzf` and keychain commands, and drive the real Expect script against a fake device; nothing touches the network or real credentials.

## License

[MIT](LICENSE)
