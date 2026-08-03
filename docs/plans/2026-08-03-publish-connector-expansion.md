# 发布连接器扩展规划

日期：2026-08-03
工作仓库：`ai-workspace-lab/xworkmate-app`
前置：`docs/tasks/2026-07-31-github-api-conversation-publisher-handoff.md`、`docs/plans/2026-08-02-platform-ops-actions-connector.md`
相关代码：`lib/features/connectors/conversation_publish_connector.dart`、`lib/features/settings/local_git_repository_connection.dart`、`lib/app/app_controller_desktop_github_publish.dart`

---

## 〇、这份文档要回答的问题

设置页「发布连接器」目前只有一张卡片（GitHub 仓库 API）。本文回答三件事：

1. **该扩展哪些**——邮箱、在线 Office、电商平台，哪些真的属于「发布连接器」，哪些不属于。
2. **扩展前要先改什么**——当前实现是 GitHub 专用的硬编码，加第二个连接器会在五个位置同时改，必须先抽象。
3. **按什么顺序做**——按「认证复杂度 × 用户价值」排序，而不是按平台知名度排序。

---

## 一、边界：什么才算发布连接器

沿用 `2026-08-02-platform-ops-actions-connector.md` 定下的执行链：

```text
对话 → select → plan/think → work → 发布连接器（结果去哪）
```

**发布连接器只回答"结果去哪"这一个问题。** 它接收一份已经产出的对话/产物，把它写到一个外部位置，然后返回成功或失败。它不参与规划，不做多轮交互，不持有业务状态机。

据此对三类候选做判定：

| 候选 | 是否属于发布连接器 | 理由 |
|---|---|---|
| **邮箱** | ✅ 是 | 「把这段对话发给某人」是标准的单向投递，一次请求一个结果。 |
| **在线 Office / 文档** | ✅ 是 | 「把结论写进这篇文档 / 新建一篇文档」同样是单向写入，与 GitHub 发布同构。 |
| **电商平台** | ❌ 不是 | 见下。 |

### 电商平台为什么不放进发布连接器

「发布到淘宝 / Shopify / 抖音小店」听起来像发布，实质不是：

- 它的输入不是一份 Markdown，而是一组**结构化业务对象**（SKU、价格、库存、图片、类目属性），需要预校验、类目映射、图片上传、审核状态轮询。
- 它失败之后需要**重试与补偿**，不是「返回一条失败消息」就结束。
- 它的凭据是**商家经营凭据**，安全等级高于「写一篇文档」。按 `docs/security/secure-development-rules.md` 的最小权限原则，这类凭据不应该落到桌面客户端。

这与运维派发是同一类问题，结论也应当一致：**电商属于 `work` 而不是「结果去哪」，应当做成 Gateway 侧的技能包 + 插件，而不是第三张连接器卡片。** App 侧只负责让用户选择插件与目标，执行、轮询、重试、凭据全部留在 Gateway。

如果确实要在 App 侧留一个入口，正确形态是复用既有的 `BuiltinPluginDescriptor` + `requiredSkills`，走 `2026-08-02` 那条链，本文不再展开。

---

## 二、前置改造：把 GitHub 专用逻辑抽象出来

### 2.1 现状：加一个连接器要改五处

| 位置 | 现在写死了什么 |
|---|---|
| `conversation_publish_connector.dart` | `enum ConversationPublishConnectorId { githubApi }`，`usesGitHub`，`validationIssues(GitHubRepositoryConnectorConfig)` 直接吃 GitHub 配置类型 |
| `SettingsSnapshot` | 只有一个 `githubRepository` 字段 |
| `settings_account_panel.dart` | `_GitHubConnectorSection` 是唯一一张发布连接器卡片，硬编码在面板里 |
| `app_controller_desktop_github_publish.dart` | `publishCurrentConversationToGitHub`，返回 GitHub 专用的 `GitHubApiResult` |
| `conversation_workflow_dialog.dart` | RadioListTile 硬编码 `ConversationPublishConnectorId.githubApi` |

按仓库的向后兼容策略（默认不保留兼容层），这次抽象应当**直接替换**上述结构，而不是在旁边并排加一套新接口。

### 2.2 目标结构

