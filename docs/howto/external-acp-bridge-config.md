# 外部 ACP 接入配置脚本

这个 how-to 对应仓库内的独立工具：

```bash
dart tool/configure_external_acp.dart
```

它只做一件事：生成或更新 XWorkmate 本地 `settings.yaml` 里的 `externalAcpEndpoints`，不改 Flutter 运行时代码，不碰 secrets。

前提：

- 在仓库根目录执行。
- 首次在新 clone 上使用前，先跑一次 `flutter pub get`，确保 `.dart_tool/package_config.json` 已生成。

## App Store 对齐约束

这次工具链按 App Store 分发边界设计，约束如下：

- 这是仓库外置脚本，不是 app bundle 内功能。
- `codex`、`opencode`、`supergateway`、`mcp-bridge`、`gemini-bridge` 都必须作为用户侧或运维侧前置依赖，不能打包进 XWorkmate 的 App Store 构建产物。
- 脚本只改用户态 `settings.yaml`，不改 entitlements、不改打包脚本、不往 DMG / `.app` bundle 写入任何第三方二进制或 secrets。
- 外部 bridge 进程必须由用户在安装后手动启动；这次方案不要求、也不允许 App Store 包内自动拉起这些进程。

## 默认 provider 映射

脚本默认会把 4 个内置 provider 写成下面的 endpoint：

| Provider | Endpoint | 约定启动方式 |
| --- | --- | --- |
| Codex | `ws://127.0.0.1:9001` | `codex app-server --listen ws://127.0.0.1:9001` |
| OpenCode | `http://127.0.0.1:4096` | `opencode serve --port 4096` |
| Claude | `ws://127.0.0.1:9011` | 本地 bridge 槽位 |
| Gemini | `ws://127.0.0.1:9012` | 本地 bridge 槽位 |

注意：

- 这里把 OpenCode 固定写成 `127.0.0.1:4096`。如果你之前记成 `27.0.0.1:4096`，这里应为 loopback 地址 `127.0.0.1:4096`。
- 当前 XWorkmate external ACP 路径保存的是 provider endpoint；脚本负责“写配置”，不负责替你守护进程。
- `settings.yaml` 是非敏感配置源。token、password、API key 仍不应该写进去。

## 默认路径

脚本默认按宿主平台定位 `settings.yaml`：

- macOS: `~/Library/Application Support/xworkmate/config/settings.yaml`
- Linux: `${XDG_CONFIG_HOME:-~/.config}/xworkmate/config/settings.yaml`
- Windows: `%APPDATA%\\xworkmate\\config\\settings.yaml`

也可以显式传 `--settings-file` 覆盖。

## 常用命令

先只看计划，不落盘：

```bash
dart tool/configure_external_acp.dart print
```

按默认 endpoint 落盘，并自动备份原文件：

```bash
dart tool/configure_external_acp.dart apply
```

指定自定义 endpoint：

```bash
dart tool/configure_external_acp.dart apply \
  --claude-endpoint ws://127.0.0.1:19111 \
  --gemini-endpoint ws://127.0.0.1:19112
```

只打印将要写入的 YAML，不真正写文件：

```bash
dart tool/configure_external_acp.dart apply --dry-run
```

禁用某个 provider 槽位：

```bash
dart tool/configure_external_acp.dart apply --disable-claude
```

## 原生 provider

### Codex

启动：

```bash
codex app-server --listen ws://127.0.0.1:9001
```

写配置：

```bash
dart tool/configure_external_acp.dart apply \
  --codex-endpoint ws://127.0.0.1:9001
```

### OpenCode

启动：

```bash
opencode serve --port 4096
```

写配置：

```bash
dart tool/configure_external_acp.dart apply \
  --opencode-endpoint http://127.0.0.1:4096
```

说明：

- 这是按当前约定写入的原生 OpenCode endpoint。
- XWorkmate 当前 single-agent 运行时会把 `http/https` endpoint 归一化成 `ws/wss` 连接再发 JSON-RPC 请求，所以 OpenCode 端是否完全兼容，取决于你前面的桥是否提供了 XWorkmate 当前期望的方法集。
- 这次变更不改项目代码，因此这里只负责把槽位写好，不额外实现 OpenCode 协议适配。

## 桥接 provider

### Gemini

你给出的要求是：

1. 本地起一个 `stdio` MCP server
2. 再把它桥到 XWorkmate 使用的本地 endpoint

推荐的最小链路：

1. 安装 Gemini CLI 并登录
2. 安装 `gemini-bridge`
3. 用 `supergateway` 把本地 `stdio` MCP server 暴露到 WebSocket 端口

参考命令：

```bash
npm install -g @google/gemini-cli
gemini auth login
pip install gemini-bridge
npx -y supergateway \
  --stdio "uvx gemini-bridge" \
  --outputTransport ws \
  --port 9012 \
  --messagePath /
```

然后写入：

```bash
dart tool/configure_external_acp.dart apply \
  --gemini-endpoint ws://127.0.0.1:9012
```

### Claude

你给出的要求同样是：

1. 本地起一个 `stdio` bridge
2. 再桥到 XWorkmate 的本地 endpoint

按这次文档约定，Claude 槽位使用：

- 本地 bridge 命令：`mcp-bridge`
- WebSocket 暴露：`supergateway`
- 本地 endpoint：`ws://127.0.0.1:9011`

参考命令：

```bash
pip install mcp-bridge
mcp-bridge init
```

编辑：

```text
~/.config/mcp-bridge/config.json
```

填入你的远程 MCP URL 和认证信息后，再启动本地桥：

```bash
npx -y supergateway \
  --stdio "mcp-bridge" \
  --outputTransport ws \
  --port 9011 \
  --messagePath /
```

然后写入：

```bash
dart tool/configure_external_acp.dart apply \
  --claude-endpoint ws://127.0.0.1:9011
```

## 兼容性边界

这次提交只补“配置脚本 + 使用说明”，不改 XWorkmate runtime，所以边界需要说清楚：

- 脚本保证 `externalAcpEndpoints` 写法正确，并保留非内置 custom provider 条目。
- 脚本不会自动拉起 `codex`、`opencode`、`supergateway`、`mcp-bridge` 或 `gemini-bridge`。
- 脚本不会写入任何 secret。
- Claude / Gemini 这里走的是“本地 bridge endpoint 槽位”方案。是否能被当前 XWorkmate runtime 直接消费，取决于桥后的协议是否与当前 external ACP 路径兼容。
- 如果后续要把 Claude / Gemini 做成真正的开箱即用 provider，需要再补一层项目内协议适配；这次明确不做。
