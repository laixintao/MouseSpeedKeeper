# 配置、使用与排障

## Homebrew 安装与首次配置（推荐）

需要 macOS、Homebrew 和 Xcode Command Line Tools（`swiftc`）。缺少编译器时运行 `xcode-select --install` 并完成系统安装界面。v0.1.0 使用源码 formula 打包，由本机编译 Swift，不提供 bottles。已测试 macOS 15；其他硬件不能据此视为已验证。

```sh
brew install laixintao/tap/mouse-speed-keeper
```

安装命令为 `mouse-speed`；安装只安装程序，不写用户配置、不自动启动服务、不修改硬件 DPI。首次使用：

```sh
config_dir="$HOME/Library/Application Support/MouseSpeedKeeper"
mkdir -p "$config_dir"
mouse-speed probe
if [ ! -e "$config_dir/config.json" ]; then
  mouse-speed capture "$config_dir/config.json"
fi
nano "$config_dir/config.json"
```

`capture` 会覆盖指定文件，所以上面仅在配置不存在时执行。需要恰好探测到一只支持的鼠标；失败时先排障，不要继续启动服务。只改目标 `dpi`，保留捕获的 `identity`。确认配置有效后：

```sh
brew services start mouse-speed-keeper
```

这一步才启动后台恢复，并可能改变硬件 DPI。服务标签是 `homebrew.mxcl.mouse-speed-keeper`，以当前用户 LaunchAgent 运行，仅在用户登录后生效；**不要使用 sudo 运行 brew services**。

### 旧脚本安装迁移

旧标签为 `local.mouse-speed-keeper`。先安装 Homebrew formula，再按 README 的“从旧脚本安装迁移”命令块操作：停止已载入的旧服务（`launchctl bootout`），仅当 `~/Library/LaunchAgents/local.mouse-speed-keeper.plist` 存在时将它改名为 `local.mouse-speed-keeper.plist.disabled`，确认旧服务不再运行后才执行 `brew services start mouse-speed-keeper`。若备份已存在，先整理备份，不要覆盖。

迁移保留原 `config.json` 和日志，不重新 capture，也不运行旧安装脚本。若配置缺失，先完成首次配置。旧二进制可以保留，但不要再运行它的 watch；也要退出手动启动的 watch。**任何时刻只运行一个 keeper。**

## 修改为 2200 DPI（Homebrew 已安装）

编辑实际生效的配置：

```sh
nano "$HOME/Library/Application Support/MouseSpeedKeeper/config.json"
```

格式示例（`identity` 为虚构值，必须保留自己的设备 ID）：

```json
{
  "dpi": 2200,
  "identity": "1234abcd"
}
```

只改 `dpi`，不改 `identity`。其他鼠标必须通过 probe / capture 获取自己的 Unit ID。`dpi` 必须是整数；程序允许 100–65535，但实际范围和步进取决于硬件，写入后会读回验证。

**watch 只在启动时读取一次配置，不会自动重载 JSON。** 保存后重启服务：

```sh
brew services restart mouse-speed-keeper
```

等待一轮检查后，只读确认实际硬件 DPI：

```sh
mouse-speed probe
```

Homebrew 不使用仓库的 `mouse-config.json`，无需为 Homebrew 升级把配置同步回仓库。

## CLI

| 命令 | 行为 |
| --- | --- |
| `mouse-speed probe` | 查询设备 ID、插槽和 DPI，不修改 DPI |
| `mouse-speed capture CONFIG.json` | 读取当前 DPI 并写出配置（覆盖同名文件）；必须恰好探测到一只支持设备 |
| `mouse-speed apply CONFIG.json` | 强制设置 DPI 并读回验证，实际修改硬件 |
| `mouse-speed watch CONFIG.json` | 持续恢复配置值，只在 DPI 不同时写入 |

无参数等同 probe。当前没有 help/version 子命令或 `--help` / `--version` 选项。后台运行时用另一份配置 apply 会被后台恢复；修改目标值应编辑生效配置并重启，不要同时启动另一个 watch。

