# OpenClaw iOS 制品返回问题交接记录

> 日期：2026-07-16 起（Asia/Shanghai），末次更新 2026-07-18
> 范围：`iOS APP -> xworkmate-bridge -> OpenClaw -> openclaw-multi-session-plugins`
> 目标：任务显示完成后，必须仍能返回并下载真实制品；UI 不变。
> 状态：**四轮排查全部闭环：#148/#150（第三轮）、#153/#154（第四轮）均已合并。客户端链路修复完成，待真机端到端验收。服务端遗留项见 §5（07-18 更新）；全局媒体作用域根治项另立 case：[openclaw-task-scoped-media-artifacts](../cases/openclaw-task-scoped-media-artifacts.md)。**
> 长期回归 case：[docs/cases/ios-artifact-return-regression/](../cases/ios-artifact-return-regression/README.md)
>
> 本文为可入库的脱敏版；涉及部署凭据与密钥存储的细节仅保留在维护者本地记录中，不入公开仓库。

## 0. 任务进度总览

### 0.1 时间线（四轮排查 + 延伸）

| 轮次 | 日期 | 结论 | 交付 |
|---|---|---|---|
| 第一轮 | 07-15 | iOS 任务卡在「执行中」——内存 association 停滞在 running，`hasAssistantPendingRun` 永真。修复：`applyGatewayChatResultInternal` 收尾时回传含终态的 association | 已合并（早于本记录） |
| 第二轮 | 07-16 | 代码审查发现：插件部署流水线从未成功发布、`collect-and-snapshot` 无调用方、Bridge 终态缓存可固化空清单、App 侧终态清 association 断链（§5 服务端遗留 + §3.2） | 判断记录入库 |
| 第三轮 | 07-16 | 定位 iOS 专属回归：移动端无条件强制 `requiresArtifactExport`，把 Bridge 终态语义扭成「永远等 export」（§3.1）。修复：去除强制标志 + 终态保留 association | **PR #148 已合并 main、PR #150 已合并 release/v1.1** |
| 第四轮 | 07-17 | 真机在线联调（服务器直调 tasks.get + profile 实时日志）定位最终根因：**iOS 进程无 HOME 环境变量**，线程工作区绑定永远回退 remoteFs，制品同步的 localFs 守卫从未通过（§4.1）。修复：Documents 目录基准 + 旧绑定迁移 | **PR #153 已合并 main、PR #154 已合并 release/v1.1** |
| 延伸（第五轮） | 07-18 | 客户端链路闭环后，控制台暴露服务端边界问题：最终回复 `MEDIA:` 引用全局媒体缓存，Control UI 拒绝读取（`Outside allowed folders`）。Bridge 终态补偿 `2e5c5b6` 已部署；根治需 OpenClaw 发送前载荷改写 hook | 另立 case 跟进：[openclaw-task-scoped-media-artifacts](../cases/openclaw-task-scoped-media-artifacts.md) |
| 第六轮 | 07-18 | iOS 退出重启后本地会话丢失：`threads.json` 加载对单条无效记录（legacy `auto` 执行模式 / 不完整 workspaceBinding / 损坏数据）一票否决——`TaskThread.fromJson` 抛错被整表 try 捕获后按空表处理，后续任何保存把空表写回即永久丢失；`SkippedTaskThreadRecord` 启动告警机制此前从未接线。修复：逐条容错加载 + 接线启动告警 + 恢复前备份原件 `threads.json.invalid-<ts>.bak` | 本分支 `251ee01`，PR → main 待开 |

### 0.2 PR 全景

