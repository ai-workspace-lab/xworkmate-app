# FFI And Rust

## Purpose

`rust/src` 当前是一组相对独立、边界清晰的 Codex FFI 草图实现。这里的重点是：

- Rust 公开结构体与状态模型
- C ABI 函数签名
- Dart / Flutter 侧应该如何理解这些函数的参数与返回值
- 当前实现仍然是 stub 的地方在哪里

## Crate Layout

| File | Responsibility |
| --- | --- |
| `rust/src/lib.rs` | 对外 `pub use` 与 `#[no_mangle] extern "C"` 导出 |
| `rust/src/runtime.rs` | Rust-native runtime/config/state |
| `rust/src/types.rs` | FFI-safe message/result/event/account/model 结构 |
| `rust/src/error.rs` | `CodexError` 错误类型 |

## `CodexConfig`

- Source: `rust/src/runtime.rs`
- Type: `struct`
- Responsibility:
  C ABI 输入配置，描述 Codex 二进制、工作目录、sandbox/approval policy、model、gateway 和 debug。

### Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `codex_path` | `*const c_char` | Codex 可执行文件路径 |
| `working_directory` | `*const c_char` | 工作目录 |
| `sandbox_mode` | `i32` | `0=read-only`, `1=workspace-write`, `2=danger-full-access` |
| `approval_policy` | `i32` | `0=suggest`, `1=auto-edit`, `2=full-auto` |
| `model` | `*const c_char` | 模型标识 |
| `api_key` | `*const c_char` | gateway API key |
| `gateway_url` | `*const c_char` | gateway URL |
| `debug` | `bool` | debug logging 开关 |

### Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `Default::default()` | `CodexConfig` | 默认 FFI config |
| `to_rust(&self)` | `Result<CodexConfigRust, CodexError>` | 转成 Rust-native 配置 |

## `CodexConfigRust`

- Source: `rust/src/runtime.rs`
- Type: `struct`
- Responsibility:
  Rust-native 配置对象，所有指针型字符串都已经转成 `Option<String>`。

## `ThreadHandle`

- Source: `rust/src/runtime.rs`
- Type: `struct`
- Responsibility:
  作为 C ABI 的 thread opaque handle。

### Fields and Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `id` | `u64` | 线程句柄 ID |
| `new(id)` | `ThreadHandle` | 构造有效句柄 |
| `null()` | `ThreadHandle` | 零值句柄 |
| `is_null()` | `bool` | 判空 |

## `RuntimeState`

- Source: `rust/src/runtime.rs`
- Type: `enum`
- Responsibility:
  Rust runtime 的内部状态机：`Disconnected / Connecting / Connected / Ready / Error`。

## `CodexRuntime`

- Source: `rust/src/runtime.rs`
- Type: `struct`
- Responsibility:
  Rust 侧管理 Codex 进程与错误状态的核心对象。

### Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `config` | `CodexConfigRust` | Rust-native 配置 |
| `state` | `RuntimeState` | 当前状态 |
| `last_error` | `CString` | 最近错误信息 |

### Key Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `new(config: CodexConfig)` | `CodexRuntime` | 由 FFI config 构造 |
| `with_config(config: CodexConfigRust)` | `CodexRuntime` | 由 Rust-native config 构造 |
| `state(&self)` | `RuntimeState` | 当前状态 |
| `set_error(&mut self, message: &str)` | `()` | 更新错误并切 `Error` |
| `find_codex_binary(&self)` | `Option<PathBuf>` | 查找 codex 二进制 |
| `start(&mut self)` | `Result<(), CodexError>` | 启动 runtime |
| `stop(&mut self)` | `Result<(), CodexError>` | 停止 runtime |

### Notes

- 当前 `start/stop` 仍然是 stub 型实现，尚未真正管理外部进程生命周期

## `CodexResult`

- Source: `rust/src/types.rs`
- Type: `struct`
- Responsibility:
  最通用的 FFI-safe 成败返回值。

### Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `success` | `bool` | 是否成功 |
| `error_code` | `i32` | 错误码 |
| `error_message` | `*const c_char` | 错误消息指针 |

### Returns

| API | Returns | Meaning |
| --- | --- | --- |
| `ok()` | `CodexResult` | 成功结果 |
| `err(code, message)` | `CodexResult` | 失败结果 |

## `CodexMessage`

- Source: `rust/src/types.rs`
- Type: `struct`
- Responsibility:
  FFI-safe 消息载体。

### Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `message_type` | `*const c_char` | text/code/tool_call 等类型 |
| `content` | `*const c_char` | 消息文本 |
| `thread_id` | `*const c_char` | thread ID |
| `turn_id` | `*const c_char` | turn ID |

## `CodexEvent`

- Source: `rust/src/types.rs`
- Type: `struct`
- Responsibility:
  FFI-safe 事件载体。

### Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `event_type` | `*const c_char` | started/delta/completed/error |
| `thread_id` | `*const c_char` | thread ID |
| `turn_id` | `*const c_char` | turn ID |
| `data` | `*const c_char` | JSON 负载 |
| `timestamp` | `i64` | Unix millis |

## `CodexError`

- Source: `rust/src/error.rs`
- Type: `enum`
- Responsibility:
  Rust 侧统一错误表示，供 runtime 和 FFI 转换使用。

## Exported FFI Functions

下面这些函数定义在 `rust/src/lib.rs`，是 Flutter / Dart 侧真正可调用的 C ABI 面。

## `codex_init`

- Type: `FFI function`
- Signature role:
  初始化入口，必须先于其它 FFI 调用。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| none | `i32` | `0` 表示成功 |

## `codex_runtime_create`

- Type: `FFI function`
- Responsibility:
  创建 `CodexRuntime` 并返回原始指针。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `config: *const CodexConfig` | `*mut CodexRuntime` | 成功返回 runtime 指针，空指针表示失败 |

### Notes

- 调用方负责后续 `codex_runtime_destroy`

## `codex_runtime_destroy`

- Type: `FFI function`
- Responsibility:
  释放由 `codex_runtime_create` 返回的 runtime 指针。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `runtime: *mut CodexRuntime` | `void` | 空指针时 no-op |

## `codex_start_thread`

- Type: `FFI function`
- Responsibility:
  以 `cwd` 启动 thread，目前返回 stub `ThreadHandle::new(0)`。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `runtime: *mut CodexRuntime`, `cwd: *const c_char` | `ThreadHandle` | cwd 为空时返回 null handle |

## `codex_send_message`

- Type: `FFI function`
- Responsibility:
  向指定 thread 发送消息，目前仍是 stub。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `runtime`, `thread`, `message` | `i32` | `0` 成功，`-1` 表示参数非法 |

## `codex_poll_events`

- Type: `FFI function`
- Responsibility:
  从 runtime 读取事件数组，目前仍返回 `0`。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `runtime`, `events`, `max_events` | `usize` | 实际写入事件数量 |

## `codex_shutdown`

- Type: `FFI function`
- Responsibility:
  优雅关闭 runtime，目前仍是 stub。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `runtime: *mut CodexRuntime` | `i32` | `0` 成功，空指针返回 `-1` |

## `codex_last_error`

- Type: `FFI function`
- Responsibility:
  返回最近错误的 C 字符串指针。

### Parameters and Returns

| Parameters | Returns | Meaning |
| --- | --- | --- |
| `runtime: *mut CodexRuntime` | `*const c_char` | 指向静态有效到下次 FFI 调用前的错误文本 |

## Dart Integration Notes

- Dart 侧对应阅读顺序：
  1. `lib/runtime/codex_runtime.dart`
  2. `lib/runtime/codex_config_bridge.dart`
  3. `rust/src/lib.rs`
  4. `rust/src/runtime.rs`
  5. `rust/src/types.rs`
- 当前 FFI 面已经具备“结构体/函数签名骨架”，但消息收发、event polling、thread lifecycle 仍未完整实现