```dart
/// 一个发布连接器能接受什么、往哪写、怎么校验。注册表驱动，UI 不再枚举分支。
abstract interface class PublishConnector {
  String get id;                       // 'github-api' / 'smtp-email' / ...
  String get label;
  PublishPayloadFormat get accepts;    // markdown / html / plainText / file
  bool get isConfigured;
  String describeTarget();             // 不含凭据的一行摘要，卡片与确认框共用
  List<String> validationIssues();
  Future<PublishResult> publish(PublishRequest request);
}

@immutable
class PublishRequest {
  final String title;
  final String markdown;
  final List<PublishAttachment> attachments;
  final DateTime timestamp;
}

@immutable
class PublishResult {
  final bool success;
  final String message;
  final Uri? location;   // 发布后的可点击位置，GitHub 是 blob URL，文档是文档链接
}
```

配套三件事：

1. **配置存储改成 map**：`SettingsSnapshot.publishConnectors: Map<String, PublishConnectorConfig>`，每个连接器一份 JSON + 一个 `tokenRef`。凭据仍然只存 ref，值留在 `FlutterSecureStorage`，与现在 `githubRepositoryTokenRef` 的做法一致。
2. **设置卡片由注册表渲染**：`_GitHubConnectorSection` 泛化为 `_PublishConnectorSection`，遍历注册表出卡片，每个连接器提供自己的配置表单 widget。
3. **workflow 对话框由注册表出选项**：`ConversationPublishConnectorId` 枚举删除，改为 `String connectorId`，RadioGroup 遍历已配置的连接器。

**这一步是所有后续工作的前提，单独一个 PR，不夹带任何新连接器。** 它应当保持行为完全不变：GitHub 连接器迁移到新接口，现有测试全绿。

### 2.3 顺带要修的一致性问题

- `verifyGitHubRepositoryConnection` / `publishConversationToGitHub` 里的 `catch (_) { return failure('Could not reach GitHub...') }` 把所有异常压成同一句话。新接口应当区分「网络不可达 / 认证失败 / 权限不足 / 目标不存在」，与本轮登录连接器的错误分级保持一致（见 `describeAccountFailureInternal`）。
- 发布结果目前只有一句话，没有 `location`。用户发布完看不到"发到哪了"，`PublishResult.location` 应当在这次抽象里补上。

---

## 三、候选连接器清单

### 3.1 邮箱

| 方案 | 认证 | 桌面端可行性 | 备注 |
|---|---|---|---|
| **SMTP + 应用专用密码** | 用户名 + 密码 | ✅ 直接可做 | 与 GitHub token 同构：一个表单、一个 secret ref、一次连接测试（SMTP `NOOP`）。Gmail / Outlook / 企业邮箱都支持应用专用密码。 |
| Gmail API | OAuth 2.0 + PKCE | ⚠️ 需回调 | 需要 loopback 回调服务器，见 §4。 |
| Microsoft Graph `sendMail` | OAuth 2.0 + PKCE | ⚠️ 需回调 | 同上。 |

**建议：先只做 SMTP。** 它把「发布连接器 = 一个表单 + 一个 secret + 一次连通性测试」的模式再验证一遍，不引入 OAuth 这个新的架构问题。OAuth 版本等 §4 定了再说。

配置项：SMTP 主机、端口、是否 STARTTLS/SSL、用户名、密码（secret ref）、默认收件人、默认主题模板。
安全约束：禁止明文 SMTP（端口 25 无 TLS）直连远端；仅在显式 loopback 测试流程中放行，与网关的 TLS 降级规则一致。

### 3.2 在线 Office / 文档

| 平台 | 认证 | 写入方式 | 复杂度 |
|---|---|---|---|
| **Notion** | Integration Token（长期，非 OAuth） | `PATCH /v1/blocks/{id}/children` 追加，或 `POST /v1/pages` 新建 | 🟢 低——与 GitHub 几乎同构 |
| **语雀** | Personal Token | `POST /repos/{id}/docs` | 🟢 低 |
| **Confluence** | API Token + 邮箱（Basic） | `POST /rest/api/content` | 🟢 低 |
| WordPress | Application Password | `POST /wp-json/wp/v2/posts` | 🟢 低 |
| 飞书文档 | 应用 token + 用户授权 | `POST /open-apis/docx/v1/documents` | 🟡 中——需应用注册 |
| Google Docs / Drive | OAuth 2.0 + PKCE | Drive `files.create` (MIME 转换) | 🔴 高——需回调 + 应用审核 |
| Microsoft Word / OneDrive | OAuth 2.0 + PKCE | Graph `driveItem` PUT content | 🔴 高——同上 |
| 腾讯文档 | OAuth 2.0 | 导入 API | 🔴 高 |

