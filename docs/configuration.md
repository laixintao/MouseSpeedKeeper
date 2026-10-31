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

`dpi` 必须为整数，程序允许 100–65535，实际支持范围和步进由硬件决定。写入后会读回验证。修改设置时保持自己的 identity。

可选的 `scrollMode` 控制硬件滚轮：

```json
{
  "dpi": 2200,
  "identity": "1234abcd",
  "scrollMode": "ratchet"
}
```

| 值 | 行为 |
| --- | --- |
| `"ratchet"` | 固定有段落感，将自动脱离阈值设为 255，禁止 SmartShift 自动切到自由滚动 |
| `"freeSpin"` | 固定自由滚动，保留自动脱离阈值 |
| 省略或 `null` | 不查询或修改滚轮，保留原有 DPI-only 行为 |

值区分大小写，不接受其他字符串。两种固定模式均保留滚轮阻力和设备默认阈值。不支持 SmartShift（0x2110/0x2111）时，设置操作会在修改 DPI 前报错；通信失败也不会被当成不支持而忽略。两项设置并非原子操作，DPI 成功后滚轮写入仍可能失败，以日志和 probe 为准。

watch 会恢复模式键或其他软件造成的改变。删除该字段并重启只会停止管理滚轮，不会还原此前的自动切换阈值。`capture` 保持兼容，只保存 ID 和 DPI；不会自动启用滚轮控制，也不会保存已有配置中的 `scrollMode`。

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
| `mouse-speed probe` | 查询设备 ID、插槽、DPI 和滚轮状态，不修改硬件 |
| `mouse-speed capture CONFIG.json` | 读取当前 DPI 并写配置，会覆盖同名文件；要求恰好一只支持设备 |
| `mouse-speed apply CONFIG.json` | 强制设置 DPI 及配置中的滚轮模式，并读回验证 |
| `mouse-speed watch CONFIG.json` | 持续恢复配置值，只在对应状态不同时写入 |

无参数等同 probe。当前没有 help/version 子命令或 `--help` / `--version` 选项。后台运行时使用另一份配置 apply 会被后台恢复。修改目标应编辑生效配置并重启服务。

probe 的 `scroll` 输出包括 `ratchet`、`freeSpin`、`smartShift(threshold=N)`、`unsupported`。通信失败时显示 `unavailable`，并向 stderr 输出原因，仍可查看 DPI。`smartShift` 表示当前允许按速度自动切换，不等于固定段落模式。

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

日志首次启动前可能不存在。受管理的设置未变化时不输出新的成功日志；没有新日志不表示服务停止。目前没有配置日志轮转。

## 排障

- **配置未生效**：确认配置路径，重启 brew 服务，等待一轮，再用 probe 查询硬件。
- **找不到设备**：唤醒鼠标，检查电源、接收器和型号兼容性。新程序和其他构建都找不到时，不要据此断言安装失败。
- **Cannot open HID device**：检查输入监控权限，必要时允许 Homebrew 的实际二进制，注销再登录；工具不绕过权限。
- **DPI 来回变化**：排查多个 watch 或 Options+ 同时写入。工具不会自动停止或卸载 Logitech 服务。
- **滚轮未固定**：检查 `scrollMode` 拼写、服务是否已重启及 probe 输出；旧程序会忽略新字段，必须使用支持滚轮的新版本。查看服务错误日志，避免 Options+ 同时管理模式。
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

无硬件的滚轮协议测试：

```sh
bash scripts/test.sh
```

覆盖旧配置兼容、0x2110/0x2111 功能选择、固定段落模式、保留阻力、模式改变后的恢复、不重复写入、不支持的设备及读回失败。测试通过不等于实机滚轮已验证。

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

该脚本只使用配置的 `identity` 和 `dpi`，即使配置包含 `scrollMode` 也不会设置滚轮。finally 尝试恢复的是仓库配置值，不是动态保存的硬件初始值；强制终止或断连时不保证恢复。不要在配置与硬件初始值不一致时运行。

协议实现参考：[Solaar 的 SmartShift 设置](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/settings_templates.py)及 [logiops 的 SmartShift 接口](https://github.com/PixlOne/logiops/blob/main/src/logid/backend/hidpp20/features/SmartShift.cpp)。
