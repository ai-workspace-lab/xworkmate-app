# 架构优化与死代码清理建议

跨 App (Flutter/Dart) + Plugin (TypeScript) 两层系统性扫描结果。

> Bridge 层 (Go, `xworkmate-bridge`) 代码未在 workspace 中，仅从 App 侧调用签名反推。

## 一、可立即删除的死代码

### D1 [App] `expectedArtifactExtensions` — 全链路透传但从未验证

| 文件 | 行号 |
|------|------|
| `lib/runtime/runtime_models_runtime_payloads.dart` | 930, 946, 971, 990, 1007, 1062-1063 |

`expectedArtifactExtensions` 字段在 `OpenClawTaskAssociation` 中完整声明、序列化 (`toJson`/`toTaskGetParams`)、反序列化 (`fromJsonOrNull`)、在 `copyWith` 中保留——但在整个 `lib/` 和 `test/` 的生产逻辑中，**没有任何验证逻辑读取这个字段**。它仅被测试断言验证"不包含"。

**清理建议**: 保留数据模型定义（Bridge 可能发送此字段），但在 App 日志/错误信息中添加 warning 级日志说明此字段未被验证，避免误导后续开发者。

### D2 [App] `DesktopGoTaskService` — 零价值透传层

| 文件 | 行号 |
|------|------|
| `lib/runtime/go_task_service_desktop_service.dart` | 1-84（全文件） |

每个方法都是 `=> _acpTransport.sameMethod(...)`，无一例外。构造函数接受 `GatewayRuntime gateway` 参数但从未存储或使用（行 8-10）。`@visibleForTesting` 的 `acpTransportForTest` 也无测试引用。

**清理建议**: 删除此类。将 `app_controller_desktop_core.dart` 中的 `goTaskServiceClientInternal` 字段类型从 `GoTaskServiceClient` 改为直接引用 `ExternalCodeAgentAcpTransport`。接口 `GoTaskServiceClient` 仅被 `DesktopGoTaskService` 实现——如果后者删除，接口也可删除。

### D3 [App] `GoTaskServiceClient` 上 3 个从未调用的方法

| 方法 | 文件 | 行号 |
|------|------|------|
| `loadExternalAcpCapabilities` | `go_task_service_client.dart` + `external_code_agent_acp_desktop_transport.dart` | ~35, 15 |
| `resolveExternalAcpRouting` | `go_task_service_client.dart` + `external_code_agent_acp_desktop_transport.dart` | ~79, 24 |
| `closeTask` | `go_task_service_client.dart` + `external_code_agent_acp_desktop_transport.dart` | ~349, 66 |

这三个方法在 `ExternalCodeAgentAcpDesktopTransport` 中有完整实现，通过 `DesktopGoTaskService` 透传，但 `goTaskServiceClientInternal` 从不调用它们（只有 `executeTask`/`getTask`/`cancelTask`/`dispose` 被调用）。

**清理建议**: 如果删除 `DesktopGoTaskService`（D2），这些方法自然成为 `ExternalCodeAgentAcpDesktopTransport` 上未曾从 production 路径调用的公开方法。在 `ExternalCodeAgentAcpTransport` 接口上加 `// UNUSED in production; kept for potential future use` 注释，或直接删除。

### D4 [App] `openClawGatewayActiveTasksInternal` — 仅测试使用的 getter

| 文件 | 行号 |
|------|------|
| `lib/app/app_controller_desktop_core.dart` | 270-271 |

```dart
int get openClawGatewayActiveTasksInternal =>
    openClawGatewayActiveTurnsInternal.length;
```

生产代码中零引用（只在 `test/runtime/assistant_execution_target_test.dart` 中被断言）。后备字段 `openClawGatewayActiveTurnsInternal` 被多处生产代码直接使用。

**清理建议**: 删除 getter，测试中改为直接访问 `openClawGatewayActiveTurnsInternal.length`。

### D5 [App] 5 个 `@visibleForTesting` 无测试引用的导出

