# Codex CLI 集成任务计划 - 已完成

## 目标（产品层）

1. 将 Codex CLI 集成到 XWorkmate 作为内置 Code Agent，支持 AI Gateway 模型桥接和 OpenClaw Gateway 在线/离线模式。
2. 提供可选设置：将 Codex CLI 以**外部依赖**方式接入 XWorkmate，支持同一套网关桥接与模式切换能力。
3. 预留其他外部 Code Agent CLI 的接入能力（统一注册、能力发现与调度）。

## 当前实现状态（对齐当前代码）

- 当前落地形态为**外部进程接入**：由 `CodexRuntime.startStdio()` 启动外部 `codex` 进程。
- Codex 可执行文件通过 `findCodexBinary()` 从 `CODEX_PATH`、常见安装目录与 `PATH` 中查找。
- 用户需预先安装 Codex CLI（例如 `npm i -g @openai/codex`）。
- 运行时由 Dart `Process`（`_process: Process?`）进行生命周期管理。
- 通过 `AgentRegistry`、`RuntimeCoordinator` 已具备多 Agent 扩展的基础结构，可继续接入其他外部 CLI。

## 架构概览

```
┌─────────────────────────────────────────────────────────────────────┐
│                        XWorkmate App (Flutter)                      │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────┐   │
│  │  GatewayRuntime   │    │  CodexRuntime     │    │  ModeSwitcher │   │
│  │  (WebSocket)      │    │  (Process/FFI)   │    │              │   │
│  │                  │    │                   │    │              │   │
│  │  wss://openclaw  │    │  codex app-server │    │              │   │
│  └────────┬─────────┘    └────────┬─────────┘    └──────┬───────┘   │
│           │                       │                       │           │
│  ┌────────▼───────────────────────▼───────────────────────▼───────┐ │
│  │                    Runtime Coordinator                           │ │
│  │    - CoordinatorMode: offline | online | auto                   │ │
│  │    - sendMessage() → 智能路由                                   │ │
│  │    - supportsCapability() → 能力检查                            │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│           │                       │                                  │
│  ┌────────▼─────────┐    ┌─────────▼────────┐                         │
│  │  AgentRegistry   │    │  CodexConfigBridge │                        │
│  │  - register()     │    │  - configureForGateway()                   │
│  │  - invokeAgent()  │    │  - configureAuth()                          │
│  │  - syncMemory()   │    │  - configureMcpServers()                   │
│  └──────────────────┘    └──────────────────┘                         │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      OpenClaw Gateway                                │
│  .env: AI-Gateway-Url = <development/test only>                      │
│  .env: AI-Gateway-apiKey = <do not commit real secrets>              │
│                                                                      │
│  模式切换:                                                           │
│  - Local:  127.0.0.1:18789 (本地代理)                               │
│  - Remote: wss://openclaw.svc.plus (云端增强)                       │
│  - Offline: 本地 Codex (无网关连接)                                  │
└─────────────────────────────────────────────────────────────────────┘
```

## 已完成文件

### Dart/Flutter 代码

| 文件 | 说明 |
|------|------|
| `lib/runtime/codex_runtime.dart` | Codex CLI 进程管理，JSON-RPC 通信 |
| `lib/runtime/codex_config_bridge.dart` | 配置文件生成器 |
| `lib/runtime/runtime_coordinator.dart` | 统一协调器，模式切换 |
| `lib/runtime/agent_registry.dart` | Agent 注册与发现服务 |
| `lib/runtime/codex_ffi_bindings.dart` | Dart FFI 绑定 |
| `lib/runtime/mode_switcher.dart` | OpenClaw Gateway 模式切换 |

### Rust FFI 代码

| 文件 | 说明 |
|------|------|
| `rust/Cargo.toml` | Rust crate 配置 |
| `rust/src/lib.rs` | FFI 入口点 |
| `rust/src/error.rs` | 错误类型定义 |
| `rust/src/types.rs` | FFI 安全类型 |
| `rust/src/runtime.rs` | 运行时封装 |

### 测试文件

| 文件 | 说明 |
|------|------|
| `test/runtime/codex_runtime_test.dart` | CodexRuntime 单元测试 |
| `test/runtime/codex_config_bridge_test.dart` | ConfigBridge 单元测试 |
| `test/runtime/agent_registry_test.dart` | AgentRegistry 单元测试 |
| `test/runtime/mode_switcher_test.dart` | ModeSwitcher 单元测试 |
| `test/runtime/codex_integration_test.dart` | 集成测试 |