| PR | 方向 | 内容 | 状态 |
|---|---|---|---|
| [#148](https://github.com/ai-workspace-lab/xworkmate-app/pull/148) | → `main` | 第一~三轮修复：强制标志移除、终态保留 association、`141ece2` 签名制品权威、死代码清理 | ✅ 已合并（`7095e1a`） |
| [#149](https://github.com/ai-workspace-lab/xworkmate-app/pull/149) | → `main` | 项目开发规范转 Claude Code 技能 `.claude/skills/project-development-standard` | ✅ 已合并（`b06f505`） |
| [#150](https://github.com/ai-workspace-lab/xworkmate-app/pull/150) | → `release/v1.1` | #148 的 backport | ✅ 已合并（`79e9b6f`） |
| [#153](https://github.com/ai-workspace-lab/xworkmate-app/pull/153) | → `main` | 第四轮：HOME 缺失根因修复 + 加固（association 兜底、404/410 视为 gone、partial 30s 冷却）+ 文档 | ✅ 已合并（squash `8555bd3`，07-17） |
| [#154](https://github.com/ai-workspace-lab/xworkmate-app/pull/154) | → `release/v1.1` | #153 的 backport | ✅ 已合并（`6ad98fc`，07-17） |

> #153 的历史：原分支在 #148 squash 合并后与 main 对撞冲突，已重建为 `origin/main + 两个干净提交`（`b7d93fe` 加固、`cb55997` HOME 根因修复），force-push 后无冲突。
>
> 2026-07-18 注意：`main` 上的本文档曾被旧版覆盖——`00b7b0d`（07-16 旧快照）经 merge `49a01fa` 于 07-18 进入 main，回退了 `8555bd3` 落地的本记录。本次提交恢复并续写；追溯旧版内容以 git 历史为准。

### 0.3 待办

- [x] 合并 #153（squash 进 main，`8555bd3`）、#154（进 release/v1.1，`6ad98fc`）——07-17 完成。
- [ ] **真机端到端验收**：全新 release 版跑产文件任务 → 制品卡片出现、可预览/分享（见 §7 与 case 验收清单）。
- [ ] 轮换测试账号 `review@svc.plus` 口令（历史提交含明文，最紧急）。
- [ ] 服务端遗留项（§5，07-18 更新）：确认插件 npm 发布凭据闭环；评估 Bridge 终态缓存失效策略；跟进 OpenClaw 发送前改写 hook 根治项（另立 case）。
- [ ] CI 基建（非阻塞、可选）：补 Mac App Distribution 证书修 `Build macos dmg`；`validate-release-pr.yml` 每次 push 的 0 秒 startup failure（已另派任务卡片）。
- [ ] 会话存储演进（第六轮结论）：暂不引入 SQLite——跨五端新增原生依赖与迁移成本大于当前单写者模型的收益；下一步优先「分线程文件」（`StoreLayout.taskFileForSessionKey` 已预留）消除整表重写放大，消息规模继续增长后再评估 sqflite 单表（threadId, json, updatedAtMs）方案。

### 0.4 忽略项（经确认）

- Xcode Cloud 两项检查（`XWorkmate | Default` / `Archive - macOS`）：签名基建问题，按可选处理。
- `Build macos dmg`：CI 缺 Mac App Distribution 证书，与代码无关。

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

## 4.1 第四轮：真机在线联调定位到最终根因（2026-07-17，PR #153/#154，已合并）

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

## 5. 服务端遗留项（2026-07-18 更新）

1. **插件部署断裂 → 部分闭环**：线上已运行 `openclaw-multi-session-plugins 2026.6.2`（enabled，安装源 `global:openclaw-multi-session-plugins/dist/index.js`，07-18 核验）。统一流水线 publish 阶段的 npm 凭据缺失问题是否已补齐仍未确认；在 CI publish 闭环前，部署依赖手工安装路径。
2. **collect-and-snapshot 无调用方 → 已闭环**：Bridge `2e5c5b6`（`fix(acp): collect terminal artifacts before export retry`）已部署（ubuntu 用户服务，active）。首次 `xworkmate.artifacts.export` 为空时，Bridge 调用 `xworkmate.artifacts.collect-and-snapshot` 后重试 export，补齐 iOS/Desktop 的制品回传。
3. **Bridge 终态缓存可固化空清单**：`requiresArtifactExport` 为 false 时，「completed+空清单」仍会被 per-session 终态缓存记住（内存缓存，bridge 重启才清）。第 2 项重试链路上线后需重新评估缓存失效策略；07-18 复现会话（`agent:main:draft:1784354131167918-3`）截止检查时尚未观察到终态 export 日志，两条验证线见 case「最新复现状态」。
4. **新根治项（OpenClaw 运行时）**：客户端与 Bridge 闭环后，控制台仍会对最终回复中的全局媒体路径显示 `Outside allowed folders`——终态补偿发生在任务终态后，无法改写已发送的网页 `MEDIA:` 引用。根治需 OpenClaw 提供发送前载荷改写 hook（线上 `2026.6.1` 不支持），完整分析、边界不变量与验收矩阵见 [docs/cases/openclaw-task-scoped-media-artifacts.md](../cases/openclaw-task-scoped-media-artifacts.md)。
5. 部署修复后按 §6 采集清单重新验证同一 runId 的 tasks.get；采集前先重启 bridge 清缓存。

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
