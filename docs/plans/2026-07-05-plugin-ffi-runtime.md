# 多语言第三方插件运行时规划（FFI 桥接 / Sidecar）

- 日期：2026-07-05
- 状态：方向规划；数据模型脚手架已落地（`lib/features/plugins/builtin_plugin_runtime.dart`，见主规划 §8.4）
- 上游关联：`docs/plans/2026-07-04-builtin-plugins-batch-1.md` §8.1（workflow 状态机）、§8.2（插件目录解耦）

## 1. 目标与非目标

**目标**

1. 第三方插件可以用 Dart 以外的语言编写：Rust / C / C++ / Go / Zig（C-ABI 动态库，经 `dart:ffi` 桥接）与 Python / Node.js（sidecar 进程）。
2. 插件交付「workflow 状态机定义（§8.1 JSON schema v2）+ 可选本地步骤钩子」，与 App 发布节奏解耦，可独立安装/升级/回滚。
3. 与现有目录、composer、设置页插件面板无缝集成——外部插件加载后与内置插件同等展示与选择。

**非目标**

- **不开新的执行通道**。重负载（生成文档/PPT/视频等）仍统一走 `Flutter → GoTaskServiceClient → ACP → xworkmate-bridge → Gateway` 管线；本地钩子仅限轻量处理（输入格式化、参数预校验、产物后处理/预览转换）。
- 不做进程内插件 UI（不加载第三方 Flutter/Dart 代码）。
- 移动端（iOS/Android）本期不开放第三方动态库加载（商店政策 + 签名约束）；mobile 仅消费 `manifest` 声明式插件。

## 2. 架构总览

```
┌─ 插件定义来源（BuiltinPluginRuntimeBinding.kind）─────────────┐
│ builtinDart    编译进 App 的第一批目录（现状，缺省）           │
│ manifest       外部 workflow JSON（重构批次 3 拉取/缓存/校验）  │
│ nativeFfi      C-ABI 动态库（dart:ffi）                        │
│ sidecarProcess 外部进程（stdio JSON-RPC）                      │
└───────────────────────────────────────────────────────────────┘
        │ 统一产出：BuiltinPluginDescriptor(workflow, runtime)
        ▼
BuiltinPluginCatalog（内置 + 外部合并，id 冲突内置优先）
        ▼
composer 选择 → chips → 发送注入 Builtin plugins block（不变）
        ▼
Gateway 管线执行（不变）；BuiltinPluginWorkflowRun 跟踪进度/重试/续跑
        ▲
        └─ 可选本地钩子 xwm_plugin_step_run / step.run（轻量前后处理）
```

## 3. C-ABI 契约（nativeFfi）

所有字符串均为 UTF-8、NUL 结尾；JSON 编码。符号前缀缺省 `xwm_plugin`（绑定可覆写 `entrySymbolPrefix`）。

```c
// ABI 协商：App 只加载 major 匹配的插件（当前 1）。
int32_t xwm_plugin_abi_version(void);

// 插件元数据 + workflow 定义。返回 BuiltinPluginWorkflow schema v2 JSON，
// 外层包 descriptor 字段：
// { "id": "...", "kind": "document|...", "nameZh": ..., "nameEn": ...,
//   "descriptionZh": ..., "descriptionEn": ...,
//   "workflow": { schemaVersion: 2, goalZh, ..., steps: [...] } }
const char* xwm_plugin_manifest(void);

// 可选：本地步骤钩子。step_id 对应 workflow 步骤 id；
// context_json 携带 { sessionKey, currentTaskWorkspace, stepInputs, artifactsSoFar }。
// 返回 { "status": "succeeded|failed|degraded", "outputs": [相对路径...],
//        "message": "..." }；不导出该符号 = 纯声明式插件。
const char* xwm_plugin_step_run(const char* step_id, const char* context_json);

// 内存所有权：上述返回的 char* 由插件分配，App 用毕必须回调释放。
void xwm_plugin_free(const char* ptr);
```

约定：