### 构建脚本

| 文件 | 说明 |
|------|------|
| `scripts/build_rust_ffi.sh` | 编译 Rust FFI 库 (macOS universal) |
| `scripts/generate_ffi_bindings.sh` | 生成 FFI 绑定代码 |
| `scripts/integrate_rust_flutter.sh` | 集成到 Flutter 构建 |
| `flutter_rust_bridge.yaml` | flutter_rust_bridge 配置 |

## 运行测试

```bash
# 运行所有单元测试
flutter test test/runtime/

# 运行特定测试文件
flutter test test/runtime/mode_switcher_test.dart
flutter test test/runtime/codex_runtime_test.dart
flutter test test/runtime/agent_registry_test.dart

# 运行集成测试 (需要 .env 配置)
flutter test test/runtime/codex_integration_test.dart

# 编译 Rust FFI 库 (需要网络连接)
cd rust && cargo build --release
```

## 模式切换逻辑

### GatewayMode 枚举

```dart
enum GatewayMode {
  local,    // 本地模式: 127.0.0.1:18789
  remote,   // 远程模式: wss://openclaw.svc.plus
  offline,  // 离线模式: 本地 Codex
}
```

### ModeCapabilities

| 模式 | 云端记忆 | 任务队列 | 多代理 | 本地模型 | 代码代理 |
|------|---------|---------|--------|---------|---------|
| Local | ❌ | ❌ | ❌ | ✅ | ✅ |
| Remote | ✅ | ✅ | ✅ | ✅ | ✅ |
| Offline | ❌ | ❌ | ❌ | ❌ | ✅ |

### 使用示例

```dart
// 创建协调器
final coordinator = RuntimeCoordinator(
  gateway: gatewayRuntime,
  codex: codexRuntime,
);

// 自动选择最佳模式
await coordinator.initializeAuto(preferRemote: true);

// 手动切换模式
await coordinator.switchMode(GatewayMode.local);

// 检查能力
if (coordinator.supportsCapability('cloud-memory')) {
  // 使用云端记忆
  await coordinator.sendMessage(prompt: '...', preferOnline: true);
} else {
  // 使用本地模式
  await coordinator.sendMessage(prompt: '...', preferOnline: false);
}

// 获取状态信息
print(coordinator.currentMode);        // GatewayMode.remote
print(coordinator.capabilitiesDescription); // "Cloud Memory, Task Queue, ..."
print(coordinator.stateDescription);    // "Connected (Remote)"
```

## 下一步

1. **网络恢复后**: 运行 `cargo build --release` 编译 Rust 库
2. **CI/CD**: 添加构建脚本到 CI 流程
3. **生产部署**: 
   - 添加 FFI 库到 macOS Frameworks
   - 配置 Xcode 构建阶段
   - 测试通用二进制 (arm64 + x86_64)

## CI/CD 集成

### GitHub Actions Workflow

文件: `.github/workflows/build-rust-ffi.yml`

工作流程:
1. **build-macos**: 为 `aarch64` 和 `x86_64` 架构构建 Rust FFI 库
2. **build-universal**: 创建通用二进制
3. **test**: 运行 Rust 测试
4. **integrate-flutter**: 与 Flutter 构建集成

### Makefile 目标

```makefile
# 构建 Rust FFI 库
make rust-build           # release 模式
make rust-build-debug     # debug 模式
make rust-test            # 运行 Rust 测试

# FFI 集成
make ffi-copy             # 复制库到 macOS/Frameworks
make ffi-generate         # 生成 FFI 绑定
make ffi-integrate        # 完整集成流程

# 带 FFI 的 Flutter 构建
make build-macos-ffi      # 构建 macOS 应用并包含 FFI
```

### 本地开发

```bash
# 首次设置
make deps                  # 安装 Flutter 依赖
make rust-build            # 编译 Rust FFI 库

# 日常开发
make check                 # 分析 + 测试
make build-macos           # 构建 macOS 应用
```

## 生产部署

### macOS Frameworks 配置

