# MouseSpeedKeeper

macOS 上的轻量 Logitech 硬件 DPI 保持工具。Swift 直接使用系统 IOKit 和 HID++ 2.0 Adjustable DPI（0x2201），不依赖 Options+ 或第三方运行时。

只修改选定鼠标的硬件 DPI，不修改 macOS 指针速度、加速度、触控板、按键或滚轮。通过设备 Unit ID 匹配鼠标。

## Homebrew 安装

需要 macOS、Homebrew 和 Xcode Command Line Tools 14+（`swiftc`）。缺少编译工具时执行 `xcode-select --install` 并完成系统安装界面。目前从源码编译，不提供 bottles。

```sh
brew install laixintao/tap/mouse-speed-keeper
```

安装后的命令是 `mouse-speed`。安装不会修改 DPI、覆盖配置或自动启动服务。

新版 Homebrew 若提示 untrusted formula，先检查 tap 中的 `Formula/mouse-speed-keeper.rb`，确认信任后执行 `brew trust --formula laixintao/tap/mouse-speed-keeper`，再重试安装；旧版 Homebrew 可能没有 trust 命令。

## 首次配置

接通并唤醒鼠标：

```sh
mouse-speed probe
```

创建配置目录，并仅在配置不存在时捕获当前设备 ID 和 DPI：

```sh
config_dir="$HOME/Library/Application Support/MouseSpeedKeeper"
mkdir -p "$config_dir"
if [ ! -e "$config_dir/config.json" ]; then
  mouse-speed capture "$config_dir/config.json"
fi
```

capture 需要恰好探测到一只支持的鼠标。若捕获失败，先排障，不要启动服务。编辑目标 DPI：

```sh
nano "$HOME/Library/Application Support/MouseSpeedKeeper/config.json"
```

例如将 `dpi` 改为 `2200`，保持自己的 `identity` 不变。然后启动当前用户的登录服务：

```sh
brew services start mouse-speed-keeper
```

**不要使用 sudo。** 启动后会按配置恢复硬件 DPI。不要同时手动运行另一个 `mouse-speed watch`。

## 修改 DPI

编辑同一配置文件，只修改 `dpi`，然后重启：

```sh
brew services restart mouse-speed-keeper
```

watch 只在启动时读取配置，不会自动重载 JSON。等待一轮后查询实际硬件 DPI：

```sh
mouse-speed probe
```

后台是一个持续运行的 Swift 进程：每轮查找鼠标、读取 DPI，仅在与目标值不同时设置并读回验证，之后休眠 5 秒。设备探测超时会延长实际检查间隔，不会每 5 秒启动 Python。

## 状态与日志

```sh
brew services list
```

```sh
tail -n 30 "$HOME/Library/Application Support/MouseSpeedKeeper/agent.log" \
  "$HOME/Library/Application Support/MouseSpeedKeeper/error.log"
```

配置与日志位于 `~/Library/Application Support/MouseSpeedKeeper/`。服务标签固定为 `homebrew.mxcl.mouse-speed-keeper`，程序由 Homebrew 管理。DPI 没有变化时不会持续输出成功日志。

## 升级、停止与卸载

```sh
brew update
brew upgrade mouse-speed-keeper
```

如果正在使用后台服务，升级后重启：

```sh
brew services restart mouse-speed-keeper
```

停止并取消登录自动启动：

```sh
brew services stop mouse-speed-keeper
```

卸载前先停止服务：

```sh
brew services stop mouse-speed-keeper
brew uninstall mouse-speed-keeper
```

卸载保留配置与日志，不还原硬件 DPI，不操作 Logitech 服务。

## 兼容性与排障

实机验证环境为 macOS 15、MX Anywhere 3S + Logi Bolt USB 接收器。其他型号、蓝牙直连、真实重启、接收器拔插和睡眠唤醒需分别验证。设备必须提供 0x2201 和非零 Unit ID。

- 找不到设备：检查电源、接收器、鼠标是否唤醒及兼容性。
- 无法打开 HID：检查系统设置 → 隐私与安全性 → 输入监控，必要时允许 Homebrew 安装的 `mouse-speed`，注销再登录。工具不绕过权限。
- DPI 来回变化：检查是否运行了多个 watch，或 Options+ 是否设置了不同值。本工具不替代 Options+ 的按键映射等功能。

完整配置格式、CLI、日志和测试说明见 [配置文档](docs/configuration.md)。

## 开发与验证

在仓库根目录编译：

```sh
bash scripts/build.sh
```

产物为 `.build/mouse-speed`；本地编译不会安装或启动服务。源码位于 `Sources/MouseSpeed.swift`。配置模板是 `config.example.json`，其中设备 ID 不能照抄。

Homebrew 的无硬件测试：

```sh
brew test laixintao/tap/mouse-speed-keeper
```

`scripts/check-recovery.py` 是可选的有副作用测试，会短暂改变 DPI。执行前阅读配置文档，不要把它作为安装步骤。
