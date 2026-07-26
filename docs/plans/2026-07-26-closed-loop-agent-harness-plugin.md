# Closed Loop Agent Harness 插件规划（新分组：开发工作流）

状态：规划中，未落地任何代码。
关联：[`2026-07-04-builtin-plugins-batch-1.md`](./2026-07-04-builtin-plugins-batch-1.md) §8.1（workflow 状态机演进）、
[`2026-07-05-plugin-ffi-runtime.md`](./2026-07-05-plugin-ffi-runtime.md) §2（运行时绑定）、
`xworkspace-core-skills/skills/engineering-standards/`（六份工程标准 + `harness-workflow` 大脑技能）。

## 1. 目标

在 App 内置插件里**新开一个分组「开发工作流 / Development Workflow」**，
首个插件为 `builtin.harness`（工程闭环 Agent Harness）。

它的作用域与现有 5 个插件（文档/表格/PPT/图片/视频，属「内容产出」分组）完全不同：

> **直接作用于传入的代码仓库**，面向**组织 / 项目 / 多仓库 / 多环境**的负载业务系统，
> 以闭环小步方式推进 **代码变更 → 测试 → 微调 → 部署**。

产物不是文件，而是**分支、PR、CI 结论、部署记录、回滚点**。

### 与内容产出分组的结构性差别

| 维度 | 内容产出分组（现有 5 个） | 开发工作流分组（Harness） |
| --- | --- | --- |
| 作用对象 | 会话内容 → 文件 | **代码仓库**（多个），及其运行环境 |
| 上下文绑定 | `currentTaskWorkspace`（产物目录） | **交付目标**：org / project / repos[] / environments[] |
| 流程形状 | 线性 | **闭环 + 内层微调回路**，失败跳回重规划 |
| 并发形状 | 单流 | **跨仓扇出**，按依赖顺序（infra → app → gitops）并汇合 |
| 完成判定 | 文件生成即完成 | **证据断言**：PR URL / CI conclusion / 部署命中数 / 健康探针 |
| 失败语义 | degrade（出个次品也算交付） | **禁止降级交付**，只有重规划或逆序回滚 |
| 人工介入 | 无 | 计划审批、CI+review、生产发布**三道强制闸门** |

### 非目标

- App 不自研 Policy Engine，不代替 CI / 分支保护 / Vault 做强制。
- **App 侧不执行 git / gh / ssh**，不持有任何仓库或云凭据。执行面在网关 agent 所在主机
  （其上已有 git / gh / ansible / 技能包），App 是控制面与证据收集面。
- 不改动 Vault / GitHub Actions / platform-ops-toolkit。跨仓改动另立规划。

## 2. 分组模型（新增）

`BuiltinPluginCatalog.firstBatch` 是一个平铺列表，UI 四处直接遍历它。要开新分组必须先有分组概念。

```dart
enum BuiltinPluginGroup { contentProduction, developmentWorkflow }
```

- `BuiltinPluginDescriptor` 新增 `group`，缺省 `contentProduction`（存量 5 个零改动）。
- 目录新增 `static const developmentWorkflowBatch` 与 `static const all = [...firstBatch, ...developmentWorkflowBatch]`；
  `byId` 遍历 `all`；`firstBatch` 保留以免破坏外部引用。
- 新增 `pluginsByGroup(BuiltinPluginGroup)` 供 UI 分节渲染。
- 4 处消费点改为按分组渲染并加分节标题：
  `settings_plugins_panel.dart:22`、`assistant_page_composer_bar.dart:463`、
  `mobile_assistant_page_conversation.dart:339`、`mobile_assistant_page_composer.dart:371`。
- `BuiltinPluginKind` 新增 `engineering`；`builtin_plugin_visuals.dart` 的 switch 是穷尽的，
  必须补色（teal `0xFF0F766E`，与办公五色明显区分），icon 用 `Icons.account_tree_outlined`。

## 3. 交付目标绑定（本规划的真正新东西）

现有上下文注入只给 agent 一个 `currentTaskWorkspace`
（`app_controller_desktop_thread_actions.dart:1001` 的 `taskWorkspaceContextPromptInternal`）——
那是**产物输出目录**，不足以描述"改哪些仓库、发到哪个环境"。新增一层：

