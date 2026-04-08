# Codex CLI 集成任务路线图

## 当前结论

XWorkmate 当前唯一可交付的 Codex 集成路径是 **external CLI**，但只适用于非 App Store 的桌面构建：

- 通过 `CodexRuntime.startStdio()` 拉起外部 `codex app-server`
- 通过 `CodexConfigBridge` 把 AI Gateway 写入 `~/.codex/config.toml`
- 通过 `CodeAgentNodeOrchestrator` 把 XWorkmate 固定为 `app-mediated cooperative node`
- 通过 `RuntimeCoordinator` 保留多外部 Code Agent CLI 的统一 registry surface

App Store 桌面构建不应再拉起本机 `codex app-server`，而应只保留远程 ACP / gateway 语义。

Rust FFI / built-in Codex 仍是 future placeholder，不应宣传为已完成。

## 能力补全清单（按需求项）

1. 内置 Code Agent（built-in）：
   - 已提供运行时模式接入位与桥接流程编排（AI Gateway / OpenClaw 协同元数据）
   - 当前仍属于 experimental，受 Rust FFI TODO 约束
2. 外部依赖 Codex CLI：
   - 已作为稳定主路径接入
   - 保持与内置模式相同的桥接能力和模式切换语义
   - 写入 `~/.codex/config.toml` 时不覆盖原有非托管配置
3. 其他外部 Code Agent CLI：
   - 已通过 `ExternalCodeAgentProvider` 保留统一注册契约
   - capability metadata 与调度扩展点在 runtime 层收口

## 交付顺序

### Phase 1: 外部 Codex CLI 协同模式

目标：

1. 用户显式启用 bridge
2. XWorkmate 先启动外部 Codex CLI 进程
3. 若 OpenClaw Gateway 已连接，则将 XWorkmate 注册为协同 code-agent bridge
4. AI Gateway 继续作为同一套模型桥接入口
5. App 发送到 Gateway 的 chat 请求带上 node / provider / bridge dispatch metadata

交付范围：

- `SettingsSnapshot.codeAgentRuntimeMode`
- `SettingsSnapshot.codexCliPath`
- Codex bridge control panel
- Gateway `agent/register` 协同注册
- `chat.send` 的 app-mediated node metadata
- 本地降级：Gateway 不可用时，外部 Codex 仍可运行
- `CodexConfigBridge` 对 `~/.codex/config.toml` 采用非破坏性写入（仅更新 XWorkmate 托管块，保留原有配置）
- 仅在非 App Store 的桌面构建中执行外部 Codex CLI 启动

非目标：

- 不自动开机拉起 Codex
- 不新增 Gateway 后端 API
- 不做 provider chooser

### Phase 2: 其他外部 Code Agent CLI 预留

目标：

- 保留统一注册、能力 metadata 和调度扩展点
- Codex 自身也通过同一 registry surface 暴露 provider 身份

交付范围：

- `ExternalCodeAgentProvider` 继续作为唯一 provider contract
- provider metadata / capability discovery 继续收口在 runtime 层
- runtime 层提供统一发现/调度入口（`discoverExternalCodeAgents` / `selectExternalCodeAgent`）
- App 侧通过 `CodeAgentNodeOrchestrator` 统一生成 Gateway dispatch envelope
- 文档明确：当前 active provider 只有 `codex`

非目标：

- 不做第二个 provider 之前的通用 UI
- 不做复杂调度策略

### Phase 3: 内置 Codex / Rust FFI

目标：

- 仅在 Rust FFI 具备真实可用能力后，再开放 built-in 交付承诺

前置条件：

- `rust/src/lib.rs` 的消息发送 / 轮询 TODO 完成
- `rust/src/runtime.rs` 的进程启动 / 停止 TODO 完成
- 能复用与 external CLI 相同的 coordinator / registry 契约

## truth 收口

- Scheduled Tasks 当前只消费 `cron.list`，是只读展示
- Memory 当前只消费 `memory/sync`，是 sync-only
- `.env` 仍是 prefill-only，不是运行时真值源
- 远程网关仍必须保持 TLS 显式配置
- OpenClaw Gateway 只看到 `XWorkmate App node`，不会直接连接外部 CLI

## 本轮验收

- External Codex bridge 可显式启用/停用
- 已配置 AI Gateway 时可导出/写入 Codex bridge 配置
- OpenClaw 已连接时，XWorkmate 会执行一次 `agent/register`
- Gateway 不可用时，Bridge 退化为本地运行，不中断外部 Codex 进程
- 外部 Codex 集成不会覆盖用户已有 `~/.codex/config.toml` 非托管内容