后台每轮完成后休息 5 秒，离线探测耗时意味着实际周期更长，恢复可能需十几秒。每轮重新枚举设备；离线时等待，并不保证产生错误日志。

## 路径、状态、日志

| 内容 | Homebrew 安装路径 |
| --- | --- |
| LaunchAgent 标签 | `homebrew.mxcl.mouse-speed-keeper` |
| LaunchAgent plist | `~/Library/LaunchAgents/homebrew.mxcl.mouse-speed-keeper.plist` |
| 命令入口 | `$(brew --prefix)/bin/mouse-speed` |
| 生效配置 | `~/Library/Application Support/MouseSpeedKeeper/config.json` |
| 运行日志 | `~/Library/Application Support/MouseSpeedKeeper/agent.log` |
| 错误日志 | `~/Library/Application Support/MouseSpeedKeeper/error.log` |

配置和日志与旧脚本安装保持同一路径。Homebrew 的二进制由 Homebrew 管理，不再使用配置目录中可能残留的旧程序。

```sh
brew services list
launchctl print "gui/$(id -u)/homebrew.mxcl.mouse-speed-keeper"
command -v mouse-speed
```

查看最近日志或实时跟踪（服务首次运行前，日志可能尚未创建）：

```sh
tail -n 30 "$HOME/Library/Application Support/MouseSpeedKeeper/agent.log" \
  "$HOME/Library/Application Support/MouseSpeedKeeper/error.log"
```

```sh
tail -f "$HOME/Library/Application Support/MouseSpeedKeeper/agent.log" \
  "$HOME/Library/Application Support/MouseSpeedKeeper/error.log"
```

DPI 未变化时不会持续输出成功日志；没有新日志不代表服务停止。不要把日志当作完整的硬件状态记录；使用 probe 读回确认。原手动安装脚本未配置日志轮转。

## Homebrew 停止、启动、升级与卸载

停止并取消用户登录自动启动，或重新启用：

```sh
brew services stop mouse-speed-keeper
# 需要恢复服务时：
brew services start mouse-speed-keeper
```

升级后显式重启，让后台进程使用新程序：

```sh
brew upgrade mouse-speed-keeper
brew services restart mouse-speed-keeper
```

卸载前先停止：

```sh
brew services stop mouse-speed-keeper
brew uninstall mouse-speed-keeper
```

配置和日志保留，硬件 DPI 不还原；不会操作 Logitech 服务。恢复此前手动禁用的 Options+ 的说明见 README。不要使用旧 `scripts/uninstall.sh` 来停用 Homebrew 服务，它只管理旧标签。

## 替代方案：源码手动安装与维护

原脚本保持不变，与 Homebrew 服务二选一。切换到手动安装前先执行 `brew services stop mouse-speed-keeper`，确认 Homebrew 服务已停止；不要同时运行两个 keeper。

需要 Command Line Tools 和安装脚本调用的 `/usr/bin/python3`。在仓库根目录执行 README 的手动 build、probe、capture、install 流程。想指定 2200 DPI，可在 capture 后编辑仓库 `mouse-config.json`，无须预先用 Options+ 调整。

**手动脚本与 Homebrew 安装语义不同：** `scripts/install.sh` 会停止旧标签服务，覆盖配置目录的二进制和配置，重新启动并应用仓库 DPI。仓库 `mouse-config.json` 和生效的 `config.json` 是两份独立文件，不是符号链接。已有用户重新安装或源码升级前，先在仓库根目录同步：

```sh
cp "$HOME/Library/Application Support/MouseSpeedKeeper/config.json" mouse-config.json
bash scripts/build.sh
bash scripts/install.sh
```

不要无意用 capture 覆盖想保留的目标 DPI。手动安装的路径为：

