# 配置、使用与排障

## 修改为 2200 DPI（已安装）

编辑正在使用的配置：

```sh
nano "$HOME/Library/Application Support/MouseSpeedKeeper/config.json"
```

格式示例（identity 为虚构示例，必须保留自己配置中的设备 ID）：

```json
{
  "dpi": 2200,
  "identity": "1234abcd"
}
```

只改 dpi，不改 identity。其他鼠标必须通过 probe / capture 获取自己的 Unit ID。dpi 必须是整数；程序允许 100–65535，但实际范围和步进取决于硬件，写入后会读回验证。

保存后重启服务：

```sh
launchctl kickstart -k "gui/$(id -u)/local.mouse-speed-keeper"
```

**watch 只在启动时读取一次配置，不会自动重载 JSON。** 等待一轮检查后读回实际硬件 DPI：

```sh
"$HOME/Library/Application Support/MouseSpeedKeeper/mouse-speed" probe
```

同步回仓库配置，避免下次安装覆盖：

```sh
cp "$HOME/Library/Application Support/MouseSpeedKeeper/config.json" /Users/xintao.lai/Programs/MouseSpeedKeeper/mouse-config.json
```

## 首次安装与升级注意

需要 macOS、Xcode Command Line Tools（swiftc）和安装脚本调用的 `/usr/bin/python3`。缺少编译器时运行 `xcode-select --install`，完成系统安装界面。

在仓库目录执行 README 的 build、probe、capture、install 流程。想直接指定 2200 时，在 capture 后编辑 mouse-config.json，再安装即可，不需要预先用 Options+ 调整。

安装脚本会停止旧服务，覆盖安装目录的二进制和配置，重新启动并应用仓库的 DPI。**仓库 mouse-config.json 和安装目录 config.json 是两份独立文件，不是符号链接。** 已安装用户升级前先把生效配置同步回仓库；不要无意用 capture 覆盖想保留的目标 DPI。

LaunchAgent 在用户登录后运行，非登录前的系统 daemon；无需 sudo。后台重新枚举设备，每轮完成后休息 5 秒，离线探测耗时意味着实际周期更长。离线时等待，并不保证产生错误日志。

## CLI

| 命令 | 行为 |
| --- | --- |
| `mouse-speed probe` | 查询设备 ID、插槽和 DPI，不修改 DPI |
| `mouse-speed capture CONFIG.json` | 读取当前 DPI 并写出配置；必须恰好探测到一只支持设备 |
| `mouse-speed apply CONFIG.json` | 强制设置 DPI 并读回验证 |
| `mouse-speed watch CONFIG.json` | 持续恢复配置值，只在 DPI 不同时写入 |

无参数等同 probe。后台运行时用另一份配置 apply 会被后台恢复；修改目标值应改安装配置并重启。

## 路径、状态、日志

| 内容 | 路径 |
| --- | --- |
| LaunchAgent | `~/Library/LaunchAgents/local.mouse-speed-keeper.plist` |
| 程序 | `~/Library/Application Support/MouseSpeedKeeper/mouse-speed` |
| 生效配置 | `~/Library/Application Support/MouseSpeedKeeper/config.json` |
| 运行日志 | `~/Library/Application Support/MouseSpeedKeeper/agent.log` |
| 错误日志 | `~/Library/Application Support/MouseSpeedKeeper/error.log` |

查看状态：

```sh
launchctl print "gui/$(id -u)/local.mouse-speed-keeper"
```

查看最近日志：

```sh
tail -n 30 "$HOME/Library/Application Support/MouseSpeedKeeper/agent.log" "$HOME/Library/Application Support/MouseSpeedKeeper/error.log"
```

实时查看：

```sh
tail -f "$HOME/Library/Application Support/MouseSpeedKeeper/agent.log" "$HOME/Library/Application Support/MouseSpeedKeeper/error.log"
```

DPI 未变化时不会持续输出成功日志；没有新日志不代表服务已停止。当前安装脚本没有配置日志轮转。

## 停止与重新启动

暂时停止（保留 plist，下次登录仍可启动）：

```sh
launchctl bootout "gui/$(id -u)/local.mouse-speed-keeper"
```

重新载入已安装的 plist：

```sh
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/local.mouse-speed-keeper.plist"
```

永久移除本工具登录项，在仓库执行：

```sh
bash scripts/uninstall.sh
```

保留程序、配置和日志；硬件 DPI 不还原；不会操作 Logitech 的服务。恢复此前手动禁用的 Options+ 的命令见 README。

## 排障

- **配置没生效**：检查改的是安装目录 config.json，执行 kickstart，使用 probe 读回硬件确认。
- **找不到鼠标**：检查电源、唤醒、接收器连接和型号兼容性；其他型号、蓝牙连接未由本机测试证明可用。
- **Cannot open HID device**：检查系统设置 → 隐私与安全性 → 输入监控，必要时允许安装目录的 mouse-speed，注销再登录。工具不绕过系统权限。
- **DPI 来回变化**：Options+ 可能同时设置不同值；本工具不会自动卸载或停止 Logitech 服务，也不替代按键映射等功能。
- **Invalid configuration**：检查 JSON、整数 dpi 和 8 字符 identity。建议重新 capture 后只修改 dpi。
- **service not found**：检查当前登录会话及安装状态；重装前先确保仓库配置正确。

## 验证与副作用边界

安全的本地编译、语法检查：

```sh
bash scripts/build.sh
```

```sh
bash -n scripts/build.sh scripts/install.sh scripts/uninstall.sh
```

只读硬件探测：

```sh
.build/mouse-speed probe
```

`python3 scripts/check-recovery.py` 会实际提高 DPI 100，再等待后台恢复。执行前必须确认后台运行、鼠标在线且只有一只支持设备，并同步安装配置到仓库，使用 probe 确认硬件初始 DPI 与配置一致，确保 DPI + 100 在硬件支持范围内。

脚本 finally 尝试恢复的是仓库配置值，不是临时捕获的硬件初始值。强制杀进程、设备断连等情况不保证恢复。此检查不能代替真实重启、拔插或睡眠唤醒验证。README 的 2026-10-20 测试描述来自原项目历史记录，不代表本次迁移重新执行了有副作用的测试。
