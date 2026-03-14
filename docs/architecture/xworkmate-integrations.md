# XWorkmate 集成架构说明

## 概述

XWorkmate 的"设置 > 集成"页面包含三个独立的集成服务，每个服务有不同的用途：

## 1. OpenClaw Gateway (网关连接)

**用途：** AI Agent OS 调度中心

> **注意：** 设置页面中显示为"OpenClaw Gateway"，避免与"AI Gateway"混淆

**功能：**
- **记忆管理** - 跨终端的云端记忆存储与检索
- **任务调度** - 任务队列、重试、执行跟踪
- **多 Agent 协调** - 多个 AI Agent 的编排和协同
- **设备配对** - 安全的设备身份管理和配对审批

**连接模式：**
- **本地模式** - `ws://127.0.0.1:18789` - 本地运行，无需云端
- **远程模式** - `wss://openclaw.svc.plus:443` - 云端增强，支持跨设备记忆

**配置项：**
- Host (默认: openclaw.svc.plus)
- Port (默认: 443)
- TLS (远程模式必须启用)
- 设备 ID、Role、Auth Token

## 2. AI Gateway

**用途：** AI 模型提供商统一管理网关 (APISIX AI 代理模式)

**功能：**
- **模型聚合** - 统一接入多个 AI Provider (OpenAI、Anthropic、Ollama 等)
- **API 路由** - 智能模型选择和请求转发
- **密钥管理** - 多 Provider 的 API Key 统一管理
- **模型同步** - 从 Gateway 拉取可用模型列表

**配置项：**
- Gateway URL (如: https://ai.example.com)
- API Key Ref (安全存储的密钥引用)
- Profile Name (配置名称)
- 选择/管理的模型列表

**支持的模式：**
- **在线模式** - 通过 AI Gateway 调用云端大模型
- **离线模式** - 使用内置 Codex Agent (通过 Rust FFI)

## 3. Vault Server

**用途：** 密钥与凭证的安全存储与审计

**功能：**
- **密钥保险箱** - 安全存储 API Keys、数据库凭证等
- **审计日志** - 完整的密钥访问和使用审计
- **细粒度权限** - 基于角色的密钥访问控制
- **本地存储备选** - 对于小型部署，支持使用本地密钥存储

**配置项：**
- Vault Server Address
- Namespace
- Auth Mode
- Token Ref
- 实际 Vault Token (安全输入)

## 三大集成的关系

```
┌─────────────────────────────────────────────────────────────┐
│                     XWorkmate Settings > 集成               │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │ OpenClaw       │  │ AI Gateway     │  │ Vault Server │ │
│  │ Gateway        │  │                │  │              │ │
│  │                 │  │                │  │              │ │
│  │ • 记忆管理      │  │ • 模型聚合      │  │ • 密钥保险箱 │ │
│  │ • 任务调度      │  │ • API 路由      │  │ • 审计日志   │ │
│  │ • 多 Agent 协调 │  │ • 密钥管理      │  │ • 访问控制   │ │
│  │ • 设备配对      │  │ • 模型同步      │  │ • 本地备选   │ │
│  │                 │  │                │  │              │ │
│  │ ws://或         │  │ Online:        │  │ Vault/Local  │ │
│  │ wss://          │  │ Cloud Models   │  │              │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
│           │                    │                  │         │
│           ▼                    ▼                  ▼         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              统一运行时协调器 (RuntimeCoordinator)   │   │
│  │                                                     │   │
│  │  • 离线模式：内置 Codex Agent (Rust FFI)           │   │
│  │  • 代理模式：通过 AI Gateway 调用模型             │   │
│  │  • 完整模式：OpenClaw + AI Gateway + Vault        │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 离线模式说明

在离线模式下（无 OpenClaw Gateway 连接）：

- ✅ **内置 Codex Agent 可用** - 通过 Rust FFI (`libcodex_ffi.dylib`) 运行
- ✅ **本地文件访问** - 可以读写工作区文件
- ❌ **云端记忆** - 不支持跨设备记忆
- ❌ **任务队列** - 不支持云端任务调度
- ❌ **云端模型** - 需连接 AI Gateway 才能使用云端大模型

离线模式仍然可以通过 AI Gateway 使用本地运行的 Ollama 等模型。

## 相关文件

| 集成 | 主要文件 |
|------|----------|
| OpenClaw Gateway | `lib/runtime/gateway_runtime.dart`, `lib/runtime/runtime_coordinator.dart` |
| AI Gateway | `lib/features/settings/settings_page.dart` (Gateway 标签) |
| Vault Server | `lib/models/app_models.dart` (`VaultConfig`), Settings Page |
| 离线 Codex | `lib/runtime/codex_runtime.dart`, `rust/src/lib.rs`, `rust/src/runtime.rs` |

## 测试检查清单

```bash
# 1. 测试内置 Codex FFI
dart test_codex_ffi.dart

# 2. 测试 OpenClaw Gateway 连接
# - 在设置 > 集成 > 网关连接中配置
# - 检查 127.0.0.1:18789 (本地) 或 wss://openclaw.svc.plus:443 (远程)

# 3. 测试 AI Gateway
# - 在设置 > 集成 > AI Gateway 中配置 URL 和 API Key
# - 测试模型同步和调用

# 4. 测试 Vault 连接
# - 在设置 > 集成 > Vault Server 中配置
# - 点击"测试 Vault"按钮
```

## 安全规则

- 所有密钥通过 `FlutterSecureStorage` 安全存储，不写入 `.env`
- `.env` 仅用于本地开发预填充，不会触自动连接
- OpenClaw 本地模式可使用 `ws://` (非 TLS)，远程模式必须使用 `wss://` (TLS)
- Vault Token 从不记录到日志、错误消息或截图