- 程序：`~/Library/Application Support/MouseSpeedKeeper/mouse-speed`
- LaunchAgent：`~/Library/LaunchAgents/local.mouse-speed-keeper.plist`
- 标签：`local.mouse-speed-keeper`
- 配置与日志：与上表相同。

仅对手动安装：编辑生效 `config.json` 后重启并读回：

```sh
launchctl kickstart -k "gui/$(id -u)/local.mouse-speed-keeper"
"$HOME/Library/Application Support/MouseSpeedKeeper/mouse-speed" probe
```

暂时停止（保留 plist，下次登录仍可启动），或重新载入：

```sh
launchctl bootout "gui/$(id -u)/local.mouse-speed-keeper"
# 需要恢复服务时：
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.mouse-speed-keeper.plist"
```

永久移除旧登录项，在仓库执行 `bash scripts/uninstall.sh`；保留程序、配置和日志，不还原硬件 DPI。若迁移到 Homebrew，应使用 README 的迁移流程停用并保存旧 plist，而不是再运行安装脚本。

## 排障

- **配置没生效**：确认改的是生效目录中的 `config.json`。Homebrew 安装执行 `brew services restart mouse-speed-keeper`；手动安装使用旧标签的 kickstart。等待一轮后用对应二进制 probe 读回。
- **找不到鼠标**：检查电源、唤醒、接收器连接和型号兼容性。历史验证为 MX Anywhere 3S + Logi Bolt；其他型号和蓝牙直连尚未验证。
- **Cannot open HID device**：检查系统设置 → 隐私与安全性 → 输入监控，必要时允许实际运行的 `mouse-speed`，注销再登录。Homebrew 安装不要误选残留的旧二进制。工具不绕过系统权限。
- **DPI 来回变化**：确认没有同时运行新旧 LaunchAgent 或手动 watch。Options+ 也可能设置不同值；工具不会自动卸载或停止 Logitech 服务，不替代按键映射等功能。
- **Invalid configuration**：检查 JSON、整数 `dpi` 和 8 字符 `identity`。需要重新捕获时先备份原配置，再 capture 到不同文件，核对后再替换；不要直接覆盖原目标值。
- **service not found**：确认当前登录会话、安装方式和服务标签。Homebrew 安装先准备有效配置，再用 `brew services start mouse-speed-keeper` 启动；不要因查错旧标签而重跑手动安装。
- **启动失败 / 日志路径不存在**：检查配置目录是否已创建、配置是否存在且有效，并检查用户目录写入权限；安装本身不会创建用户配置。

## 验证与副作用边界

以下在仓库根目录执行，只检查构建与 shell 语法，不启动服务、不写硬件 DPI：

```sh
bash scripts/build.sh
bash -n scripts/build.sh scripts/install.sh scripts/uninstall.sh
```

只读硬件探测使用 `mouse-speed probe`（Homebrew）或 `.build/mouse-speed probe`（源码构建）。编译通过不能证明其他硬件兼容。

**不要把硬件集成测试当作安装或升级检查自动执行。** `python3 scripts/check-recovery.py` 会实际提高 DPI 100，再等待后台恢复。它仍使用仓库 `.build/mouse-speed` 和 `mouse-config.json`，并非 Homebrew 安装的一部分。仅在明确需要改变鼠标 DPI 做测试时运行；运行前须确认：

- 只有一个后台 keeper，鼠标在线且只有一只支持设备。
- 已构建仓库二进制，并同步生效配置到仓库。
- probe 读回的初始 DPI 与配置一致，DPI + 100 在硬件支持范围内。

脚本 finally 尝试恢复的是仓库配置值，不是临时捕获的硬件初始值。强制杀进程、设备断连等情况不保证恢复。此检查不能代替真实重启、拔插或睡眠唤醒验证。

README 的 2026-10-20 测试是原项目历史记录，不是 v0.1.0 Homebrew 发布的新硬件测试。本次文档更新不运行该测试，不宣称新增硬件支持或 Swift 功能。
