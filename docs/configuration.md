# 配置、CLI 与验证

安装与服务管理以 [README](../README.md) 的 Homebrew 流程为准。只运行一个 keeper，不使用 sudo 启动服务。

## 配置文件

`~/Library/Application Support/MouseSpeedKeeper/config.json`：

```json
{
  "dpi": 2200,
  "identity": "1234abcd"
}
```

`identity` 是虚构示例；必须使用 `mouse-speed capture` 捕获的设备 Unit ID。捕获会覆盖目标文件，已有配置时应跳过，或捕获到另一文件核对。

`dpi` 必须为整数，程序允许 100–65535，实际支持范围和步进由硬件决定。写入后会读回验证。只修改 dpi，保持自己的 identity。

```sh
nano "$HOME/Library/Application Support/MouseSpeedKeeper/config.json"
```

```sh
brew services restart mouse-speed-keeper
```

watch 仅在启动时读取配置；编辑后必须重启。等待一轮检查后用 `mouse-speed probe` 验证实际硬件值，而不只是检查 JSON。

## CLI

| 命令 | 行为 |
| --- | --- |
| `mouse-speed probe` | 查询设备 ID、插槽和 DPI，不修改 DPI |
| `mouse-speed capture CONFIG.json` | 读取当前 DPI 并写配置，会覆盖同名文件；要求恰好一只支持设备 |
| `mouse-speed apply CONFIG.json` | 强制设置硬件 DPI，并读回验证 |
| `mouse-speed watch CONFIG.json` | 持续恢复配置值，只在当前 DPI 不同时写入 |

无参数等同 probe。当前没有 help/version 子命令或 `--help` / `--version` 选项。后台运行时使用另一份配置 apply 会被后台恢复。修改目标应编辑生效配置并重启服务。

后台每轮重新枚举设备，检查完成后休眠 5 秒。离线探测有超时，实际恢复可能需十几秒；离线时等待并不保证产生错误日志。

## 文件与服务

| 内容 | 路径或名称 |
| --- | --- |
| 服务标签 | `homebrew.mxcl.mouse-speed-keeper` |
| LaunchAgent | `~/Library/LaunchAgents/homebrew.mxcl.mouse-speed-keeper.plist` |
| 命令入口 | `$(brew --prefix)/bin/mouse-speed` |
| 服务执行路径 | `$(brew --prefix)/opt/mouse-speed-keeper/bin/mouse-speed` |
| 配置 | `~/Library/Application Support/MouseSpeedKeeper/config.json` |
| 运行日志 | `~/Library/Application Support/MouseSpeedKeeper/agent.log` |
| 错误日志 | `~/Library/Application Support/MouseSpeedKeeper/error.log` |

Homebrew 负责程序，配置与日志位于 Cellar 之外；升级或卸载不会覆盖/删除它们。首次启动前必须创建配置目录并准备有效配置。

```sh
brew services list
```

```sh
launchctl print "gui/$(id -u)/homebrew.mxcl.mouse-speed-keeper"
```

```sh
tail -f "$HOME/Library/Application Support/MouseSpeedKeeper/agent.log" \
  "$HOME/Library/Application Support/MouseSpeedKeeper/error.log"
```

日志首次启动前可能不存在。DPI 未变化时不输出新的成功日志；没有新日志不表示服务停止。目前没有配置日志轮转。

## 排障

- **配置未生效**：确认配置路径，重启 brew 服务，等待一轮，再用 probe 查询硬件。
- **找不到设备**：唤醒鼠标，检查电源、接收器和型号兼容性。新程序和其他构建都找不到时，不要据此断言安装失败。
- **Cannot open HID device**：检查输入监控权限，必要时允许 Homebrew 的实际二进制，注销再登录；工具不绕过权限。
- **DPI 来回变化**：排查多个 watch 或 Options+ 同时写入。工具不会自动停止或卸载 Logitech 服务。
- **Invalid configuration**：检查 JSON、整数 dpi 和 8 字符 identity。需要重新 capture 时先备份，捕获到另一文件核对，避免丢失目标值。
- **服务启动失败**：检查配置目录、有效 JSON 和写入权限；安装本身不创建用户配置。
- **untrusted formula**：确认配方可信后运行 `brew trust --formula laixintao/tap/mouse-speed-keeper`；该命令只适用于提供 trust 功能的新版 Homebrew。

## 验证与副作用边界

无硬件的包测试：

```sh
brew test laixintao/tap/mouse-speed-keeper
```

源码编译：

```sh
bash scripts/build.sh
```

只读探测：

```sh
mouse-speed probe
```

编译和无硬件测试不能证明鼠标兼容性，也不等于真实拔插、睡眠或重启测试。

### 可选：硬件恢复集成检查

`python3 scripts/check-recovery.py` 会实际提高 DPI 100，再等待后台恢复；不作为安装或升级的自动检查。它使用仓库 `.build/mouse-speed` 和 `mouse-config.json`，不是 Homebrew 安装的一部分。执行前必须确认：

1. 明确允许短暂改变 DPI，且只有一个后台 keeper。
2. 鼠标在线，恰好一只可探测的支持设备。
3. 已运行 build.sh，将生效配置复制到仓库 mouse-config.json，并用 probe 确认硬件初始值与其相同。
4. DPI + 100 也受硬件支持。

finally 尝试恢复的是仓库配置值，不是动态保存的硬件初始值；强制终止或断连时不保证恢复。不要在配置与硬件初始值不一致时运行。