| 导出 | 文件 | 行号 |
|------|------|------|
| `addRuntimeLogForTest` | `lib/runtime/gateway_runtime_core.dart` | 91 |
| `usesSessionClient` | `lib/runtime/gateway_runtime_core.dart` | 100 |
| `sessionClientForTest` | `lib/runtime/gateway_runtime_core.dart` | 103 |
| `clientForTest` | `lib/runtime/external_code_agent_acp_desktop_transport.dart` | 31 |
| `acpTransportForTest` | `lib/runtime/go_task_service_desktop_service.dart` | 77 |

**清理建议**: 全部删除。若后续测试需要，届时再加。

### D6 [Plugin] `openClawSnapshotSources` 中 `params.snapshotSourceRoots` 路径

| 文件 | 行号 |
|------|------|
| `src/exportArtifacts.ts` | 992-1006 |

该函数的 `configured` 路径从 `params.snapshotSourceRoots` 读取——但没有任何生产调用者（`index.ts` 中的 gateway handler、`bridgeAgents.ts`）传递这个参数。`pluginConfig.snapshotSourceRoots` 也未在 `openclaw.plugin.json` 配置 schema 中声明。运行时始终回退到默认的 `~/.openclaw/media` + `os.tmpdir()/openclaw`。

**清理建议**: 删除 `configured` 路径，简化函数为直接返回默认值数组。如果未来需要外部配置，届时再加。

---

## 二、架构优化建议

### A1 [App] 消除 `_artifactBytesResultInternal` 的 `skipped`/`failed` 语义模糊

**文件**: `lib/app/app_controller_desktop_runtime_helpers.dart`，行 901-938

当前 7 条返回路径中，4 条返回 `skipped`（包括"授权缺失"这种真实错误），1 条返回 `failed`。调用者（行 828-831）只检查 `bytesResult.failed`，而 `skipped` 的 `failed` 为 `false` → 授权失败被静默处理。

**建议**: 将"授权缺失"（行 927-929）从 `skipped` 改为 `failed`，使调用者能区分"有 URL 但下载失败"和"根本没有 URL"。

### A2 [App] `gatewayResultCodeRequiresNewSessionInternal` 缺失关键错误码

**文件**: `lib/app/app_controller_desktop_thread_actions.dart`，行 1555

当前列表缺少：
- `OPENCLAW_GATEWAY_SOCKET_CLOSED` — 在 `app_controller_desktop_runtime_helpers.dart:295` 引用但未加入列表
- 回退 `'error'` — `gatewayTerminalResultCodeInternal` 可能返回此值，但当前默认为"不需要新会话"（return false），这可能不安全

**建议**: 追加 `OPENCLAW_GATEWAY_SOCKET_CLOSED`；将回退逻辑从 `return false` 改为 `return true`（未识别的错误 → 保守策略：开新会话）。

### A3 [App] `clearGatewayTaskArtifactStateInternal` 是不必要的间接层

**文件**: `lib/app/app_controller_desktop_thread_actions.dart`，行 1299

两个调用者都在同一个父函数 `applyGatewayChatResultInternal` 内，且都传入 `syncStatus: 'failed'`。函数体是单次 `upsertTaskThreadInternal` 调用。

**建议**: 将调用内联，删除此函数。

### A4 [Plugin] `XWorkmateArtifactPrepare` 类型导出但无消费

**文件**: `src/exportArtifacts.ts`，行 50-60

该类型作为 `prepareXWorkmateArtifacts` 的返回类型导出，但在 `bridgeAgents.ts` 或 `index.ts` 中从未被显式导入为类型注解——代码使用解构和 `const` 推断类型。

**建议**: 如果 TypeScript 结构化类型推断不需要此 export，移除 `export` 关键字。保留类型定义（内部使用），但不再对外暴露。

### A5 [Plugin] `manifestMarkdown` 在 App/Bridge 层未消费

**文件**: `src/exportArtifacts.ts`，行 47, 354, 466, 470-504

`manifestMarkdown` 由 `formatArtifactManifestMarkdown` 生成并附加到每个 `XWorkmateArtifactExport`。但 grep 整个 xworkmate-app 代码库，此字段名从未在 TypeScript 生产代码中被按名消费。它仅由插件的 tool response 使用（作为 markdown 格式化文本）。

**建议**: 评估是否真的需要跨 ACP 传输 markdown 字符串（增大 payload）。如果 App 层不需要，可将 `formatArtifactManifestMarkdown` 调用下移到 tool handler 层（`index.ts`），而不是嵌入 export payload。

