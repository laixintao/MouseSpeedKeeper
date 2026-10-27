# Mouse Speed Keeper

macOS 上的轻量 Logitech DPI 恢复工具，无界面，不调用 Options+。使用系统 IOKit 和 HID++ 2.0 的 Adjustable DPI（0x2201）功能，不安装驱动或第三方运行时依赖。

只保存并恢复选定鼠标的硬件 DPI；不修改 macOS 全局鼠标速度、触控板、按键、滚轮或键盘。以鼠标自身 Unit ID 匹配设备，避免接收器插槽变动后改错设备。若手动修改了 macOS 的指针速度，手感仍会变化。

## 推荐：通过 Homebrew 安装

需要 macOS、Homebrew 和 Xcode Command Line Tools（`swiftc`）。缺少编译工具时先运行 `xcode-select --install`，完成系统安装界面后再继续。

**v0.1.0 是源码 formula 打包，不提供 bottles（预编译包）**：Homebrew 使用 Command Line Tools 编译 Swift 源码，安装命令为：

```sh
brew install laixintao/tap/mouse-speed-keeper
```

安装后的命令是 `mouse-speed`。如果新版 Homebrew 提示 untrusted tap/formula，先检查 tap 中的 `Formula/mouse-speed-keeper.rb`，确认信任后执行 `brew trust --formula laixintao/tap/mouse-speed-keeper`，再重试安装（旧版 Homebrew 可能没有 trust 命令）。

**安装只安装程序，不写用户配置，不自动启动服务，也不修改 DPI。** 已通过旧脚本安装的用户请跳到下方迁移步骤，不要同时启动两个 keeper。

### 首次配置与启动

接通并唤醒鼠标，然后执行：

```sh
config_dir="$HOME/Library/Application Support/MouseSpeedKeeper"
mkdir -p "$config_dir"
mouse-speed probe
# capture 会覆盖目标文件；已有配置时必须跳过。
if [ ! -e "$config_dir/config.json" ]; then
  mouse-speed capture "$config_dir/config.json"
fi
nano "$config_dir/config.json"
```

`probe` 只读硬件；`capture` 仅在检测到一只支持的鼠标时保存当前 DPI 和 Unit ID。确认 capture 成功、配置存在且有效后，只修改 `dpi` 为目标整数（如 `2200`），保留自己的 `identity`；不要复制示例设备 ID。保存后启动：

```sh
brew services start mouse-speed-keeper
```

启动服务会按配置恢复硬件 DPI。服务是当前用户登录后运行的 LaunchAgent，标签为 `homebrew.mxcl.mouse-speed-keeper`，**不要使用 sudo 运行 brew services**。未登录时不运行。配置和日志仍位于 `~/Library/Application Support/MouseSpeedKeeper/`。

### 从旧脚本安装迁移

先执行上面的 `brew install`；保留现有 `config.json`，不重新 capture、不运行 `scripts/install.sh`。下面的命令先停止旧服务，并仅在旧 plist 存在时将它移到 `.plist.disabled`，避免下次登录启动两个 keeper：

```sh
(
  set -e
  legacy="$HOME/Library/LaunchAgents/local.mouse-speed-keeper.plist"
  if launchctl print "gui/$(id -u)/local.mouse-speed-keeper" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/local.mouse-speed-keeper"
  fi
  if [ -e "$legacy" ]; then
    if [ -e "$legacy.disabled" ]; then
      printf '%s\n' '已有 .plist.disabled，请先整理备份后重试；尚未启动 Homebrew 服务。' >&2
      exit 1
    fi
    mv "$legacy" "$legacy.disabled"
  fi
  if launchctl print "gui/$(id -u)/local.mouse-speed-keeper" >/dev/null 2>&1; then
    printf '%s\n' '旧服务仍在运行，停止迁移。' >&2
    exit 1
  fi
  test -f "$HOME/Library/Application Support/MouseSpeedKeeper/config.json"
  brew services start mouse-speed-keeper
)
```

若任何步骤失败，先排除问题，不要另行启动新服务。也应退出手动启动的 `mouse-speed watch`。旧二进制可留在配置目录，但不要再启动；Homebrew 使用自己安装的二进制。迁移不删除配置与日志。

### 修改配置、升级与卸载

**watch 只在启动时读取配置，编辑后必须重启：**

```sh
nano "$HOME/Library/Application Support/MouseSpeedKeeper/config.json"
brew services restart mouse-speed-keeper
# 等待一轮检查后，只读确认实际硬件 DPI：
mouse-speed probe
```

升级后重启，让后台进程使用新程序：

```sh
brew upgrade mouse-speed-keeper
brew services restart mouse-speed-keeper
```

停用或卸载（先停止服务，再卸载）：

```sh
brew services stop mouse-speed-keeper
brew uninstall mouse-speed-keeper
```

配置和日志保留；鼠标保持停用时的 DPI。不会更改 Logitech 原有服务。

## 状态与排障

