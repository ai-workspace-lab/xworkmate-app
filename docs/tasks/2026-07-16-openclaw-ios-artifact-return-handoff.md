# OpenClaw iOS 制品返回问题交接记录

> 日期：2026-07-16（Asia/Shanghai）  
> 范围：`iOS APP -> xworkmate-bridge -> OpenClaw -> openclaw-multi-session-plugins`  
> 目标：任务显示完成后，必须仍能返回并下载真实制品；UI 不变。

## 1. 现场现象

### 用户可见现象

- iOS 真机显示任务正文已经完成。
- 页面没有可用的制品返回或下载入口。
- 本次截图显示的是“会话”页面，正文包含资讯报告内容，底部输入框可用；没有看到制品卡片。
- 任务状态与制品状态必须分开判断：OpenClaw 文本完成，不等于 `artifacts.items` 已返回，也不等于文件已同步到 iOS 本地线程目录。

### 相关任务标识

当前现场网页地址：

```text
https://openclaw.svc.plus/chat?session=agent%3Amain%3Adraft%3A1784107717459614-1
```

解码后的 OpenClaw session key：

```text
agent:main:draft:1784107717459614-1
```

对应的 app thread key 应按协议记录为：

```text
draft:1784107717459614-1
```

本地线程目录命名规则示例：

```text
$HOME/.xworkmate/threads/draft-1784107717459614-1
```

历史调试中还出现过：

```text
$HOME/.xworkmate/threads/draft-1784089143304708-1
```

注意：`runId`、`turnId`、`artifactScope` 不能从截图推断，必须从 APP 的 `xworkmate.tasks.get` 请求和 Bridge/OpenClaw 响应中采集。禁止用 session key 猜 run ID。

## 2. 当前代码版本快照

以下是本次交接时本地工作区的仓库状态。分支可能不是远端生产分支，后续 Agent 必须先确认部署引用的 commit。

| 仓库 | 当前分支 | 当前 commit | 工作区状态 | 运行时相关性 |
|---|---|---|---|---|
| `xworkmate-app` | `main` | `141ece2` | clean；领先 `origin/main` 1 commit | iOS 状态机、远端任务查询、制品下载与本地同步 |
| `xworkmate-bridge` | `hotfix/release-pr-guard-backport` | `d87d954` | `.github/workflows/pipeline.yml` 有未提交修改 | ACP 路由、`xworkmate.tasks.get`、制品 URL 装饰与下载代理 |
| `openclaw-multi-session-plugins` | `hotfix/completed-task-status-20260715` | `5c34a5f` | clean | OpenClaw session 映射、任务终态、制品 scope/export |
| `xworkspace-console` | `fix/macos-postgres-compose-path` | `0205c37` | `scripts/setup-ai-workspace-all-in-one.sh` 有未提交修改 | 部署/运行时编排，不是当前制品协议的直接处理点 |
| `xworkspace-core-skills` | `feat/pptx-editable-reconstruction` | `c1de2fe` | 有两个未跟踪 skill 目录 | skill 输出目录约定和 `artifact-ignore` 规则 |

不要在交接过程中覆盖上述未提交改动。尤其是 `xworkmate-bridge` 与 `xworkspace-console` 的工作区修改属于其他工作流，先保留并单独判断归属。

## 3. 端到端数据链路

