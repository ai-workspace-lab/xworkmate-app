# OpenClaw iOS 制品返回问题交接记录

> 日期：2026-07-16（Asia/Shanghai）
> 范围：`iOS APP -> xworkmate-bridge -> OpenClaw -> openclaw-multi-session-plugins`
> 目标：任务显示完成后，必须仍能返回并下载真实制品；UI 不变。
> 状态：**根因已定位，客户端修复随 PR [#148](https://github.com/ai-workspace-lab/xworkmate-app/pull/148) 落地；服务端遗留项见 §8。**
> 长期回归 case：[docs/cases/ios-artifact-return-regression/](../cases/ios-artifact-return-regression/README.md)
>
> 本文为可入库的脱敏版；涉及部署凭据与密钥存储的细节仅保留在维护者本地记录中，不入公开仓库。

## 1. 现场现象

- iOS 真机显示任务正文已经完成，但页面没有可用的制品返回或下载入口。
- 任务状态与制品状态必须分开判断：OpenClaw 文本完成，不等于 `artifacts.items` 已返回，也不等于文件已同步到 iOS 本地线程目录。
- 现场会话（OpenClaw session key）：`agent:main:draft:1784107717459614-1`，对应 app thread key `draft:1784107717459614-1`，本地线程目录 `$HOME/.xworkmate/threads/draft-1784107717459614-1`。
- 对照组：桌面端同一链路在 07-15 19:05 对 `draft-1784089143304708-1` 成功同步 6 个 markdown 制品（右边栏可见、可预览）。
- `runId`、`turnId`、`artifactScope` 必须从 `xworkmate.tasks.get` 的请求/响应中采集，禁止用 session key 猜 run ID。

## 2. 端到端数据链路

```text
iOS MobileAssistantConversation
  -> AppController.loadAssistantArtifactSnapshot()
  -> syncRemoteTaskArtifactsForSessionInternal()
  -> GoTaskServiceClient.getTask()
  -> ACP JSON-RPC: xworkmate.tasks.get
  -> xworkmate-bridge.handleTaskGet()
  -> OpenClaw gateway: xworkmate.tasks.get
  -> plugin.getXWorkmateTaskSnapshot()
  -> exportXWorkmateArtifacts()
  -> bridge decorateOpenClawArtifactDownloadURLs()
  -> { artifacts: [{ relativePath, downloadUrl, sizeBytes, sha256 }] }
  -> APP 使用 Bearer bridge auth 下载
  -> APP 写入 $HOME/.xworkmate/threads/<thread>/...
  -> AssistantArtifactSnapshot.fileEntries
  -> iOS 分享/下载动作
```

关键协议原则：

1. `status=completed` 只代表任务终态，不能代表制品一定存在。
2. `artifacts` 清单是制品是否存在的权威来源；清单非空时，不能被 `artifactStatus=none` 或旧的 export 状态覆盖。
3. iOS 页面只展示已经进入 APP 本地 workspace 且被 `lastTaskArtifactRelativePaths` 登记的文件，不直接读取远端路径。

## 3. 根因（三轮排查结论）

### 3.1 iOS 专属回归：移动端强制 `requiresArtifactExport: true`（主因）

`b91294cd`（07-15 20:01，feat(ios): support artifact syncing）让移动端在 `chat.send` 与 `xworkmate.tasks.get` 两处无条件发送 `requiresArtifactExport: true`：

- `lib/runtime/go_task_service_client.dart`（chat.send 参数）
- `lib/runtime/runtime_models_runtime_payloads.dart` `toTaskGetParams()`

失效机制：

1. Bridge `normalizeOpenClawTaskGetResult` 对「completed + artifacts=[] + requiresArtifactExport」会把响应重写为 `status=running`（"waiting for artifact export"）。
2. 只要远端 export 为空（纯文本任务、或文件输出滞后/不在 task scope），iOS 永远等不到正常的 completed 收尾，持续轮询直到 `openClawArtifactSyncLimitReachedInternal` 超时，落 `partial`。
3. 桌面端不发送该标志，同样的空清单立即正常收尾；有清单则直接下载。时间线吻合：桌面成功同步发生在 19:05，回归提交在 20:01。

### 3.2 叠加缺陷：终态空清单后 App 断链

`applyGatewayChatResultInternal` 在成功终态但清单为空时会清除 `openClawTaskAssociation`；而后续补拉 `syncRemoteTaskArtifactsForSessionInternal` 依赖该 association（或从 `lastRemoteWorkingDirectory` 推断）。被清除后，该会话永远无法再发起带 runId 的 tasks.get——表现为"完成但永远没有制品入口"，手动刷新也无法恢复。

### 3.3 历史客户端问题（已在 `141ece2` 修复）

iOS 客户端曾在 `artifactStatus` 为 `none/exporting/failed` 时先于检查真实 `artifacts` 清单提前返回。`141ece2` 后以非空 manifest 为权威。

## 4. 已落地修复（PR #148，squash 进 main）

| 文件 | 修改 |
|---|---|
| `lib/runtime/runtime_models_runtime_payloads.dart` | `toTaskGetParams()` 只在 association 真带合同时发送 `requiresArtifactExport` |
| `lib/runtime/go_task_service_client.dart` | 删除 chat.send 的移动端强制标志 |
| `lib/app/app_controller_desktop_thread_actions.dart` | 成功终态即使清单为空也保留 association（校正为终态 status），给 `loadAssistantArtifactSnapshot` 留补拉路径 |
| `lib/features/mobile/mobile_assistant_page_composer.dart` | 清理 `_MobileAssistantSheetSection` 死代码（fatal analyze 警告曾卡住所有进 main 的 PR） |

设计取舍：association 保留后，移动端对"完成但无制品"的会话在页面打开期间会周期性发起 tasks.get（Bridge 终态缓存使其为内存回放）。短期以此换取制品可恢复性，后续可改为事件驱动。

skill 合同型任务（association 自带 `requiresArtifactExport` / `requiredArtifactExtensions`）行为不变。UI 未改动。

验证：`assistant_execution_target_test.dart` + `app_controller_thread_workspace_binding_test.dart` 共 109 用例通过；全仓 `flutter analyze` 零告警。（`records workspace files produced during an empty-artifact task run` 存在文件 mtime 竞态的存量 flake，与本修复无关。）

## 4.1 第四轮：真机在线联调定位到最终根因（2026-07-17）

前三轮修复(§3/§4)落地后,新任务在 iOS 上仍无制品卡片。通过「服务器侧直接调用
`xworkmate.tasks.get` + 真机 profile 模式实时日志」两端夹逼,得到决定性证据链：

1. **服务端链路当场验证健康**：对现场 run 直接调用 tasks.get,返回
   `status=completed + artifactCount=1 + 签名 downloadUrl`,文件确实在
   `tasks/<session>/<run>/` scope 内。断点 100% 在客户端。
2. **真机日志揭示第一层**：`[artifact-sync] bail: workspaceKind=remoteFs
   workspacePath=/owners/...`——iOS 上所有线程的 workspace 绑定都是
   remoteFs 兜底,而制品同步第一道守卫要求 localFs,**同步从未发起过**。
3. **真机日志揭示第二层（最终根因）**：`[thread-binding] localPath bail:
   empty base (home="")`——**iOS 应用进程没有 HOME 环境变量**,
   `resolveUserHomeDirectory()` 得到空串,`localThreadWorkspacePathInternal`
   永远返回空,绑定构建永远走 remoteFs 兜底分支。`a88ffb2` 只修了
   bootstrap 的 workspace root,线程绑定这条路径从未在 iOS 上工作过。

### 最终修复（三处,含桌面兼容设计）

| 文件 | 修改 | 桌面端影响 |
|---|---|---|
| `app_controller_desktop_core.dart` + `app_controller_desktop_settings_runtime.dart` | 新增 `mobileWorkspaceBaseDirectoryInternal`,`initializeInternal` 在**恢复线程之前**经 path_provider 解析应用 Documents 目录(仅 iOS/Android 且无 environmentOverride 时) | 无——桌面不进入该分支 |
| `app_controller_desktop_thread_binding.dart` | `threadWorkspaceHomeBaseInternal()`：移动端用 Documents 基准,桌面端保持 `$HOME`;显示路径移动端为 `$DOCUMENTS/.xworkmate/threads/<dir>` | 桌面路径与显示完全不变 |
| `app_controller_desktop_thread_storage.dart` | 线程恢复时迁移：`remoteFs + /owners/ 兜底路径 + app-owned` 且本地路径可用 → 迁回 localFs 并重建目录 | 桌面同样受益：历史上绑定失败的线程自愈;正常 localFs 线程不满足迁移条件,不受影响 |

配套：`mobile_assistant_page_core.dart` 的任务路径展示改用
`localThreadWorkspaceDisplayPathInternal()`(此前硬编码 `$HOME/...`,与真实
写入位置不符)。新增 host 可跑的迁移回归测试
`startup migrates owner-scoped remoteFs threads back to a local workspace`。

### 桌面兼容结论

- 桌面端(macOS/Windows/Linux)路径推导、显示、绑定行为**逐字节不变**
  (仅 `Platform.isIOS/isAndroid` 分支变化,host 全量测试 110 用例通过)。
- 迁移逻辑跨端生效但条件严格(owner-scoped remoteFs 兜底 + 本地可用),
  桌面只会修复历史坏绑定,不会触碰正常线程。
- `environmentOverride` 语义保留：测试注入的环境不受 path_provider 影响。

## 5. 服务端遗留项（尚未闭环）

1. **插件部署断裂**：`openclaw-multi-session-plugins` 统一流水线的 publish 阶段自 06-28 建立以来从未成功（发布所需的 npm 凭据在 CI 密钥源中缺失；npm 上仅有 2026-05-07 的 `0.1.8`）。`5c34a5f`（识别 completed 终态）已合入 main 但从未部署。需补齐发布凭据后 `workflow_dispatch` 重新发布部署。
2. **collect-and-snapshot 无调用方**：插件注册了 `xworkmate.artifacts.collect-and-snapshot`（把约定的临时输出目录内容复制进 `tasks/<session>/<run>/artifacts/`），但 App/Bridge 全链路无任何调用点。工具输出若落在临时目录而非 task scope，export 永远为空。候选修复：bridge 在 tasks.get 终态且 export 空集时先调一次 collect-and-snapshot 再重试 export。
3. **Bridge 终态缓存可固化空清单**：`requiresArtifactExport` 为 false 时，「completed+空清单」会被 per-session 终态缓存记住，此后同一 runId 永远回放空清单（内存缓存，bridge 重启才清）。若配合第 2 项修复，需同时评估缓存失效策略。
4. 部署修复后按 §6 采集清单重新验证同一 runId 的 tasks.get；采集前先重启 bridge 清缓存。

## 6. 现场采集清单（部署修复后执行）

### APP 真机

1. 记录 `appThreadKey`、`openclawSessionKey`、`runId`、`artifactScope`。
2. 记录 `lastArtifactSyncStatus` 变化：`syncing -> synced/no-artifacts/failed/download-failed/partial`。
3. 记录 `lastTaskArtifactRelativePaths` 是否为空。
4. 对照 APP 日志中的 `Remote artifact sync failed`、下载 HTTP 状态、校验失败信息。
5. 确认安装包含 PR #148 的构建。

### Bridge

1. 按同一 `runId` 记录 `xworkmate.tasks.get` 入参与最终响应（不记录 token）。
2. 记录 export 的 `artifactScope`、candidate count、warnings、artifact count。
3. 若有 manifest，记录每项 `relativePath/sizeBytes/contentType/downloadUrl path`；脱敏 query 中的签名值。
4. 对 APP 的下载请求记录 HTTP status、scope/path 解析结果与失败原因。

### OpenClaw/plugin

1. 在 `tasks/<safeSessionKey>/<safeRunId>/` 中确认最终文件是否存在。
2. 确认工具输出目录与 task scope 的关系，以及 snapshot 是否复制。
3. 对照 `expectedArtifactDirs` 与真实输出目录。
4. 检查 artifact ignore 规则未误过滤最终交付物。

## 7. 验收标准

- OpenClaw `xworkmate.tasks.get` 返回 `status=completed`。
- 同一 `runId` 响应返回 `artifacts[]`，每项有安全 `relativePath` 与可访问的 signed `downloadUrl`。
- Bridge download endpoint 返回 200，并验证 scope/path/signature。
- iOS 本地线程目录出现对应文件，`lastTaskArtifactRelativePaths` 非空。
- `lastArtifactSyncStatus=synced` 或有明确 `partial` 原因。
- iOS 会话页面显示真实制品，点击后能分享/下载。
- 任务 lifecycle 已完成，不因制品延迟或空清单永久停留 `running`。

## 8. 安全边界

- 本文不记录任何 token、Cookie、签名完整 URL、账号口令或密钥存储路径。
- 调试日志只保留 session/run/path/status/count，签名 query 参数必须脱敏。
- 不允许为了让 APP 显示制品而扫描整个远端 workspace 或放宽跨 host 下载；必须保持 task scope 和 Bridge signed URL 边界。
- 本仓库为公开仓库：任务/案例文档入库前必须完成上述脱敏。