1. **手动配置 Xcode**:
   - 打开 `macos/Runner.xcodeproj`
   - 选择 Runner target
   - Build Phases > Link Binary With Libraries
   - 添加 `libcodex_ffi.dylib`
   - 设置 Framework Search Paths: `$(PROJECT_DIR)/Frameworks`

2. **使用脚本**:
   ```bash
   make ffi-integrate
   ```

3. **构建脚本**:
   - `scripts/build_rust_ffi.sh` - 编译 Rust 库
   - `scripts/copy_ffi_framework.sh` - 复制到 Frameworks
   - `scripts/integrate_rust_flutter.sh` - 完整集成

### 依赖项

**Rust Crate 依赖**:
- `serde` - 序列化
- `serde_json` - JSON 处理
- `thiserror` - 错误处理

**Flutter 依赖**:
- 已在 `pubspec.yaml` 中配置
- 无需额外 FFI 依赖

## 运行测试

```bash
# 分析所有新创建的文件
dart analyze lib/runtime/codex_runtime.dart \
             lib/runtime/codex_config_bridge.dart \
             lib/runtime/runtime_coordinator.dart \
             lib/runtime/agent_registry.dart \
             lib/runtime/mode_switcher.dart

# 运行单元测试
flutter test test/runtime/codex_runtime_test.dart
flutter test test/runtime/codex_config_bridge_test.dart
flutter test test/runtime/agent_registry_test.dart
flutter test test/runtime/mode_switcher_test.dart

# 运行集成测试 (需要 .env 配置)
flutter test test/runtime/codex_integration_test.dart

# 运行 Rust 测试
cd rust && cargo test
```

## 故障排除

### 网络问题

如果 `cargo build` 因网络问题失败:
```bash
# 使用本地缓存
cd rust && cargo build --release --offline
```

### FFI 库未找到

如果运行时找不到 FFI 库:
```bash
# 检查库是否存在
ls -la rust/target/universal/libcodex_ffi.dylib
ls -la macos/Frameworks/libcodex_ffi.dylib

# 重新构建和复制
make ffi-integrate
```

### Flutter 编译错误

如果 Dart 分析失败:
```bash
# 检查导入是否正确
dart analyze lib/runtime/

# 确保所有文件存在
ls -la lib/runtime/codex_*.dart
ls -la lib/runtime/mode_switcher.dart
ls -la lib/runtime/agent_registry.dart
```

## 文件清单

### 已创建/更新的文件

```
lib/runtime/
├── codex_runtime.dart          ✅ Codex CLI 进程管理
├── codex_config_bridge.dart    ✅ 配置文件生成
├── codex_ffi_bindings.dart     ✅ FFI 绑定
├── runtime_coordinator.dart    ✅ 统一协调器
├── agent_registry.dart         ✅ Agent 注册服务
└── mode_switcher.dart          ✅ OpenClaw 模式切换

rust/
├── Cargo.toml                  ✅ Rust crate 配置
├── Cargo.lock                  ✅ 依赖锁定
└── src/
    ├── lib.rs                  ✅ FFI 入口
    ├── error.rs                ✅ 错误类型
    ├── types.rs                ✅ FFI 类型
    └── runtime.rs              ✅ 运行时封装

test/runtime/
├── codex_runtime_test.dart      ✅ CodexRuntime 测试
├── codex_config_bridge_test.dart ✅ ConfigBridge 测试
├── agent_registry_test.dart    ✅ AgentRegistry 测试
├── mode_switcher_test.dart      ✅ ModeSwitcher 测试
└── codex_integration_test.dart ✅ 集成测试

scripts/
├── build_rust_ffi.sh           ✅ 编译 Rust 库
├── copy_ffi_framework.sh        ✅ 复制到 Frameworks
├── generate_ffi_bindings.sh     ✅ 生成 FFI 绑定
└── integrate_rust_flutter.sh   ✅ 完整集成

.github/workflows/
└── build-rust-ffi.yml          ✅ CI/CD 工作流

docs/codex-integration/
└── tasks.md                    ✅ 本文件
```

## 下一步

当网络恢复后:

```bash
# 1. 编译 Rust FFI 库
cd rust && cargo build --release

# 2. 创建通用二进制
./scripts/build_rust_ffi.sh release

# 3. 复制到 Frameworks
./scripts/copy_ffi_framework.sh

# 4. 验证集成
make check
make build-macos-ffi
```