```dart
class HarnessRepoBinding {
  final String name;            // ai-workspace-infra/platform-ops-toolkit
  final String url;
  final HarnessRepoRole role;   // app | infra | gitops | playbooks | service
  final String checkoutPath;    // 网关主机上的路径
  final String defaultBranch;   // main
  final int order;              // 跨仓执行顺序：infra=0 app=10 gitops=20
}

class HarnessEnvironment {
  final String name;                 // sit | uat | prod
  final HarnessTriggerKind trigger;  // pullRequest | mainPush | tag
  final HarnessDeployKind deploy;    // ghWorkflowDispatch | docoCdWebhook | ansible
  final String healthProbe;          // 部署后断言用的 URL / 命令
  final bool requiresHumanGate;      // prod 恒为 true
}

class HarnessTarget {
  final String org, project;
  final List<HarnessRepoBinding> repos;
  final List<HarnessEnvironment> environments;
}
```

- 存储：随设置持久化（参考 `workspace_management` 的表单/持久化形态），可配多个 target，线程级选择。
- 注入：在既有 workspace context 块之后追加一段 `Harness delivery context:`
  （org / project / repos+role+path / environments+trigger+deploy），
  与 `currentTaskWorkspace` 并列，不替换它——产物（计划、报告）仍写进任务工作区。
- 环境路由刚性：分支类别与环境的映射由 `HarnessEnvironment.trigger` 声明，
  步骤请求的环境与当前分支类别不匹配时直接拒绝执行，不给 agent 自由发挥空间。

## 4. 流水线定义（代码 → 测试 → 微调 → 部署）

| # | id | 阶段 | 扇出 | 完成证据（断言） | 闸门 | 失败去向 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `bind` | 绑定并校验交付目标 | 单流 | 每个 repo 可达、checkout 存在、环境路由表完整 | — | abort |
| 2 | `analyze` | 跨仓现状分析（repo map、依赖、各环境当前版本与漂移） | perRepo | 每仓产出结构化现状摘要 | — | abort |
| 3 | `plan` | 最小变更集规划（跨仓变更清单 + 分支命名 + 执行顺序 + 回滚预案） | 单流 | 计划 `md` 含每仓分支名与回滚步骤 | **人工确认** | abort |
| 4 | `change` | 按 `order` 逐仓落代码/配置/IaC 变更 | perRepo 有序 | 每仓有非空 diff、分支名符合 `project-development-standard` | — | replan → `analyze` |
| 5 | `test` | 变更处本地/前置测试（lint / unit / build / `terraform plan`） | perRepo | 命令退出码 0 **且** 报告文件存在（不接受"我跑过了"） | — | replan → `change` |
| 6 | `artifact` | 逐仓开 PR，跨仓 PR 互相引用 | perRepo | 每仓返回 PR URL + number | — | replan → `change` |
| 7 | `validate` | CI 门禁 + 人类审查 | perRepo 汇合 | 每个 PR 的 CI `conclusion == success` **且 job 未被 skipped** | **人工确认** | replan → `change` |
| 8 | `deploy` | 按环境路由部署（SIT/UAT） | 单流（按 repo order） | 部署 run 成功 + **主机命中数 > 0** + 健康探针通过 | — | replan → `tune` 或 `rollback` |
| 9 | `tune` | 微调内回路：观测（日志/指标/探针）→ 调配置或参数 → 重部署 | 单流 | 观测指标达阈值；配置改动必须落在 config-as-code 仓，禁止直接改主机 | — | 回 `deploy`，超预算 → `rollback` |
| 10 | `promote` | 生产发布（tag 触发） | 单流 | tag 已推、prod 部署 run 成功 | **人工确认（强制）** | rollback |
| 11 | `verify` | 发布后验证（健康探针 + 关键路径） | 单流 | 探针通过、无新错误率抬升 | — | rollback |
| 12 | `rollback` | 逆序止损（gitops → app → infra），revert / 回滚到上一 tag | perRepo 逆序 | 每仓有 revert commit 或回滚 run，环境探针恢复 | — | abort |
| 13 | `next` | 收敛本轮增量，进入下一循环 | 单流 | — | — | — |

`requiredSkills` 绑定 `engineering-standards`：`harness-workflow`（全程）、
`ai-agent-collaboration-standard` + `project-development-standard`（3/4/12）、
`ci-cd-workflow-spec`（5/7）、`infrastructure-as-code-spec` + `config-as-code-spec`（4/9）、
`multi-environment-delivery-and-release`（8/10）。

### 反"假绿"是第一原则

`platform-ops-toolkit` 的两次事故都是**看起来绿了但什么都没做**：
inventory 路径错 → ansible 0 主机命中仍 exit 0；skip 沿 `needs` 链传递 → deploy job 根本没被求值。
所以每一步的完成判定必须是**声明式证据断言**，不是 agent 自述：

