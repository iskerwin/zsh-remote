# AGENTS.md

zsh-remote 是 zsh 插件（远端 `iskerwin/zsh-remote`）：ssh / sftp / telnet / ftp 主机选择器、`ssh-ag`、`net-backup`。dotfiles 在 `.chezmoiexternal.toml` 里把它锁定到一个提交，由 `.zshrc` 的 `plug` 加载。README.md 是给人看的说明，本文件写给 agent：改动前 MUST 先读。

本文的 MUST、MUST NOT、SHOULD、SHOULD NOT、MAY 按 RFC 2119 / RFC 8174 解释，仅在全大写时有此含义。

## 结构与约定

- 文件分工写在 `zsh-remote.plugin.zsh` 开头：每种协议一个 `<kind>.zsh`，共用 `lib.zsh`（解析配置、钥匙串、外观）、`picker.zsh`（fzf 选择器和 `\<Tab>` 补全）、`util.zsh`（帮助、tinge 检查）。新协议 MUST 按那里写的步骤加。
- 界面和帮助 MUST 用英文；每个命令 MUST 响应 `-h` / `--help`，并 MUST 自己注册补全（含 `-h`）。
- 插件 MUST NOT 调用 dotfiles 里的函数；外观用 zsh-ui 的 `_ui_*`，`ui-fallback.zsh` 是 zsh-ui 的原样副本，MUST NOT 在这里改，zsh-ui 发版后 MUST 整份覆盖（CI 的 `ui-fallback` 任务会和 zsh-ui 最新 tag 比对）。
- fzf 最低 0.58，更新的选项 MUST 用 `_ui_fzf_since` 按版本加。
- 加载顺序不同也 MUST 能用：fzf 自带的 `_fzf_complete_ssh` / `_telnet` 由 `_rmt_fzf_claim` 在第一次显示提示符前收回；以后再有同名冲突，MUST 用同样的方式处理，MUST NOT 要求用户调整加载顺序。

## 和 tinge 的分工

- `ssh-to` 只把主机的 `#_Tags` 用 `--tags` 交给 tinge，`telnet-to` 直接运行 `tinge telnet`；用哪套规则由 tinge 规则集的 `match` 决定。MUST NOT 在本仓库判断规则集。
- `_rmt_tinge` 检查 tinge 版本（现在要求 0.3.0 起，因为用了 `--tags`），太旧时提示一次并退回普通命令。用到 tinge 的新选项时 MUST 提高这个门槛，并改 README「Requirements」里的版本号。
- `lib.zsh` 的 `_rmt_device_pat` 只用于选择器的设备图标和 `net-backup` 找设备。新增一类网络设备时，MUST 同时改它和 tinge `network.yml` 的 `match`，两处的词 SHOULD 保持一致。

## 测试

- 改完 MUST 通过 `zsh -f tests.zsh && zsh -f tests-lib.zsh`。测试用假的 `ssh`、`lftp`、`fzf`、`tinge` 和钥匙串命令，MUST NOT 访问网络、真实设备或凭据。
- 新行为 MUST 配测试；修 bug MUST 配一个修复前会失败的测试，并在旧代码上确认它失败。
- 交互行为（`\<Tab>` 补全、选择器）只在测试里跑通不够：发版后 SHOULD 在新开的交互 shell 里确认，例如用 `whence -f`、`$functions[...]` 看实际生效的函数。

## 文档

同一个 commit 里 MUST 同步更新：README 的命令表、「Requirements」、「Configuration」、「Host files」；命令的 `-h` 帮助；`zsh-remote.plugin.zsh` 开头的文件表。改名的命令 MUST 搜索全仓库和 dotfiles 里的引用（缩写、README、AGENTS.md）。

改了什么要一起看哪些文件，写在 `.impact`（格式见 `impact-check -h`，`impact-check` 由 dotfiles 安装）。结束前和提交时会自动列出漏掉的项（Stop hook、`.githooks/commit-msg`；clone 后执行一次 `git config core.hooksPath .githooks`），MUST 逐项更新，确实不需要时说明原因，提交时写 `Docs-checked: <原因>`。发现漏掉的关联 MUST 补进 `.impact` 并跑 `impact-check --lint`。

## 发布

1. 提交推送到 `main`，打 tag：`git tag -a vX.Y.Z -m "zsh-remote X.Y.Z" && git push origin vX.Y.Z`。改名、删除命令或提高依赖版本升第二位，其余升第三位。
2. 算 sha256 MUST 走代理：`zsh -ic 'net-with-proxy curl -sL https://github.com/iskerwin/zsh-remote/archive/refs/tags/vX.Y.Z.tar.gz' </dev/null | shasum -a 256`，再改 `~/Developer/homebrew-tap/Formula/zsh-remote.rb` 的 `url`、`sha256`（caveats 里的工具列表变了也改），`brew style` 后提交推送。
3. 更新 dotfiles：按 dotfiles AGENTS.md「改动流程与检查」里「自有插件或 tinge 发版」一行做（改 `.chezmoiexternal.toml` 里的提交、`chezmoi apply`、新开 shell 验证、`cz-check`、再提交）。

## 提交

MUST 直接提交到 `main`；提交说明用英文，第一行写改了什么，正文写原因。