### A6 [跨层] `sinceUnixMs` 时间戳来源不确定导致文件遗漏

**问题**: `exportXWorkmateArtifacts` 的 `sinceUnixMs` 参数控制"只导出此时间之后修改的文件"。但在当前调用链中，此时间戳由 Bridge 或 Gateway 传入，App 侧无法控制。当 Gateway 在 session.start 之前就开始写入文件，而这些文件的时间戳早于 `sinceUnixMs` → 被过滤。

**跨层修复**: 
- Plugin 侧：当 scope 目录的 `birthtimeMs` 晚于 `sinceUnixMs` 时，使用 `scopeStat.birthtimeMs` 代替 sinceUnixMs（已在 ROOT_CAUSE_ANALYSIS.md Fix 7）。
- App 侧：`persistGoTaskArtifactsForSessionInternal` 中，当 `artifacts` 列表为空且 `isOpenClawNoExportedArtifactsGuardResultInternal` 为 false 时，fallback 扫描 workspace 中 lastRunAtMs 之后修改的文件（行 787-791）——此逻辑已存在但未考虑 Gateway agent 的输出目录可能不在 workspace 根。

---

## 三、清理优先级与预估节省

| 编号 | 类型 | 层 | 影响 | 节省 |
|------|------|-----|------|------|
| D2+D3 | 删除类+3方法 | App | 消除无意义抽象 | ~130 行 |
| D4 | 删除 getter | App | 消除仅测试的 production 导出 | 3 行 |
| D5 | 删除 5 个 test-only getter | App | 清理未使用的测试 API | ~20 行 |
| D1 | 加 warning 注释 | App | 文档化而非删除 | 0 行 |
| D6 | 删除死分支 | Plugin | 简化 snapshot 逻辑 | ~15 行 |
| A3 | 内联 | App | 减少函数调用层 | ~10 行 |
| A4 | 移除 export | Plugin | 缩小公开 API | 1 行 |
| A5 | 下移调用 | Plugin | 减少跨层 payload | ~5 行移动 |
| A1 | 改语义 | App | 修复静默错误 | 1 行 |
| A2 | 补错误码 | App | 修复保守性缺口 | 2 行 |

**总计**: 可删除约 170 行死代码，2 个语义修复各 1 行，2 个架构重构（不含跨层 A6）。

---

## 四、Bridge 层（xworkmate-bridge, Go）的推断问题

Bridge 层代码不在当前 workspace 中，但从 App 侧调用签名可推断以下架构问题：

1. **ACP `session.start` 缺少 `expectedArtifactDirs`** — App 侧 `toExternalAcpParams()` 未传此字段，Bridge ACP handler 也未接收。这是 Plugin Fix 0 的前置依赖。

2. **`xworkmate.tasks.get` 的快照模式** — 当前实现返回单一快照（status + artifacts），不支持"仅返回 artifacts"或"等待 artifacts ready"语义。建议增加可选参数 `waitForArtifacts: true` 或 `minArtifactCount: N`，由 Bridge 轮询至条件满足后再返回。

3. **`xworkmate.artifacts.collect-and-snapshot` 的调用时机** — 当前 snapshot 在 agent 执行完成后调用，但 agent 在 session 结束前就可能已写入文件。建议在 session 生命周期中加入 `beforeSessionEnd` hook 自动触发 snapshot。

---

## 五、单元测试缺口

| 缺口 | 应在文件 |
|------|----------|
| `_recoveredResultFromTaskSnapshot` 的 Map 类型敏感性 | `external_code_agent_acp_desktop_transport.dart` 测试 |
| `_isRecoverableTaskStreamClosure` 对 `ACP_SSE_NO_RESULT` 的覆盖 | 同上 |
| `persistGoTaskArtifactsForSessionInternal` 的 `partial` 状态分支 | `assistant_execution_target_test.dart` |
| `contentTypeForPath` 的 `.pptx`/`.xlsx`/`.mov`/`.webm` 分支 | `exportArtifacts.test.ts` |
| `openClawSnapshotSources` 的默认路径 | `exportArtifacts.test.ts`（已有隐含覆盖但无显式断言） |
