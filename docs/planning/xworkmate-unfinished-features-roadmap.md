# XWorkmate 未完成能力路线图

更新时间：2026-03-14

## 原则

路线图按真实可交付顺序排列，不再把 placeholder 能力写成已完成。

## Phase 1: External Codex CLI 协同模式

目标：

- 用户显式启用 bridge
- XWorkmate 启动外部 Codex CLI
- 已连接 OpenClaw 时执行 `agent/register`
- AI Gateway 继续作为统一模型桥接

状态：

- 已进入可交付范围
- 仍需持续补强 widget test / 手工联调

验收口径：

- Bridge 不自动开机拉起
- Gateway 离线时可降级为本地 bridge
- Built-in 不对外宣称可用

## Phase 2: 其他外部 Code Agent CLI 预留

目标：

- 保留统一 provider registry
- 保留 capability metadata
- 为未来调度和发现能力预留 runtime contract

状态：

- registry 已存在
- 当前只有 `codex` 一个 provider

本阶段不做：

- provider chooser UI
- 多 provider 调度策略
- 第二个 provider 之前的泛化产品设计

## Phase 3: Built-in Codex / Rust FFI

目标：

- 在不依赖外部 `codex` 可执行文件的情况下运行内置 Code Agent

前置条件：

- `rust/src/lib.rs` 补完消息发送与事件轮询
- `rust/src/runtime.rs` 补完进程启动与停止
- 能复用当前 coordinator / registry 契约

状态：

- 仍是 future work
- 当前不进入交付承诺

## 与 Gateway 能力的真实边界

当前不要混淆：

- Scheduled Tasks：只读 `cron.list`
- Memory：只到 `memory/sync`
- Agent 协同：已到 `agent/register`

尚未进入本路线图交付的内容：

- 任务创建 / 删除
- 记忆 CRUD 产品化
- Codex 直接连 Gateway 的独立 RPC 通道