**关键观察：Markdown 是天然的公共输入格式。** Notion / 语雀 / Confluence / WordPress 都能直接吃 Markdown 或简单转换后的 HTML，`renderGitHubConversationMarkdown` 可以原样复用。Google Docs 与 Word 需要格式转换（Markdown → HTML → 平台格式），这是它们复杂度更高的第二个原因。

**建议：先做 Notion 与语雀。** 两者都用长期 token，认证模型与 GitHub 完全一致，且覆盖国内外两侧用户。Google/Microsoft 一族全部压在 OAuth 决策之后。

### 3.3 IM / 协作（清单里没提，但成本最低）

Slack / 飞书 / 企业微信 / Discord 的 **Incoming Webhook** 是所有候选里最便宜的一类：一个 URL（本身即凭据）、一次 POST、没有 OAuth、没有格式转换。

如果目标是「让发布连接器这个抽象尽快有第二、第三个实例来验证设计」，Webhook 类是比邮箱更快的验证路径。建议在 §2 抽象完成的同一个迭代里顺手做一个，成本约等于零。

---

## 四、必须先决策的架构问题：OAuth 回调

Google、Microsoft、腾讯文档、飞书全部要求 OAuth 2.0 授权码流程，需要一个 redirect URI。桌面/移动客户端有三条路：

| 方案 | 做法 | 代价 |
|---|---|---|
| **A. Loopback + PKCE** | App 起临时 `http://127.0.0.1:<port>/callback`，系统浏览器授权后回跳 | 需要在 App 内开监听端口；macOS 沙盒与 entitlements 要评估；移动端不适用 |
| **B. 自定义 scheme** | `xworkmate://oauth/callback`，注册 URL scheme | 移动端标准做法；桌面端各平台注册方式不一；部分厂商不接受非 https redirect |
| **C. 经 Bridge 中转** | Bridge 提供 https 回调端点，换到的 token 再下发给 App | 认证复杂度移出客户端；但 token 会经过 Bridge，需要明确信任边界与留存策略 |

**这三条路的选择决定了 §3 里所有 🔴 项能不能做，必须在动手之前定，不能边做边定。**

倾向性意见（需确认）：桌面端选 **A（loopback + PKCE）**，理由是 token 不经过第三方、与现有「凭据只存本地 secure storage」的模型一致；移动端在有明确需求前不做 OAuth 连接器。若选 C，则需要一份独立的信任边界文档，并更新 `docs/security/secure-development-rules.md` 第 2 节。

---

## 五、分期路线

| 阶段 | 内容 | 出口条件 |
|---|---|---|
| **P0** | §2 抽象层：`PublishConnector` 接口 + 注册表 + 配置 map + 卡片/对话框泛化；GitHub 迁移到新接口 | 行为零变化，`flutter analyze` + `flutter test` 全绿，GitHub 发布路径的现有测试不改断言 |
| **P1** | Webhook 连接器（Slack 或飞书，二选一）| 第二个连接器落地，验证注册表不需要为它开分支；`PublishResult.location` 生效 |
| **P2** | SMTP 邮箱连接器 | 覆盖「连接测试」与「发送失败分级」两类新场景 |
| **P3** | Notion + 语雀 | 验证「同一份 Markdown 投递到多个文档平台」的复用度 |
| **P4** | OAuth 决策落地（§4），之后才谈 Google Docs / Microsoft Word | 决策文档合入 + 一个可跑通的 OAuth 连接器 |
| **不排期** | 电商平台 | 按 §1 的判定，走 Gateway 技能包路线，不进发布连接器 |

P0 是硬前置。P1–P3 之间没有依赖，可以并行。

---

## 六、每个新连接器的验收清单

抽象层落地后，新增一个连接器应当只需要：

1. 一个实现 `PublishConnector` 的类（`lib/features/connectors/<name>_publish_connector.dart`）。
2. 一个配置表单 widget。
3. 在注册表里注册一行。
4. 三类测试：配置校验、连接测试成功/失败、发布成功/失败（用注入的 fake HTTP 客户端，禁止打真实网络）。

**如果新增一个连接器还需要改注册表以外的公共代码，说明抽象没做对，回到 §2。**

安全检查项（每个连接器都要过）：

- 凭据只存 `tokenRef`，值进 secure storage，不进 `SettingsSnapshot` 的 JSON。
- 摘要文本（卡片副标题、确认框、日志）不含凭据片段。
- 远端连接不允许 TLS 降级。
- 失败消息分级，不把异常 `toString()` 直接抛给用户。