```sh
brew services list
launchctl print "gui/$(id -u)/homebrew.mxcl.mouse-speed-keeper"
tail -n 30 "$HOME/Library/Application Support/MouseSpeedKeeper/agent.log" \
  "$HOME/Library/Application Support/MouseSpeedKeeper/error.log"
```

后台每轮检查后休息 5 秒；离线设备探测有超时，实际恢复可能需十几秒。每轮重新枚举设备，仅在 DPI 与保存值不同时写入；鼠标离线时等待下次检查。没有新日志不代表服务停止。

如果提示无法访问 HID，请检查系统设置 → 隐私与安全性 → 输入监控，必要时允许实际运行的 `mouse-speed`，随后注销再登录。权限由 macOS 管理，工具不会绕过权限。更多配置格式、CLI 和排障见 `docs/configuration.md`。

## 替代方案：从源码手动安装

**与 Homebrew 服务二选一，不要混用安装方式。** 若已运行 Homebrew 服务，先执行 `brew services stop mouse-speed-keeper`。原脚本保持不变；与 Homebrew 不同，手动安装脚本会覆盖安装配置并立即启动旧标签的服务。

在本仓库根目录执行（例如先 `cd ~/Programs/MouseSpeedKeeper`），需要 Command Line Tools 和安装脚本使用的 `/usr/bin/python3`：

```sh
bash scripts/build.sh
.build/mouse-speed probe
if [ ! -e mouse-config.json ]; then
  .build/mouse-speed capture mouse-config.json
fi
nano mouse-config.json
# 确认配置存在且目标 DPI 正确后安装；这一步会启动服务并修改硬件 DPI。
bash scripts/install.sh
```

已有安装的用户在重新安装前，先把 `~/Library/Application Support/MouseSpeedKeeper/config.json` 同步到仓库的 `mouse-config.json`，避免覆盖目标 DPI。这是两份独立文件。脚本把程序和配置复制到该用户目录，服务标签为 `local.mouse-speed-keeper`。

手动安装的配置编辑后使用 `launchctl kickstart -k "gui/$(id -u)/local.mouse-speed-keeper"` 重启；停用使用 `bash scripts/uninstall.sh`，保留程序、配置和日志。不要用这些旧服务命令管理 Homebrew 服务。

## 适用范围与历史验证

已测试环境为 macOS 15；历史实机目标为 MX Anywhere 3S，经 Logi Bolt USB 接收器连接。其他硬件、其他型号和蓝牙直连尚未验证；真实重启、接收器拔插、睡眠唤醒也不能仅凭编译或轮询逻辑视为已通过。设备必须提供 0x2201 和 Unit ID，不支持时报告错误，不猜测配置。

程序不依赖 Options+，也不会自动卸载或停止 Logitech 服务。如果 Options+ 同时运行并设置不同 DPI，两者可能反复覆盖。按键映射等功能不由此工具替代。

**历史记录（不是本次 v0.1.0 Homebrew 打包测试）：** 2026-10-20，Options+ 界面、配置后台及更新进程均停止后，将 DPI 从 2000 改为 2100，旧 LaunchAgent 自动恢复至 2000，并读回确认。此前退出原后台时也曾观察到 DPI 从 2000 重置为 1000，独立工具恢复至 2000。

若要恢复此前手动禁用的 Options+，先停用本工具；以下只适用于对应 Logitech plist 仍存在的情况（其中系统服务操作需要管理员权限，并非本工具的安装要求）：

```sh
launchctl enable "gui/$(id -u)/com.logi.cp-dev-mgr"
launchctl bootstrap "gui/$(id -u)" /Library/LaunchAgents/com.logi.optionsplus.plist
sudo launchctl enable system/com.logi.optionsplus.updater
sudo launchctl bootstrap system /Library/LaunchDaemons/com.logi.optionsplus.updater.plist
```

**硬件测试会改变 DPI，不属于安装步骤。** `scripts/check-recovery.py` 会短暂增加 DPI 100；finally 仅尝试恢复仓库配置值，断连或强制终止不保证恢复。执行前须阅读 `docs/configuration.md` 的验证边界。本次文档更新不执行硬件测试。

## 仓库与文件

本仓库从原 `logi-options-clone` 项目复制源码和脚本，原目录保持不变；历史迁移时构建产物与已安装二进制的 SHA-256 一致，后续维护无须依赖原目录。

- `Sources/MouseSpeed.swift`：完整 Swift 源码。
- `scripts/build.sh`：编译程序，产物及模块缓存在 `.build/`。
- `scripts/install.sh`：手动安装，复制程序和配置，生成并启动旧 LaunchAgent。
- `scripts/uninstall.sh`：停用并删除旧 LaunchAgent，保留程序、配置与日志。
- `scripts/check-recovery.py`：有硬件副作用的自动恢复测试。
- `config.example.json`：配置格式示例；不要照抄设备 ID。
- `mouse-config.json`：手动安装使用的本机配置，已被 Git 忽略。
- `docs/configuration.md`：配置、运行路径、CLI、排障与验证说明。