- **线程模型**：App 在后台 isolate 里调用 FFI（`Isolate.run`），不阻塞 UI；单插件串行调用，插件内部无需可重入。
- **错误约定**：返回 `NULL` 或非法 JSON 视为失败，进入该步骤的 `failurePolicy` 流程（重试预算 → degrade/skip/abort），与 §8.1 状态机语义完全一致。
- **崩溃隔离限制**：`dart:ffi` 在进程内加载，native 崩溃会拖垮 App。因此 F1 阶段 nativeFfi 只开放 `manifest`（一次性调用、启动即验证）；`step_run` 常驻钩子优先推荐 sidecar（进程隔离），nativeFfi 钩子放 F2 并配套崩溃前置检查（加载时先在独立短生命周期进程内探测调用一次）。

## 4. Sidecar 协议（sidecarProcess）

- 传输：子进程 stdin/stdout，逐行 JSON-RPC 2.0；stderr 归入插件日志。
- 方法：
  - `manifest` → 同 §3 的 manifest JSON
  - `step.run` `{stepId, context}` → 同 §3 的 result JSON
  - `shutdown`（幂等）
- 生命周期：懒启动；空闲 5 分钟自动退出；单请求超时 60s（超时按步骤失败处理）；App 退出时统一 `shutdown` + SIGTERM 兜底。
- 适配层与 nativeFfi 共用同一 Dart 抽象（`PluginRuntimeClient` 接口：`loadManifest()` / `runStep()`），上层目录/执行代码不感知运行时差异。

## 5. 插件包与分发

```
<plugin-id>-<version>.xwmplugin/          # zip 容器
├── plugin.json                           # BuiltinPluginRuntimeBinding + 元数据
├── lib/
│   ├── macos-arm64/libxwm_<id>.dylib
│   ├── macos-x64/libxwm_<id>.dylib
│   ├── linux-x64/libxwm_<id>.so
│   └── windows-x64/xwm_<id>.dll
└── sidecar/                              # 或 sidecar 形态：入口脚本 + 依赖清单
```

- 完整性：`plugin.json` 内含各平台构件的 `sha256`；安装与每次加载前校验。
- 签名（F4）：包级签名 + 发布者身份；未签名包首次启用弹权限确认（明示「本地代码执行」）。
- 安装位置：`~/.xworkmate/plugins/<id>/<version>/`；多版本并存，回滚 = 切换目录指针。
- 目录合并：外部插件经批次 3 的清单加载器进 `BuiltinPluginCatalog`，id 冲突时内置优先并在设置页标注。

## 6. 里程碑

| 阶段 | 内容 | 依赖 |
| ---- | ---- | ---- |
| F0（已完成） | 数据模型脚手架：`BuiltinPluginRuntimeKind` / `BuiltinPluginRuntimeBinding`（version+sha256）+ descriptor.runtime 字段 + JSON | §8.1 批次 2 |
| F1 | manifest 声明式插件端到端：外部 JSON 拉取/缓存/sha256 校验/目录合并 + nativeFfi 只读 `xwm_plugin_manifest` 加载器 | 重构批次 3 |
| F2 | `xwm_plugin_step_run` 本地钩子 + 后台 isolate 调用 + 加载前探测；`PluginRuntimeClient` 抽象 | F1 |
| F3 | sidecar 运行时（协议、生命周期、超时→failurePolicy）；Python/Node 模板仓库 + Rust cdylib 模板仓库 | F2 |
| F4 | 包签名与发布者身份、权限提示 UI、设置页插件安装/升级/回滚管理 | F1–F3 |

## 7. 风险

- **本地代码执行面**：FFI/sidecar 均引入本地执行，签名校验与权限提示（F4）是启用第三方分发的硬前提；此前仅限手动安装的开发者模式。
- **进程内崩溃**：nativeFfi 无隔离，靠「manifest-only 起步 + 加载前探测 + 钩子优先走 sidecar」缓解。
- **平台矩阵成本**：三桌面平台 × 双架构的构建产物要求，模板仓库（Rust cdylib / Python sidecar）负责摊平。
- **ABI 漂移**：`xwm_plugin_abi_version` major 不匹配直接拒载；workflow schema 演进沿用 §8.1 的 schemaVersion 兼容策略。
