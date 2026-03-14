# XWorkmate Codex 集成实际运行状态分析

## 分析时间
2026-03-14 10:30

## 1. Codex FFI 调用能力验证

### ❌ **结论：无法通过 FFI 调用 Codex 进行对话和执行**

### 实际实现方式

**CodexRuntime 类使用外部 CLI 模式：**

```dart
lib/runtime/codex_runtime.dart:382
_process = await Process.start(
  codexPath,
  args,  // ['app-server', '--listen', 'stdio://', ...]
  workingDirectory: cwd,
);
```

**工作流程：**

```
XWorkmate (Flutter/Dart)
    ↓
CodexRuntime.startStdio()
    ↓
Process.start() → 启动外部 'codex' 可执行文件
    ↓
Stdio (stdin/stdout/stderr)
    ↓
JSON-RPC 通信
    ↓
Codex CLI (外部进程)
```

### FFI 库状态

**libcodex_ffi.dylib 当前状态 - 仅桩代码：**

| FFI 函数 | 实现 | 说明 |
|----------|------|------|
| `codex_init()` | ✅ 桩代码 | 返回 0，无实际初始化 |
| `codex_runtime_create()` | ✅ 桩代码 | 创建 Box 并返回指针，无进程 |
| `codex_start_thread()` | ✅ 桩代码 | 返回 id=0 空句柄 |
| `codex_send_message()` | ✅ 桩代码 | 返回 0，未发送消息 |
| `codex_poll_events()` | ✅ 桩代码 | 返回 0，无事件队列 |

**Rust 源码确认：**

```rust
rust/src/lib.rs:87     // TODO: Implement async message sending
rust/src/lib.rs:108    // TODO: Implement event polling
rust/src/runtime.rs:235 // TODO: Start process
rust/src/runtime.rs:247 // TODO: Stop process
```

所有核心功能都有 TODO 标记，未实现。

## 2. AI Gateway 桥接能力验证

### ✅ **结论：可以桥接到 AI Gateway 提供的模型**

### 实现路径

```
XWorkmate 设置
    ↓
AI Gateway 配置 (URL、API Key、模型)
    ↓
CodexConfigBridge.configureForGateway()
    ↓
生成 ~/.codex/config.toml
    ↓
[model_providers.xworkmate]
base_url = "https://ai.example.com"
experimental_bearer_token = "xxx"
```

### 配置代码

```dart
lib/runtime/codex_config_bridge.dart:16
Future<void> configureForGateway({
  required String gatewayUrl,
  required String apiKey,
  String providerName = 'xworkmate',
  String defaultModel = 'gpt-4.1',
  ...
})
```

### 实际工作流程

```
1. 用户在设置中配置 AI Gateway
   - Gateway URL: https://ai.example.com
   - API Key: sk-xxx
   - 选择模型: gpt-4.1, gpt-4-mini, ...

2. 调用配置桥接
   await _runtimeCoordinator.configureCodexForGateway(
     gatewayUrl: gatewayUrl,
     apiKey: apiKey,
   );

3. 生成 Codex 配置文件
   ~/.codex/config.toml 包含：
   - [model_providers.xworkmate]
   - base_url
   - experimental_bearer_token

4. 启动 Codex 外部 CLI
   Codex CLI 读取配置文件
   使用 AI Gateway 作为模型提供方
   所有 AI 调用通过 AI Gateway 代理
```

### 支持的 AI Gateway 功能

| 功能 | 状态 | 说明 |
|------|------|------|
| 模型配置 | ✅ 支持 | 可从 AI Gateway 同步模型列表 |
| API Key 管理 | ✅ 支持 | 使用 API Key Ref 安全存储 |
| URL 配置 | ✅ 支持 | 自定义 AI Gateway 地址 |
| 模型选择 | ✅ 支持 | 可选择多个模型 |

### 实际调用链

```
用户发送消息
    ↓
CodexRuntime.sendMessage()
    ↓
JSON-RPC → 外部 Codex CLI (进程)
    ↓
Codex CLI 读取 config.toml
    ↓
[model_providers.xworkmate]
    ↓
HTTP 请求 → AI Gateway
    ↓
AI Gateway 代理到实际模型 (OpenAI、Anthropic等)
    ↓
响应返回
```

## 3. OpenClaw Gateway 集成验证

### ✅ **结论：通过 WebSocket 连接到 OpenClaw Gateway，但任务调度和远期记忆功能需要后端支持**

### OpenClaw Gateway 提供的功能

| 功能 | 客户端支持 | 后端需求 | 状态 |
|------|-----------|----------|------|
| 身份认证 | ✅ 已实现 | ✅ 已实现 | ✅ 可用 |
| 设备配对 | ✅ 已实现 | ✅ 已实现 | ✅ 可用 |
| Agent 列表 | ✅ 已实现 | ✅ 已实现 | ✅ 可用 |
| 聊天消息 | ✅ 已实现 | ✅ 已实现 | ✅ 可用 |
| 健康检查 | ✅ 已实现 | ✅ 已实现 | ✅ 可用 |

### 任务调度功能

