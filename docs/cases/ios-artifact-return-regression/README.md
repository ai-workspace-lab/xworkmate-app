# iOS 制品返回回归 case（工作区绑定 + requiresArtifactExport）

这个 case 固化「iOS 任务完成后拿不到制品、桌面端同链路正常」的回归现象与验收路径。2026-07-17 真机在线联调确认这是**叠加的两层缺陷**：底层是 iOS 工作区绑定从未成立（制品同步被静默跳过），表层是移动端强制 `requiresArtifactExport` 扭曲了 Bridge 终态语义。

- 交接与排查记录：[docs/tasks/2026-07-16-openclaw-ios-artifact-return-handoff.md](../../tasks/2026-07-16-openclaw-ios-artifact-return-handoff.md)
- 修复 PR：[#148](https://github.com/ai-workspace-lab/xworkmate-app/pull/148)
- 相关提交：`b91294cd`（强制标志回归）、`a88ffb2`（只修了 bootstrap root、未覆盖线程绑定）

## 现象

- iOS 真机：任务正文完成，但会话页面始终无制品卡片；旧版最终落 `partial`（"artifact 同步已超时"），新版正常完成但静默无卡片。
- 桌面端：同一 bridge/plugin 链路正常返回制品并本地落盘（对照组 `draft-1784089143304708-1`，6 个 markdown 成功同步）。
- 服务器侧直接调用 `xworkmate.tasks.get` 返回完整签名 manifest——断点在客户端。

## 根因机制（两层）

### 底层：iOS 线程工作区绑定从未成立（主因）

1. **iOS 应用进程没有 HOME 环境变量**，`resolveUserHomeDirectory()` 返回空串（真机日志：`[thread-binding] localPath bail: empty base (home="")`）。
2. `localThreadWorkspacePathInternal` 因此永远返回空，`buildDesktopWorkspaceBindingInternal` 永远走 owner-scoped **remoteFs 兜底**分支。
3. 制品同步（`syncRemoteTaskArtifactsForSessionInternal` / `persistGoTaskArtifactsForSessionInternal`）第一道守卫要求 `WorkspaceKind.localFs`——**iOS 上同步从未发起过**，与服务端状态无关。

### 表层：移动端强制 requiresArtifactExport（放大症状）

1. 移动端在 `chat.send` 与 `xworkmate.tasks.get` 中无条件发送 `requiresArtifactExport: true`（桌面端不发送）。
2. Bridge 对「completed + `artifacts=[]` + requiresArtifactExport」会把响应重写为 `status=running`，App 永远收不到"完成但无制品"的正常终态，轮询至上限后以 `partial` 收尾。
3. 叠加缺陷：终态空清单会清除 `openClawTaskAssociation`，此后无法再发起带 runId 的补拉。

## 修复不变量（回归断言的语义）

- **移动端线程工作区必须落在应用 Documents 下**（path_provider 解析，`initializeInternal` 在恢复线程前完成），不依赖 HOME 环境变量；桌面端保持 `$HOME/.xworkmate/threads/` 不变。
- **owner-scoped remoteFs 只是兜底态**：线程恢复时若本地路径可用，必须迁回 localFs（跨端生效，桌面历史坏绑定同样自愈）。
- 平台不改变任务查询语义：`requiresArtifactExport` 只能来自任务合同（association），不允许按平台强制。
- 成功终态即使制品清单为空，也必须保留 association（校正为终态 status），使 `loadAssistantArtifactSnapshot` 保有补拉能力。
- 非空 manifest 是权威：不被旧 `artifactStatus` 提前截断（`141ece2` 语义）。
- skill 合同型任务（association 自带 `requiresArtifactExport` / `requiredArtifactExtensions`）保持等待/轮询直至清单满足或超时。

## 自动化落点

| 仓库 | 文件 | 覆盖点 |
| --- | --- | --- |
| `xworkmate-app` | `test/runtime/app_controller_thread_workspace_binding_test.dart` | `startup migrates owner-scoped remoteFs threads back to a local workspace`：remoteFs 兜底绑定在本地可用时迁回 localFs 并重建目录 |
| `xworkmate-app` | `test/runtime/assistant_execution_target_test.dart` | `toTaskGetParams()` 的字段契约：session mapping 键、artifactScope/Directory 透传；不含平台强制字段 |
| `xworkmate-app` | `test/runtime/app_controller_thread_workspace_binding_test.dart` | 制品下载/鉴权/scope/超时/校验失败、空清单收尾与 `lastArtifactSyncStatus` 状态机 |

## 真机验收清单

1. 用会产出文件的任务（如「采集最新 AI 资讯，保存在 md 文件」）在 iOS 真机执行：
   - 任务完成后会话页面出现真实制品卡片，可预览/分享；
   - `lastArtifactSyncStatus=synced`，`lastTaskArtifactRelativePaths` 非空。
2. 用纯文本任务（无文件产出）执行：
   - 任务正常收尾为完成态，不出现"artifact 同步已超时"；
   - 不永久停留 `running`。
3. 修复前创建的旧会话（曾被持久化为 remoteFs 兜底绑定）：重启 APP 后打开该会话，制品能被补拉并出现卡片（迁移生效）。
4. 桌面端跑相同两类任务，行为与 iOS 一致（同一任务查询语义），且桌面线程目录仍为 `$HOME/.xworkmate/threads/`。

## 已知边界

- 若远端 export 确实为空（产物未进入 `tasks/<session>/<run>/` scope），任何客户端都无法拿到制品；该问题属于服务端链路（见交接文档 §5 遗留项），不在本 case 的客户端断言范围内。
