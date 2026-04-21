# xworkmate-app 核心功能测试全景规划 V1

## Summary

本轮 `xworkmate-app` 侧核心验收聚焦 UI 与交互层，目标是确认：

1. APP 能从 `accounts.svc.plus -> xworkmate-bridge.svc.plus` 动态拿到 provider / routing / 能力面。
2. Assistant UI、线程状态、artifact 展示和 follow-up 行为都围绕“bridge 动态发现 + APP 本地 workspace 优先”运行。

这里不强调后端 provider 固定列表，而强调：

- UI provider 选项来自 bridge 动态发现
- 线程内 provider / workspace / artifact 状态可见且不串线
- 追问继续复用当前线程，不意外漂移

## Scope

### 1. Provider 发现与 UI 展示

- UI 不依赖固定静态 provider 列表。
- “智能体模式” provider 列表由 bridge `acp.capabilities` 动态驱动。
- “Gateway 模式” provider 列表由 bridge `目前支持 openclaw
- 当 bridge 广告能力变化时，provider selector、状态文案和可执行状态同步更新。
- `auto` 模式下，UI 应表现为“由 bridge 当前可用项决定”，而不是写死默认 provider。

  | Service Endpoint      │ Protocol   │ Result │ Functional Check                  │
  ├───────────────────────┼────────────┼────────┼───────────────────────────────────┤
  │ /acp-server/codex/    │ JSON-RPC   │ PASS   │ acp.capabilities returned         │
  │                       │ (SSE/HTTP) │        │ successfully via /acp/rpc         │
  │ /acp-server/gemini/   │ JSON-RPC   │ PASS   │ acp.capabilities returned         │
  │                       │ (SSE/HTTP) │        │ successfully via /acp/rpc         │
  │ /acp-server/opencode/ │ JSON-RPC   │ PASS   │ acp.capabilities returned         │
  │                       │ (SSE/HTTP) │        │ successfully via /acp/rpc         │
  │ /gateway/openclaw/    │ WSS / RPC  │ PASS   │ WebSocket handshake successful at │
  │                       │            │        │ /acp; received connect.challenge


### 2. Assistant 线程体验

- `agent` 线程首次发送时自动绑定完整 `workspaceBinding`。
- 当前线程的 provider、workspace、artifact 只属于当前线程，不污染其他线程。
- 二次追问继续复用当前线程与当前本地 workspace。
- prompt 文本不能覆盖已绑定 workspace。

### 3. Artifact 可见性

- bridge 返回的 `artifacts` 需要被 APP 写入当前线程本地目录。
- Assistant / artifact 面板可以看到新结果。
- 同名文件默认版本化，不覆盖旧结果。
- browser case 下，摘要、截图、日志应能进入统一结果面。

### 4. 状态与错误反馈

- 无 provider 时，UI 给出 ACP-only 的明确提示。
- 已绑定但当前不可用的 provider，UI 给出“不可自动改线”的提示。
- debug runtime 开启时，UI 可以显示当前 target 的 runtime/provider 状态。
- provider 未就绪、workspace 缺失、执行失败时，提示文案与线程状态一致。

## Test Scope by Layer

### A. UI / Feature Layer

重点看用户实际能看到什么：

- provider selector
- task dialog target chip / label（`agent` / `gateway`）
- thread workspace 与 artifact 可见性
- 错误提示与状态提示
- thread 切换后的 provider / artifact 隔离

建议主测文件：

- `test/features/assistant_page_single_agent_flow_suite.dart`
- `test/features/assistant_page_installed_skill_e2e_suite.dart`
- `test/features/assistant_page_suite.dart`
- `test/features/settings_page_external_acp_end_to_end_suite.dart`

### B. Runtime / Controller Layer

重点看线程绑定、provider 解析、workspace 语义和结果落盘：

- `test/runtime/account_bridge_smoke_suite.dart`
- `test/runtime/app_controller_ai_gateway_chat_suite.dart`
- `test/runtime/app_controller_single_agent_workspace_binding_regression_test.dart`
- `test/runtime/desktop_thread_artifact_service_test.dart`
- `test/runtime/go_task_service_client_test.dart`

## Core Cases

| Case | UI 侧目标能力 | 核心验收点 |
| --- | --- | --- |
| `docx` | 展示文档生成结果 | `.docx` 写回当前线程；assistant 结果与 artifact 面板一致；后续补写仍在同线程 |
| `xlsx` | 展示表格与计算结果 | `.xlsx` 结果写回当前线程；后续追问继续修改同一线程内容 |
| `pptx` | 展示生成中的文稿任务与追问续写 | 首次生成结果可见；继续追问仍在同线程；workspace 不变；新文件或新版本可见 |
| `pdf` | 展示文件转换结果 | `.pdf` 产物可见；转换后结果属于当前线程；继续操作不漂移 |
| `image-resizer` | 展示图片处理结果 | 输出图片写回当前线程；artifact 面板可见；尺寸变化可通过测试或 fixture 校验 |
| `browser` | 展示摘要、截图、日志 | assistant 文本有摘要；截图 / 日志进入 artifact 面板；继续浏览仍在当前线程 |

## Test Plan

### Phase 1: UI 与账户桥接 Smoke

先验证 app 能拿到 bridge 能力与 provider 动态结果：

```bash
flutter test test/runtime/account_bridge_smoke_suite.dart
flutter test test/features/settings_page_external_acp_end_to_end_suite.dart
```

### Phase 2: Agent Runtime 回归

验证 thread / provider / workspace / artifact 主链路：

```bash
flutter test test/runtime/app_controller_ai_gateway_chat_suite.dart
flutter test test/runtime/app_controller_single_agent_workspace_binding_regression_test.dart
flutter test test/runtime/go_task_service_client_test.dart
```

### Phase 3: Artifact Surface 回归

验证结果文件是否被 APP 统一展示：

```bash
flutter test test/runtime/desktop_thread_artifact_service_test.dart
```

### Phase 4: Feature / UI 交互验收

验证用户在页面上能否正确看到 provider、结果与线程隔离：

```bash
flutter test test/features/assistant_page_single_agent_flow_suite.dart
flutter test test/features/assistant_page_installed_skill_e2e_suite.dart
flutter test test/features/assistant_page_suite.dart
```

### Phase 5: 6 个 Case 最小验收

每个 case 至少覆盖两步：

1. 首次执行
2. 一次追问 / 复用线程

建议每个 case 的 UI 最少断言：

| Case | Step 1 | Step 2 |
| --- | --- | --- |
| `pptx` | assistant 返回文稿结果；artifact 面板出现 `.pptx` | 同线程追问修改后，仍在当前线程显示结果 |
| `docx` | artifact 面板出现 `.docx` | 同线程补写后，结果仍写回当前线程 |
| `xlsx` | artifact 面板出现 `.xlsx` | 同线程继续修改；workspace 不变 |
| `pdf` | artifact 面板出现 `.pdf` | 同线程继续转换/合并；结果仍归属当前线程 |
| `image-resizer` | 输出图片出现于当前线程 | 再次调整尺寸时不新建错误线程 |
| `browser` | 摘要显示在 assistant 消息里；截图 / 日志进入 artifact 面板 | 同线程继续浏览；结果继续累积在当前线程 |

## Recommended Assertions

### Provider / UI 断言

- provider selector 的选项来自 bridge 当前广告结果。
- `agent` target 只展示 bridge 当前广告的 ACP bridge providers。
- `gateway` target 只展示 bridge 当前广告的 gateway providers。
- UI 不会展示 bridge 未广告的 provider 作为可执行项。
- bridge 未返回 catalog 时，provider 菜单为空或禁用，而不是硬编码 provider。
- provider 不可用时，线程提示信息正确。

### Thread / Workspace 断言

- 当前线程 `workspaceBinding` 自动完成绑定。
- 当前线程 `workspaceBinding` 始终保持本地目录真相源。
- `remoteWorkingDirectory` 只记录为 metadata。
- follow-up 请求继续复用当前线程的本地 workspace。

### Artifact / Result Surface 断言

- bridge 返回的 `artifacts` 被 APP 落盘到当前线程本地目录。
- artifact 面板读取的是当前线程本地目录。
- 同名文件版本化成功，例如 `report.docx -> report.v2.docx`。
- browser case 的摘要、截图、日志都能进入统一结果面。

### UX / Error 断言

- 无 provider 时，错误提示明确指向 bridge/provider 配置问题。
- provider 已绑定但不可用时，UI 不会偷偷改线到其他 provider。
- debug runtime 打开时，当前 target 的 provider/runtime 状态对用户可见。

## Execution Order

建议按下面顺序执行，便于先确认 UI 能否感知 bridge，再确认 thread / artifact 语义：

1. `flutter test test/runtime/account_bridge_smoke_suite.dart`
2. `flutter test test/features/settings_page_external_acp_end_to_end_suite.dart`
3. `flutter test test/runtime/go_task_service_client_test.dart`
4. `flutter test test/runtime/app_controller_ai_gateway_chat_suite.dart`
5. `flutter test test/runtime/app_controller_single_agent_workspace_binding_regression_test.dart`
6. `flutter test test/runtime/desktop_thread_artifact_service_test.dart`
7. `flutter test test/features/assistant_page_single_agent_flow_suite.dart`
8. `flutter test test/features/assistant_page_installed_skill_e2e_suite.dart`
9. `flutter test test/features/assistant_page_suite.dart`
10. 再按 `pptx / docx / xlsx / pdf / image-resizer / browser` 做专项最小验收

## Assumptions

本次测试默认使用与 bridge 规划一致的在线环境：

- `https://accounts.svc.plus`
- `review@svc.plus`
- `<review-account-password>`
- managed bridge origin: `https://xworkmate-bridge.svc.plus`
- `BRIDGE_AUTH_TOKEN=...`

补充口径：

- `BRIDGE_SERVER_URL` 若仍出现在账户返回中，仅作为 metadata，不再是运行期入口前置条件。

额外约定：

- UI 本轮不改结构，只验证 provider 列表来源、展示结果与 thread 内状态。
- `gateway` target 若 bridge 当前未广告任何 gateway provider，可 `skip`，但 UI 不得伪造 `openclaw` 默认入口。
- 如果某些长耗时在线任务未在默认时间窗内完成，允许先记录为 `timeout`，再用专项 case 延长超时补验。

## Deliverable

第一版 `xworkmate-app` 核心功能测试清单的完成标准：

- UI 能证明 provider 列表来自 bridge 动态发现
- thread / workspace / artifact 语义已通过 runtime 回归
- feature 层能看到 `agent / gateway` 结果、状态和错误提示
- 6 个典型 case 都有最小 UI 验收骨架
- 所有断言都围绕“用户在 APP 里能否看到正确 provider、正确线程、正确结果”展开