| 功能 | 客户端代码 | 状态 |
|------|-----------|------|
| Cron 任务列表 | ⚠️ 部分实现 | 仅查询显示 |
| 创建 Cron 任务 | ❌ 未实现 | 无 UI |
| 删除 Cron 任务 | ❌ 未实现 | 无 UI |
| 任务执行状态 | ❌ 未实现 | 无监控 |

### 远期记忆功能

| 功能 | 客户端代码 | 状态 |
|------|-----------|------|
| 记忆存储 API | ❌ 未找到 | 无实现 |
| 记忆检索 API | ❌ 未找到 | 无实现 |
| 记忆管理 UI | ❌ 未找到 | 无界面 |

### GatewayRuntime 支持的方法

```dart
lib/runtime/gateway_runtime.dart

已实现的 RPC 方法：
- health()          // 健康检查
- status()          // 状态查询
- agents.list()     // Agent 列表
- devices.list()    // 设备列表
- devices.approve() // 设备批准
- chat.sendMessage() // 发送消息
- abortChat()       // 中止聊天
```

### 客户端未实现的功能

```dart
// 以下方法在 GatewayRuntime 中未找到：
- scheduleTask()           // 调度任务
- listScheduledTasks()     // 列出调度任务
- deleteScheduledTask()    // 删除调度任务
- storeMemory()            // 存储记忆
- retrieveMemory()        // 检索记忆
- listMemoryKeys()        // 列出记忆键
```

### 实际工作流程 (聊天 - 已实现)

```
XWorkmate 连接到 OpenClaw Gateway
    ↓
WebSocket 握手 (ws:// 或 wss://)
    ↓
设备配对审批
    ↓
mainSession 建立成功
    ↓
用户发送消息
    ↓
GatewayRuntime.request('chat.sendMessage', params)
    ↓
OpenClaw Gateway 处理
    ↓
Agent 响应返回
```

## 总结

| 需求 | 状态 | 实现方式 |
|------|------|----------|
| **1. FFI 调用 Codex** | ❌ | 仅桥代码，使用外部 CLI 模式 |
| **2. AI Gateway 桥接** | ✅ | 通过配置文件，Codex CLI 使用 AI Gateway |
| **3. OpenClaw 任务调度** | ⚠️ | 客户端已连接，但任务调度 API 未实现 |
| **4. OpenClaw 远期记忆** | ❌ | 客户端和 API 均未实现 |

### 实际可用的功能

```
✅ 本地 Codex 对话 (外部 CLI + JSON-RPC)
✅ AI Gateway 模型代理 (通过配置文件)
✅ OpenClaw Gateway 连接和身份认证
✅ OpenClaw Chat 消息收发
✅ OpenClaw Agent 列表查询
✅ OpenClaw 设备配对管理
```

### 未实现的功能

```
❌ FFI Rust 嵌入模式 (仅桥代码)
❌ OpenClaw 任务调度 (无 API)
❌ OpenClaw 远期记忆 (无 API)
❌ Codex 嵌入式执行 (仅外部进程)
```

### 架构总结

```
┌─────────────────────────────────────────────────────────┐
│                   XWorkmate (Flutter)                    │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────────┐  ┌──────────────────┐             │
│  │ OpenClaw         │  │ AI Gateway      │             │
│  │ Gateway          │  │ (模型代理)       │             │
│  │                  │  │                  │             │
│  │ • 身份认证 ✅   │  │ • 模型配置 ✅   │             │
│  │ • 设备配对 ✅   │  │ • API Key ✅    │             │
│  │ • Chat 消息 ✅  │  │ • 桥接 Codex ✅ │             │
│  │                  │  │                  │             │
│  │ • 任务调度 ❌   │  └──────────────────┘             │
│  │ • 远期记忆 ❌   │                                  │
│  └──────────────────┘                                  │
│                                                           │
│  ┌──────────────────┐                                   │
│  │ Codex Runtime    │                                   │
│  │                  │                                   │
│  │ 外部 CLI 模式 ✅  │                                   │
│  │ FFI 模式 ❌      │                                   │
│  │                  │                                   │
│  │ Process.start()  │                                   │
│  │ Stdio JSON-RPC   │                                   │
│  └──────────────────┘                                   │
└─────────────────────────────────────────────────────────┘
```

## 建议实现路径

### 1. 启用 FFI Codex (长期)

```rust
// 需要实现：
- ProcessManager (启动/停止 Codex 进程)
- MessageQueue (异步消息队列)
- EventStream (事件流输出)
- StdioHandler (stdio 处理)
```

### 2. 实现 OpenClaw 任务调度 (中期)

```dart
// 需要添加到 GatewayRuntime：
- scheduleTask()           // 创建任务
- listScheduledTasks()     // 列出任务
- deleteScheduledTask()    // 删除任务
- getTaskStatus()          // 查询状态
```

### 3. 实现 OpenClaw 远期记忆

```dart
// 需要添加到 GatewayRuntime：
- storeMemory()            // 存储记忆
- retrieveMemory()        // 检索记忆
- listMemoryKeys()        // 列出键
- deleteMemory()          // 删除记忆
```

### 4. AI Gateway 增强 (短期)

```dart
// 当前已经可用，可以：
- 添加模型缓存
- 添加多模型并发
- 添加流式响应
- 添加错误重试
```