```text
iOS MobileAssistantConversation
  -> AppController.loadAssistantArtifactSnapshot()
  -> syncRemoteTaskArtifactsForSessionInternal()
  -> GoTaskServiceClient.getTask()
  -> ACP JSON-RPC: xworkmate.tasks.get
  -> xworkmate-bridge.handleTaskGet()
  -> OpenClaw gateway: xworkmate.tasks.get
  -> plugin.getXWorkmateTaskSnapshot()
  -> native task lookup / recorded task run lookup
  -> collect-and-snapshot (必要时)
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
3. OpenClaw 工具可能把文件写到 `~/.openclaw/media/` 或 `/tmp/openclaw/`；这些文件必须先被 collect-and-snapshot 复制到当前 `tasks/<session>/<run>/` scope，之后 export 才能发现。
4. iOS 页面只展示已经进入 APP 本地 workspace 且被 `lastTaskArtifactRelativePaths` 登记的文件，不直接读取远端路径。

## 4. 关键代码文件

### 4.1 xworkmate-app

| 文件 | 入口 | 作用 | 调试重点 |
|---|---|---|---|
| `lib/app/app_controller_desktop_thread_actions.dart` | `pollOpenClawTaskAssociationInternal()` | 轮询 `xworkmate.tasks.get`，区分 running/terminal/artifact-syncing | 记录原始 `result.status`、`result.artifacts.length`、`runId`、association status；确认 completed 是否被提前收尾 |
| `lib/app/app_controller_desktop_thread_actions.dart` | `applyGatewayChatResultInternal()` | 将最终文本、任务状态、association 和制品同步串起来 | 关注 `hasCurrentRunArtifacts`、`waitingForOpenClawArtifacts`、最终 `lifecycleStatus` |
| `lib/app/app_controller_desktop_runtime_helpers.dart` | `persistGoTaskArtifactsForSessionInternal()` | 下载/校验/写入制品，并登记 `lastTaskArtifactRelativePaths` | 先看 `result.artifacts`；再看 `downloadUrl`、鉴权、sha256/size 校验、ignore policy 和最终 sync status |
| `lib/app/app_controller_desktop_runtime_helpers.dart` | `_artifactBytesResultInternal()` | 支持 inline content 或 Bridge signed URL 下载 | 远端 URL 必须是 Bridge host 或带 signed path；缺 auth、跨 host、HTTP 非 200、校验失败都会导致制品不落盘 |
| `lib/app/app_controller_desktop_thread_sessions.dart` | `loadAssistantArtifactSnapshot()` | iOS/桌面加载本地 snapshot，必要时触发远程补拉 | `snapshot.fileEntries` 为空时是否进入 `syncRemoteTaskArtifactsForSessionInternal()` |
| `lib/app/app_controller_desktop_thread_sessions.dart` | `syncRemoteTaskArtifactsForSessionInternal()` | 使用 association 再次查询任务并同步远端制品 | 当前代码在 `result.artifacts.isEmpty` 时直接返回，需确认远端是否真的返回清单 |
| `lib/runtime/go_task_service_client.dart` | `GoTaskServiceArtifact.fromJson()` / `GoTaskServiceResult.artifacts` | 将 `artifacts/items/files/attachments` 解析为 APP 模型 | 检查响应嵌套层级、`relativePath`、`downloadUrl` 是否在解析后仍存在 |
| `lib/features/mobile/mobile_assistant_page_conversation.dart` | `_MobileSessionArtifacts` | 轮询 snapshot 并展示真实文件卡片 | 这里不是制品来源；若 `_snapshot.fileEntries` 为空，UI 不会凭空生成制品 |
| `lib/runtime/runtime_models_runtime_payloads.dart` | `OpenClawTaskAssociation` | 保存 session/run/scope/status/required extensions | 检查 `openclawSessionKey`、`runId`、`artifactScope` 是否同一轮一致 |
| `test/runtime/app_controller_thread_workspace_binding_test.dart` | Bridge URL 与 OpenClaw artifact tests | 覆盖下载、鉴权、scope、超时、校验失败 | 优先复用这些 fixture 对照现场响应 |

已合并的 APP 修复：

- `a88ffb2`：移动端 workspace path 指向 app documents，解决 iOS 本地写入路径问题。
- `141ece2`：当制品清单非空时，以 manifest 为权威，不再被 `artifactStatus` 的旧值提前截断；新增 signed OpenClaw URL 回归测试。

### 4.2 xworkmate-bridge

| 文件 | 入口 | 作用 | 调试重点 |
|---|---|---|---|
| `internal/acp/rpc_handler.go` | `handleTaskGet()` | 接收 APP 的 `xworkmate.tasks.get` 并转发 OpenClaw | 是否收到正确的 `appThreadKey/openclawSessionKey/runId/includeArtifacts` |
| `internal/acp/orchestrator.go` | `handleTaskGet` 相关路径 | 查询 OpenClaw、触发 artifact export、规范化结果 | `mergeOpenClawTaskGetArtifact()` 是否执行；最终 payload 是否有 artifacts |
| `internal/acp/orchestrator.go` | `decorateOpenClawArtifactDownloadURLs()` | 给每个 artifact 写入 Bridge signed `downloadUrl` | URL 的 host、path、session key、run ID、relative path、sig 是否完整 |
| `internal/acp/openclaw_artifact_download.go` | `HandleOpenClawArtifactDownload()` | 校验签名并从 OpenClaw task scope 读取文件 | APP 请求是否到达；Authorization、sig、scope/path 校验是否成功 |
| `internal/acp/routing_test.go` | OpenClaw artifact routing tests | 覆盖 URL 装饰、scope、fallback、export | 现场响应应与这些测试中的最终 shape 一致 |
| `internal/acp/web_contract_test.go` | `xworkmate.tasks.get` contract | 覆盖 ACP Web 请求 shape | 对照 APP 真机请求字段 |

### 4.3 openclaw-multi-session-plugins

| 文件 | 入口 | 作用 | 调试重点 |
|---|---|---|---|
| `src/taskState.ts` | `getXWorkmateTaskSnapshot()` | 通过 mapping 找 session，再找 native task 或 durable run | `mapping_not_found`、native task 缺失、recorded run 与 artifact export 是否组合返回 |
| `src/taskState.ts` | `exportArtifactsForTaskLookup()` | 用当前 session/run 调用 export | 传入的 `openclawSessionKey/runId/artifactScope/expectedArtifactDirs` 是否正确 |
| `src/taskState.ts` | durable task run read/write | 记录 `running/completed/failed` | `agent_end` 是否写入真实 output；不能用终态记录替代空制品 |
| `src/exportArtifacts.ts` | `exportXWorkmateArtifacts()` | 扫描 task scope、expected dirs、读取文件、生成 manifest | scope 是否已准备；文件是否实际位于 `tasks/<session>/<run>`；是否被 ignore、size、symlink 规则过滤 |
| `src/expectedArtifactDirs.ts` | `normalizeExpectedArtifactDirs()` | 约束 expected artifact directory | expected dirs 必须是 workspace 内相对目录，不能是 `/tmp` 或绝对路径 |
| `src/exportArtifacts.test.ts` | export tests | 覆盖 scope、expected dirs、ignore、签名 manifest | 用于判断“任务完成但 artifacts=[]”是 export 空集还是 Bridge 丢字段 |
| `src/taskState.test.ts` | task snapshot tests | 覆盖 durable run/native task/terminal source | 对照 `terminalSource`、`artifactCount`、`warnings` |

### 4.4 xworkspace-console / xworkspace-core-skills

这两个仓库不是当前 APP 到 Bridge 的直接 RPC 处理点，但不能忽略：

- `xworkspace-console/docs/en/RUNTIME_DELIVERY_PLAN.md`：部署面、Bridge/OpenClaw 公网入口和 release 对齐记录。
- `xworkspace-console/api/portal_services.go`：服务发现/控制台服务目录，不负责制品 manifest。
- `xworkspace-console/api/metric_probe.go`：可用于确认 bridge/openclaw 进程和健康状态。
- `xworkspace-core-skills/skills/artifact-ignore.md`：全局 artifact ignore/reject 规则；会影响 APP 最终看到的文件集合。
- `xworkspace-core-skills/skills/video-production/it-infra-evolution-video-v2/SKILL.md`：强制最终输出位于当前 task artifact scope，且只把最终 MP4 作为用户制品。
- `xworkspace-core-skills/docs/operations/vault-github-actions-2026-06-06.md`：记录各仓库发布与密钥注入约定；调试时不得把 token 写入日志或文档。

## 5. 当前根因判断

### 已确认并已修复的客户端问题

此前 iOS 客户端有移动平台分支：当 `artifactStatus` 为 `none/exporting/failed` 时，在检查真实 `artifacts` 清单之前提前返回。若 OpenClaw/Bridge 返回旧状态同时带有非空 signed artifact manifest，APP 会跳过下载，最终没有本地制品。

该问题已在 `141ece2` 修复：只有 `artifacts.isEmpty` 时才解释 `artifactStatus`；非空 manifest 优先进入下载流程。UI 未修改。

### 当前截图仍显示无制品时，优先验证远端是否返回空清单

若真机已经安装 `141ece2` 生成的 IPA，下一优先级不是继续改 UI，而是完整记录同一次 `xworkmate.tasks.get`：

```text
request:
  appThreadKey
  openclawSessionKey
  runId
  includeArtifacts=true
  artifactScope/artifactDirectory

