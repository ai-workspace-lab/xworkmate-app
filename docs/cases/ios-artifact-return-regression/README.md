# iOS 制品返回回归 case（requiresArtifactExport 强制标志）

这个 case 固化「iOS 任务完成后拿不到制品、桌面端同链路正常」的回归现象与验收路径，用于防止移动端再次引入与桌面端不一致的任务查询语义。

- 交接与排查记录：[docs/tasks/2026-07-16-openclaw-ios-artifact-return-handoff.md](../../tasks/2026-07-16-openclaw-ios-artifact-return-handoff.md)
- 修复 PR：[#148](https://github.com/ai-workspace-lab/xworkmate-app/pull/148)
- 引入回归的提交：`b91294cd`（feat(ios): support artifact syncing）

## 现象

- iOS 真机：任务正文完成，但会话页面始终无制品卡片；最终落 `partial`（"artifact 同步已超时"）。
- 桌面端：同一 bridge/plugin 链路正常返回制品并本地落盘（对照组 `draft-1784089143304708-1`，6 个 markdown 成功同步）。

## 根因机制

1. 移动端在 `chat.send` 与 `xworkmate.tasks.get` 中无条件发送 `requiresArtifactExport: true`（桌面端不发送）。
2. Bridge 对「completed + `artifacts=[]` + requiresArtifactExport」会把响应重写为 `status=running`（等待 export），App 因此永远收不到"完成但无制品"的正常终态。
3. 远端 export 为空（纯文本任务、文件滞后、或产物不在 task scope）时，iOS 轮询至上限后以 `partial` 收尾。
4. 叠加缺陷：终态空清单会清除 `openClawTaskAssociation`，之后该会话无法再发起带 runId 的补拉，手动刷新也无法恢复。

## 修复不变量（回归断言的语义）

- 平台不改变任务查询语义：`requiresArtifactExport` 只能来自任务合同（association），不允许按平台强制。
- 成功终态即使制品清单为空，也必须保留 association（校正为终态 status），使 `loadAssistantArtifactSnapshot` 保有补拉能力。
- 非空 manifest 是权威：不被旧 `artifactStatus` 提前截断（`141ece2` 语义）。
- skill 合同型任务（association 自带 `requiresArtifactExport` / `requiredArtifactExtensions`）保持等待/轮询直至清单满足或超时。

## 自动化落点

| 仓库 | 文件 | 覆盖点 |
| --- | --- | --- |
| `xworkmate-app` | `test/runtime/assistant_execution_target_test.dart` | `toTaskGetParams()` 的字段契约：session mapping 键、artifactScope/Directory 透传；不含平台强制字段 |
| `xworkmate-app` | `test/runtime/app_controller_thread_workspace_binding_test.dart` | 制品下载/鉴权/scope/超时/校验失败、空清单收尾与 `lastArtifactSyncStatus` 状态机 |

## 真机验收清单

1. 用会产出文件的任务（如「采集最新 AI 资讯，保存在 md 文件」）在 iOS 真机执行：
   - 任务完成后会话页面出现真实制品卡片，可预览/分享；
   - `lastArtifactSyncStatus=synced`，`lastTaskArtifactRelativePaths` 非空。
2. 用纯文本任务（无文件产出）执行：
   - 任务正常收尾为完成态，不出现"artifact 同步已超时"；
   - 不永久停留 `running`。
3. 桌面端跑相同两类任务，行为与 iOS 一致（同一任务查询语义）。

## 已知边界

- 若远端 export 确实为空（产物未进入 `tasks/<session>/<run>/` scope），任何客户端都无法拿到制品；该问题属于服务端链路（见交接文档 §5 遗留项），不在本 case 的客户端断言范围内。
