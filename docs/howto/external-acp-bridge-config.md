# 外部 ACP Endpoint 预配置脚本

这个工具是一个**外置 pre 动作**：

```bash
dart tool/configure_external_acp.dart
```

它只负责生成或更新 XWorkmate `settings.yaml` 里的 `externalAcpEndpoints`。

它**不**做这些事：

- 不修改 Flutter runtime 代码
- 不往 `.app` bundle、DMG 或打包脚本写任何内容
- 不启动任何外部 provider、bridge、daemon 或 CLI
- 不写入 token、password、API key 等 secrets

## App Store 对齐边界

当前脚本按 App Store 边界收敛为“纯配置助手”：

- 脚本在 app 外运行
- 只写用户态配置文件
- 不再内置或推荐任何第三方 bridge 依赖
- Claude / Gemini 在这里只是 endpoint 槽位，不绑定特定实现

如果某个 provider 以后要接入，要求是：

- 由你自行准备一个兼容的外部 endpoint
- XWorkmate 只消费 endpoint，不负责拉起依赖

## 默认 provider 槽位

| Provider | 默认 endpoint |
| --- | --- |
| Codex | `ws://127.0.0.1:9001` |
| OpenCode | `http://127.0.0.1:4096` |
| Claude | `ws://127.0.0.1:9011` |
| Gemini | `ws://127.0.0.1:9012` |

说明：

- 这些值只是默认槽位，不代表脚本会安装或启动任何 provider。
- `Codex` / `OpenCode` 的本地地址被保留为示例默认值。
- `Claude` / `Gemini` 仅保留 endpoint 占位，不再绑定第三方桥接包说明。
- ACP contract 的规范路径统一为 `/acp` 与 `/acp/rpc`。
- local / loopback 可使用 `ws://` 或 `http://`。
- remote endpoint 必须使用 `wss://` 或 `https://`，不能静默降级到非 TLS。

## macOS 路径策略

macOS 默认增加了 App Sandbox 感知：

- `--settings-scope auto`
  优先写 `~/Library/Containers/plus.svc.xworkmate/Data/Library/Application Support/xworkmate/config/settings.yaml`
  如果容器目录还不存在，再退回 `~/Library/Application Support/xworkmate/config/settings.yaml`
- `--settings-scope sandbox`
  强制写 App Sandbox 容器路径
- `--settings-scope user`
  强制写非沙盒用户目录路径

这让脚本既能服务 Mac App Store 安装版，也保留非沙盒构建的旧路径。

## 前置条件

- 在仓库根目录执行
- 首次在新 clone 上使用前，先跑一次 `flutter pub get`

## 常用命令

查看将使用哪个配置文件，以及要写入哪些 endpoint：

```bash
dart tool/configure_external_acp.dart print
```

按自动路径策略写入：

```bash
dart tool/configure_external_acp.dart apply
```

强制写入 Mac App Store 容器路径：

```bash
dart tool/configure_external_acp.dart apply --settings-scope sandbox
```

强制写入旧的用户目录路径：

```bash
dart tool/configure_external_acp.dart apply --settings-scope user
```

指定自定义 endpoint：

```bash
dart tool/configure_external_acp.dart apply \
  --codex-endpoint ws://127.0.0.1:9001 \
  --opencode-endpoint http://127.0.0.1:4096 \
  --claude-endpoint ws://127.0.0.1:19111 \
  --gemini-endpoint ws://127.0.0.1:19112
```

协议边界：

- 如果你提供的是 base URL，运行时应派生：
  - websocket endpoint：`/acp`
  - RPC endpoint：`/acp/rpc`
- 如果你提供的 URL 已经包含 `/acp` 或 `/acp/rpc`，运行时不得重复拼接。

只打印结果 YAML，不落盘：

```bash
dart tool/configure_external_acp.dart apply --dry-run
```

禁用某个槽位：

```bash
dart tool/configure_external_acp.dart apply --disable-claude
```

## 兼容性边界

- 这个脚本只负责 `externalAcpEndpoints`
- 它会保留非内置 custom provider 条目
- 它不会判断某个 endpoint 背后是否真的可用
- 它不会绕过 XWorkmate 在 App Store 构建里对外部 CLI / 本地 runtime 的禁用策略