```dart
class BuiltinPluginStepVerification {
  final HarnessEvidenceKind kind;  // prUrl | ciRun | deployRun | hostCount | httpProbe | command | fileExists
  final String assertion;          // conclusion == success && skipped == false
  final bool required;             // true：拿不到证据即判定 failed，不得 succeeded
}
```

**拿不到证据 = 失败**，这条不设例外。没有 `degrade` 出口。

## 5. 模型扩展（schemaVersion 2 → 3）

在 `builtin_plugin_workflow.dart` / `builtin_plugin_workflow_run.dart` 上扩展，全部向后兼容
（新字段有默认值，v1/v2 清单继续解析，存量 5 个插件行为与模板逐字符不变）：

**Step 新增**
- `gate: none | humanReview` + `gateReasonZh/En`
- `scope: single | perRepo` + `repoRoles`（限定扇出到哪些角色的仓库）
- `verification: BuiltinPluginStepVerification`
- `rollbackInstructionZh/En`
- `environment`（该步作用的环境名，空 = 与环境无关）

**失败策略新增 `replan`** + `replanTargetStepId`（闭环的唯一非线性转移；分支/汇合/自由 guard 留后续批次）。

**Workflow 新增** `maxLoopIterations`（默认 3）与 `maxTuneIterations`（默认 5）——死循环护栏。

**Run 层改造（run schemaVersion 1 → 2）**：现有实现用「按步骤下标的 statuses 数组」，
闭环重访会被覆盖、扇出无处安放，必须改：
1. 新增状态 `awaitingApproval` / `awaitingEvidence` / `rolledBack`。
2. 每步内维护 **per-repo lane**（repo → 状态/证据/attempt），汇合规则 all-must-pass。
3. 新增 **append-only 事件日志** `{seq, stepId, repo, attempt, iteration, from, to, at, evidence}`——
   即文章说的 immutable audit event，也是后续接 X-Memory-Hub 采集的结构化摘要来源；
   `statuses` 降级为当前视图，日志才是事实来源。
4. 新增 API：`approveCurrentStep()` / `rejectCurrentStep(reason)` / `submitEvidence(repo, evidence)` /
   `replanTo(stepId)` / `enterRollback()`。
5. `replan` 时 iteration+1，超 `maxLoopIterations` 按 abort 处理并进 `rollback`。

## 6. 执行语义：必须真执行

上一版规划设想过"先做提示词级闭环"。按修正后的目标，那条路不成立——
提示词说服不了 CI，也拿不到 PR URL 和部署 run id。所以执行端接入
（batch 1 计划 §8.1 的「重构批次 4」，至今 `BuiltinPluginWorkflowRun` 无任何执行端消费）
从"后续"变成**本规划的主线**。

分工：

| 面 | 位置 | 职责 |
| --- | --- | --- |
| 控制面 | App（本仓） | 推进状态机、渲染每步契约、拦闸门、收证据、判定成败、可视化与审计 |
| 执行面 | 网关 agent 主机 | 实际 git / gh / 测试 / ansible / 部署触发（凭据在网关侧与 Vault，App 不碰） |
| 证据面 | 见下 | 把执行结果变成可断言的结构化事实 |

证据获取分两阶段落地：
- **E1（先做）**：每步任务下发时附带**结构化返回契约**，要求 agent 以固定 JSON 块回报
  （PR URL、CI run id/conclusion、部署 run id、主机命中数、探针状态码）。App 解析并断言。
  优点：零跨仓依赖，今天就能做。风险：agent 可能编造 → 断言里带上可复查的 id/URL，
  并在 UI 明示"证据来源：agent 自报"。
- **E2（后做）**：证据由 bridge/gateway 侧直接查 GitHub / 部署系统核实，
  agent 自报降级为线索。需要 `xworkmate-bridge` 侧新增能力，跨仓另立规划。

## 7. 里程碑

| 里程碑 | 内容 | 分支 | 可验证制品 |
| --- | --- | --- | --- |
| M1 | 分组模型：`BuiltinPluginGroup` + `all` + `pluginsByGroup` + 4 处 UI 分节渲染（此时新分组为空） | `feature/plugin-groups` | PR，存量插件视觉不变（golden 更新） |
| M2 | 交付目标模型 `HarnessTarget` + 设置页表单 + 持久化 + 上下文注入块 | `feature/harness-delivery-target` | PR + 可配置并注入的 delivery context |
| M3 | Workflow 模型扩展：gate / replan / rollback / scope / verification / 循环预算，schema v3 + run v2（含扇出 lane 与事件日志） | `feature/harness-workflow-model` | PR + 单测，存量插件零变化 |
| M4 | Harness 插件目录条目 + 13 步定义 + 模板渲染 + feature flag（preview） | `feature/harness-plugin-catalog` | PR + 设置页/输入框可见 |
| M5 | 执行端接入（E1 证据契约）：逐步下发、闸门阻塞、证据断言、跨仓扇出、进度与审计面板 | `feature/harness-plugin-executor` | PR + 在一个真实双仓小变更上跑通 SIT |
| M6 | 清单外部化：workflow JSON 移到 `xworkspace-core-skills/.../harness-workflow/workflow.json`，经 `BuiltinPluginRuntimeBinding.manifest` 拉取；E2 证据核实 | 跨仓，另立规划 | 标准仓成为单一事实来源 |

