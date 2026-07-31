# 对话插件 × GitHub API 发布连接器实施与交接计划

更新时间：2026-07-31

工作仓库：`xworkmate-app`

工作分支：`agent/github-plugin-publish`

基线：本地 `main@e25b5662`，远端 `origin/main@d51cda23`

关联规划：[PR #211](https://github.com/ai-workspace-lab/xworkmate-app/pull/211)

## 一、最终目标

在对话页面建立一条可扩展、显式选择的执行链：

```text
当前对话
  ├─ 可选：对话插件
  │    └─ Harness Workflow（首个实现；后续承载技能选择与使用规则）
  └─ 可选：发布连接器
       ├─ 不发布
       └─ GitHub API（首个实现）
```

两个选择相互独立：

- 用户可以只运行 Harness Workflow，结果保留在当前任务线程，不向外发布。
- 用户可以不运行插件，直接把原始对话快照发布到 GitHub。
- 用户可以先运行 Harness Workflow，再把完成后的对话快照发布到 GitHub。
- 未显式选择 GitHub API 时，绝不发送 GitHub 网络请求。

商店版是当前优先级：GitHub 发布只能通过 HTTPS REST API 完成，不启动 `git`、`ssh`、shell 或其他外部进程。

## 二、已经确认的产品决策

1. 设置 → 连接器中的 GitHub 不是“本地可用”静态状态，必须点击“连接”并完成输入与验证。
2. 本地/自托管工作空间也不是默认已连接；沿用“自托管工作空间”的显式连接交互。
3. 对话页不应只有一个写死的“发布到 GitHub”按钮；入口应打开“对话工作流”对话框。
4. “对话插件”和“发布连接器”是两类能力，不合并为同一个枚举或同一个设置。
5. 首版对话插件只有 `Harness Workflow`，但模型必须允许以后增加插件、技能和规则。
6. 首版发布连接器只有 `GitHub API`，并提供“不发布”；以后可增加其他连接器。
7. GitHub token 只进入安全存储，配置快照只保存 token 引用。

## 三、关联 PR 与现状

- PR #211 规划了 Harness delivery-target 模型。
- 该模型的等价实现已随 PR #218 合入主干，当前已有：
  - `HarnessTarget`
  - `HarnessRepoBinding`
  - `HarnessEnvironment`
  - `renderHarnessDeliveryContextBlock(...)`
  - `SettingsSnapshot.harnessTargets`
- 当前分支已有一版 GitHub API 底层能力和“直接发布”原型，但直接发布 UI 不符合最新产品决策，需要在提交前重构为选择式对话框。

## 四、建议的数据模型

### 4.1 对话插件

新增轻量描述模型，建议放在 `lib/features/plugins/conversation_plugin.dart`：

```dart
enum ConversationPluginId {
  harnessWorkflow,
}

class ConversationPluginSelection {
  final ConversationPluginId? pluginId; // null = 不运行插件
  final String harnessTargetId;          // Harness 时必填
}
```

首版不要把 GitHub 连接器塞进插件模型。插件只负责如何处理对话：

- `Harness Workflow` 根据 `harnessTargetId` 找到 `SettingsSnapshot.harnessTargets`。
- 使用 `renderHarnessDeliveryContextBlock(target)` 生成严格的目标范围。
- 技能选择与使用规则以后作为插件描述/规则字段扩展，不改变发布连接器接口。

### 4.2 发布连接器

新增与插件独立的发布目标描述，建议放在
`lib/features/connectors/conversation_publish_connector.dart`：

```dart
enum ConversationPublishConnectorId {
  githubApi,
}

class ConversationPublishSelection {
  final ConversationPublishConnectorId? connectorId; // null = 不发布
}
```

首版连接器的实际配置继续使用
`GitHubRepositoryConnectorConfig`：

- `repository`
- `branch`
- `publishPath`
- `tokenRef`
- `connected`

token 本身不得出现在该对象的 JSON 中。

### 4.3 一次执行请求

建议增加只存在于内存中的请求对象：

```dart
class ConversationWorkflowRequest {
  final ConversationPluginSelection plugin;
  final ConversationPublishSelection publisher;
}
```

它的职责是表达一次用户确认的选择，不作为长期凭据存储。

## 五、对话框交互设计

### 5.1 入口

- 将当前顶部“发布到 GitHub”原型改为“对话工作流”。
- Key 建议：`assistant-conversation-workflow-button`。
- 仅在当前平台支持相关 feature 时显示。

### 5.2 对话框字段

对话框建议标题：“运行对话工作流”。

第一组“对话插件”：

- `不使用插件`
- `Harness Workflow`

选择 Harness 后显示“交付目标”下拉框：

- 数据来自 `settings.harnessTargets`。
- 只展示有效 target。
- 没有 target 时显示明确空状态，并提供“前往设置 → 插件”的入口。
- 未选择 target 时禁用“运行”。

第二组“发布连接器”：

- `不发布`
- `GitHub API`

GitHub API 项应显示连接状态：

- 已连接：展示脱敏的 `owner/repo · branch · publishPath` 摘要。
- 未连接：禁用该选项或阻止提交，并提供“前往设置 → 连接器”。
- 不能在对话框中展示或回填 token。

底部按钮：

- “取消”
- 主按钮根据组合显示：
  - 无插件 + GitHub：`发布`
  - Harness + 不发布：`运行`
  - Harness + GitHub：`运行并发布`
  - 两者都不选：禁用

### 5.3 明确的用户确认

在主按钮上方显示执行摘要，例如：

```text
将使用 Harness Workflow 处理当前对话；
完成后通过 GitHub API 发布到 haitaopanhq/knowledge 的 main 分支。
```

这样网络发布行为是可见、可选、可确认的。

## 六、执行顺序与状态机

### 6.1 状态

```text
idle
  -> validating
  -> runningPlugin（可选）
  -> publishing（可选）
  -> completed
  -> failed
```

### 6.2 只运行 Harness

1. 解析当前 `TaskThread` 和所选 `HarnessTarget`。
2. 生成 Harness delivery context。
3. 将 Harness Workflow 规则作为结构化插件上下文注入当前任务线程。
4. 通过现有 `sendChatMessage`/任务执行通道运行，不创建新执行后端。
5. 结果继续进入当前对话与 artifact sidebar。
6. 不调用 GitHub API。

### 6.3 只发布 GitHub

1. 读取当前已完成消息。
2. 生成 Markdown 快照，保留完整正文及 `Builtin plugins`/Harness 上下文。
3. 从 `SecretStore` 根据 `tokenRef` 读取 token。
4. 使用 GitHub Contents API 创建唯一文件。
5. 返回可展示的 GitHub 文件 URL。

### 6.4 Harness 后发布

1. 先运行 Harness。
2. 必须等待本次插件执行完成，不能在 pending/running 状态提前发布。
3. 重新读取最新的当前线程消息。
4. 再执行 GitHub API 发布。
5. Harness 失败时不自动发布，并给出“仅发布现有对话”的二次选择。

首个 PR 若无法可靠监听 Harness 完成，可以先交付“运行”和“发布”两个明确阶段：

- 选择 Harness + GitHub 时先运行 Harness；
- 完成后在同一对话框显示“发布最新结果”；
- 不要用延时或轮询猜测任务是否完成。

## 七、GitHub API 连接器详细设计

### 7.1 设置交互

位置：设置 → 连接器 → 可用连接器。

卡片：

- 标题：`GitHub 仓库（API）`
- 说明：`通过 GitHub API 发布对话，无需启动本机 Git。`
- 按钮：未配置为“连接”，已配置为“配置”

表单：

- 仓库：接受 `owner/repo`、GitHub HTTPS URL、GitHub SSH URL，仅将其解析为仓库标识。
- Fine-grained token：密码字段，不自动填充。
- 分支：默认 `main`。
- 发布目录：默认 `conversations`。
- 动作：`连接并保存`。

设置页无论当前是否已连接 svc.plus 或自托管工作空间，都必须能看到/配置 GitHub 连接器。

### 7.2 验证

连接动作顺序：

1. 本地校验仓库、分支、路径与 token 非空。
2. `GET /repos/{owner}/{repo}` 验证 token 可访问仓库。
3. 成功后把 token 写入 `SecretStore`。
4. 把非敏感配置与 `tokenRef` 写入 `SettingsSnapshot`。
5. UI 显示连接成功；不得回显 token。

### 7.3 发布

创建文件：

```http
PUT /repos/{owner}/{repo}/contents/{encodedPath}
Authorization: Bearer <token>
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
```

body：

```json
{
  "message": "docs: publish conversation <title>",
  "content": "<base64 utf-8 markdown>",
  "branch": "main"
}
```

默认文件路径：

```text
<publishPath>/<yyyy-MM-dd-HHmmss>-<safe-title>.md
```

首版使用唯一时间戳路径，避免覆盖。如果以后允许固定路径更新，必须先 GET
现有文件的 `sha`，再在 PUT body 中携带 `sha`。

### 7.4 Markdown 内容

至少包含：

- 对话标题
- 发布时间
- 会话/任务标识（不得包含凭据）
- 用户和助手的已完成消息
- 插件选择摘要
- Harness target 的非敏感标识
- 原有 `Builtin plugins` 与 Harness context，不静默丢失

不得包含：

- GitHub token
- SecretStore 引用的实际值
- Authorization header
- SSH 私钥或本地 Keychain 内容

## 八、Feature flag 与商店边界

沿用 `config/feature_flags.yaml` 的
`desktop.settings.github_repository`，并补充/确认对话入口使用同一能力判断。

商店版允许：

- `dart:io HttpClient` 或项目现有 HTTP client
- GitHub HTTPS REST API
- Keychain/SecretStore

商店版禁止：

- `Process.run` / `Process.start`
- `git` CLI
- `ssh` CLI
- 读取 `~/.ssh`
- 下载并执行二进制

如果未来提供本地全功能 Git/SSH 版本，应使用独立 feature flag 和独立实现文件，
不能让商店构建仅靠 UI 隐藏仍打包可达的外部进程路径。

## 九、代码落点

已经存在或已修改：

- `lib/features/settings/local_git_repository_connection.dart`
  - 仓库解析、GET 验证、Contents API PUT、配置对象、Markdown 渲染。
- `lib/runtime/runtime_models_settings_snapshot.dart`
  - GitHub 非敏感配置持久化。
- `lib/features/settings/settings_account_panel.dart`
  - GitHub 连接器卡片和输入表单。
- `lib/features/settings/settings_page_core.dart`
  - token 写入 `SecretStore`，配置写入 Settings。
- `lib/app/app_controller_desktop_github_publish.dart`
  - 当前对话到 GitHub 发布的 controller 原型。
- `lib/features/assistant/assistant_page_main.dart`
  - 当前是直接发布按钮原型，必须改成工作流对话框。
- `lib/features/assistant/assistant_page_state_actions.dart`
  - 当前是直接发布 action 原型，必须改成选择请求执行。

建议新增：

- `lib/features/plugins/conversation_plugin.dart`
- `lib/features/connectors/conversation_publish_connector.dart`
- `lib/features/assistant/conversation_workflow_dialog.dart`
- `lib/app/app_controller_desktop_conversation_workflow.dart`

## 十、TDD 与验收矩阵

### 10.1 单元测试

- [x] GitHub 仓库三种输入格式解析。
- [x] API 验证成功/失败与请求 header。
- [x] Contents API 的 URL、branch、commit message、UTF-8 Base64。
- [x] GitHub 配置 JSON round trip，确认无 token。
- [x] Markdown 保留完整插件块。
- [ ] `ConversationWorkflowRequest` 的组合合法性。
- [ ] Harness target 缺失/无效时拒绝运行。
- [ ] 未选择 connector 时不读取 token、不发 HTTP。
- [ ] 插件失败时不自动发布。

### 10.2 Widget 测试

- [x] 未登录/未连接工作空间时显示 GitHub 卡片和“连接”按钮。
- [x] 点击卡片显示四个输入字段。
- [ ] 已连接 svc.plus 时仍显示 GitHub 卡片。
- [ ] 已连接自托管工作空间时仍显示 GitHub 卡片。
- [ ] 点击“对话工作流”打开对话框。
- [ ] 插件与连接器可以独立选择。
- [ ] Harness 无 target、GitHub 未连接时给出正确引导。
- [ ] 四种组合的主按钮文案和启用状态正确。
- [ ] 发布中防止重复提交。

### 10.3 集成/策略测试

- [x] `app_store_policy_test.dart` 确认 GitHub API 能力在商店策略下可用。
- [ ] 对话工作流入口受 feature manifest 控制。
- [ ] 静态扫描新增文件不引用 `Process`、shell 或 SSH 私钥路径。
- [ ] HTTP fake 验证“未选 GitHub = 0 次请求”。
- [ ] HTTP fake 验证“选 GitHub = 1 次 Contents API PUT”。

### 10.4 必跑命令

```bash
flutter analyze
flutter test test/features/settings/local_git_repository_connection_test.dart
flutter test test/runtime/settings_snapshot_github_repository_test.dart
flutter test test/features/settings/settings_account_panel_test.dart
flutter test test/features/assistant/assistant_page_session_binding_test.dart
flutter test test/app/app_store_policy_test.dart
git diff --check
```

UI 页面变化按仓库 `AGENTS.md` 还应增加/更新 widget 与 golden 测试；golden
基线更新前先完成视觉检查。

## 十一、当前验证记录

- `flutter analyze`：通过，无 issue。
- 5 组目标测试：通过，共 23 tests。
- `git diff --check`：通过。
- `flutter test` 全量曾出现仓库现有 mobile golden/page 测试失败
  （找不到 `mobile-assistant-page` 等 key）；当前判断与 GitHub API 文件无直接调用关系，
  提交前需再次确认失败基线并在 PR 中如实记录。

## 十二、提交、PR 与合并步骤

1. 先完成选择式对话框，删除/替换直接发布原型。
2. 修复“已连接工作空间后 GitHub 卡片不可见”的设置布局。
3. 完成上表测试与视觉检查。
4. 更新本文件的 checklist、验证结果和最终 commit。
5. 提交到 `agent/github-plugin-publish`。
6. 推送分支并创建面向 `main` 的 ready-for-review PR。
7. PR 描述必须说明：
   - PR #211 / #218 的 Harness 模型复用关系；
   - 插件和连接器独立可选；
   - GitHub API 无外部进程；
   - token 的安全存储方式；
   - 测试结果与已知全量测试基线。
8. 等待必需检查通过。
9. 使用 merge commit 合并，确保本地已有三个前置提交仍是远端 `main` 祖先。
10. 快进本地 `main`，确认工作树干净。
11. 在 PR #211 留下已交付 PR 链接；是否关闭 #211 以其剩余讨论是否仍有价值为准。

## 十三、当前工作树说明

当前分支有未提交代码，约 282 行增量，属于“GitHub 配置持久化 + 直接发布原型”：

- 可以保留 GitHub API、SecretStore、配置持久化和 Markdown 渲染部分。
- 必须重构直接发布按钮/action，不能以现状提交为最终产品。
- 尚未推送分支、尚未创建新 PR、尚未合并 `main`。

## 十四、Code Agent 交接规则

1. 每完成一个阶段，先更新本文件对应 checklist 和验证记录，再提交代码。
2. 不得把 token、Authorization header 或本机 SSH 信息写入本文件、测试 fixture 或日志。
3. 不得把“插件选择”和“发布连接器选择”重新耦合为一个固定选项。
4. 若执行语义发生变化，先更新“第五、六节”，再修改 UI/controller。
5. 合并前必须确认：未选择 GitHub 时没有任何 GitHub 请求。