response:
  status/taskStatus/terminal
  message/output/resultSummary
  artifactStatus
  artifactCount
  artifacts[]
  warnings[]
  artifactScope
  remoteWorkingDirectory
  missingRequiredExtensions
```

判断矩阵：

| 现场响应 | 结论方向 |
|---|---|
| `status=completed` 且 `artifacts=[]`，`warnings` 指 scope 未准备/无候选 | OpenClaw/plugin export 或产物写入路径问题 |
| `status=completed` 且 `artifacts=[]`，但任务声称生成文件 | 重点检查工具输出是否落在 `~/.openclaw/media`、`/tmp/openclaw`，以及 collect-and-snapshot 是否执行 |
| `status=completed` 且 `artifacts` 非空，APP 本地仍无文件 | 重点检查 Bridge URL、Bearer、host allowlist、HTTP 响应、size/sha256 校验、iOS workspace 写入 |
| Bridge 日志有 artifacts，APP 解析后为 0 | 检查 `GoTaskServiceResult._firstGoTaskArtifactList()` 的响应嵌套层级或 Bridge 返回 shape |
| `mapping_not_found` / `no_native_task_record` | 检查 appThreadKey、OpenClaw session key、runId 三元组，不要用 message 文本或历史目录猜测 |
| `artifactCount>0` 但 `downloadUrl` 缺失 | Bridge 的 manifest decoration 或部署版本不一致 |

## 6. 下一轮调试采集清单

### APP 真机

1. 打开任务 ID 详情，记录 `appThreadKey`、`openclawSessionKey`、`runId`、`artifactScope`。
2. 记录 `lastArtifactSyncStatus` 的变化：`syncing -> synced/no-artifacts/failed/download-failed/partial`。
3. 记录 `lastTaskArtifactRelativePaths` 是否为空。
4. 对照 APP 日志中的 `Remote artifact sync failed`、下载 HTTP 状态、校验失败信息。
5. 确认当前 IPA 的 bundle id 为 `plus.svc.xworkmate`，且安装包来自包含 `141ece2` 的工作区。

### Bridge

1. 按同一个 `runId` 记录 `xworkmate.tasks.get` 入参和最终响应，不记录 token。
2. 确认是否调用了 `xworkmate.artifacts.collect-and-snapshot` / `xworkmate.artifacts.export`。
3. 记录 export 的 `artifactScope`、candidate count、warnings、artifact count。
4. 若有 manifest，记录每个 artifact 的 `relativePath/sizeBytes/contentType/downloadUrl path`；脱敏 query 中的签名值。
5. 对 APP 发起的 download URL 记录 HTTP status、scope/path 解析结果和失败原因。

### OpenClaw/plugin

1. 在 `tasks/<safeSessionKey>/<safeRunId>/` 中确认最终文件是否存在。
2. 确认工具输出是否来自 `~/.openclaw/media/` 或 `/tmp/openclaw/`，并确认 snapshot 是否复制。
3. 对照 `expectedArtifactDirs` 与真实输出目录，确认没有把 app owner path 当成 OpenClaw workspace root。
4. 检查 `agent_end` 是否写入 `completed`，但不要把 durable terminal record 当作 artifact manifest。
5. 检查 `artifact-ignore.md` 是否误过滤最终文件；ignore 规则只能过滤中间文件，不能删除真实最终交付物。

## 7. 交接验收标准

本问题只有同时满足以下条件才算闭环：

- OpenClaw `xworkmate.tasks.get` 返回 `status=completed`。
- 同一个 `runId` 的响应返回 `artifacts[]`，每项有安全的 `relativePath` 和可访问的 signed `downloadUrl`。
- Bridge download endpoint 返回 200，并验证 scope/path/signature。
- iOS 本地线程目录出现对应文件，`lastTaskArtifactRelativePaths` 非空。
- `lastArtifactSyncStatus=synced` 或有明确 `partial` 原因。
- iOS 会话页面显示真实制品，点击后能分享/下载；不能依赖硬编码“任务结果.md”。
- 任务 lifecycle 已完成，不因为制品延迟或空清单永久停留 `running`。

## 8. 安全边界

- 本文不记录 Bridge token、Gateway token、Cookie、签名完整 URL 或用户凭据。
- 调试日志只保留 session/run/path/status/count，签名 query 参数必须脱敏。
- 不允许为了让 APP 显示制品而扫描整个远端 workspace 或放宽跨 host 下载；必须保持 task scope 和 Bridge signed URL 边界。