每个里程碑一个 `feature/*` → `main` 的小步 PR。自己吃自己的狗粮：Harness 的落地按 Harness 走。

**首个验收场景建议**：拿 `platform-ops-toolkit` + `gitops` 双仓的一个 UAT 小变更做 M5 验收——
这正是现成的多仓多环境负载业务系统，且已知的假绿坑都在那条链路上，能真正检验证据断言是否有效。

## 8. 测试

- 分组：`pluginsByGroup` 分节正确、`all` 长度 6 而 `firstBatch` 仍为 5、`byId` 覆盖新插件。
- 交付目标：`HarnessTarget` JSON 往返、repo order 排序、环境路由表缺项时 `bind` 判定失败、
  分支类别与环境不匹配时拒绝执行。
- 模型：v3 往返 + v1/v2 兼容解析；`replanTargetStepId` 悬空时安全回退。
- Run：闸门 → `awaitingApproval`；approve/reject 分支；perRepo lane 汇合（一仓失败即整步失败）；
  证据缺失 → `failed` 而非 `succeeded`（**反假绿主测例**）；replan 跳回并重置后续步骤；
  循环预算耗尽 → rollback；事件日志 seq 单调且含每次重访；带日志与 lane 的断点续跑往返。
- 模板：存量 5 个插件模板逐字符不变（现有 prompt 快照测试兜底）；Harness 模板含闸门、
  证据契约 JSON 块、回滚契约。
- **金标风险**：`test/features/mobile/mobile_assistant_home_golden_test.dart` 与
  `mobile_assistant_page_test.dart` 渲染插件列表，分组分节 + 第 6 条会改布局 → M1 同批更新。

## 9. 风险与对策

| 风险 | 对策 |
| --- | --- |
| **假绿**：agent 自述成功但什么都没做 | 每步必须有 required 证据断言；拿不到证据即 failed；无 degrade 出口；M5 验收场景刻意选已知假绿链路 |
| agent 编造证据 | 证据必须是可复查 id/URL；UI 标注"agent 自报"；E2 阶段改为服务端核实 |
| 跨仓顺序错（app 先于 infra 部署） | `HarnessRepoBinding.order` 声明依赖顺序，`change`/`deploy`/`rollback` 按序/逆序推进，不由 agent 决定 |
| 生产误发 | `promote` 强制人工闸门 + 环境路由刚性校验（非 tag 分支类别直接拒绝） |
| 凭据边界 | App 不持有任何仓库/云凭据；执行面凭据在网关主机与 Vault；delivery target 只存名称与路径 |
| 微调回路无限重部署 | `maxTuneIterations` 默认 5，耗尽进 rollback |
| 模型一步跨成通用工作流引擎 | 只加 `replan` 一种非线性转移 + perRepo 一种扇出；分支/汇合/guard 留后续 |
| 存量插件被误伤 | 新字段全默认值；分组缺省 `contentProduction`；prompt 快照锁定模板不变 |
| 受众不同（平台工程师 vs 办公用户） | 新分组独立 feature flag，首版 `release_tier: preview` + `build_modes: [debug, profile]` |
| 定义双写（App 常量 vs 标准仓 SKILL.md）漂移 | M1–M5 承认双写并互相引用，M6 以标准仓 `workflow.json` 收敛 |

## 10. 待确认

1. **分组命名**：「开发工作流 / Development Workflow」是否定稿？该分组后续还会放什么插件
   （如"仅代码评审"、"仅事故止损"），会影响分组与 kind 的粒度划分。
2. **交付目标从哪来**：手工在设置页配置（M2 方案），还是从 CMDB / gitops 仓自动发现？
   自动发现更贴合"组织/项目"的规模，但要新增跨仓读取能力。
3. **微调（`tune`）的观测数据源**：健康探针足够，还是要接 observability
   （`ai-workspace-infra/observability`）的指标？后者会把范围扩到监控集成。
4. **M5 验收场景**：是否就用 `platform-ops-toolkit` + `gitops` 的 UAT 双仓变更。
