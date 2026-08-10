# 多端共享 TaskThread 与多 Namespace 调度 MVP

> 状态：实施中（TDD 第一垂直切片已完成）  
> 日期：2026-08-10  
> 目标：把现有 `TaskThread`、Bridge ACP 和 UAT AI Workspace 串成一个跨端可继续、可恢复、可按 namespace 公平调度的最小闭环。

## 1. 结论

不新造第二套任务模型，也不让 App、Web、Bridge 分别保存“当前任务”的真相。

**APP UI 冻结是本 MVP 的硬约束。** 已运行的 XWorkmate APP 保持当前页面、导航、文案、交互、组件层级和视觉样式不变；本期只在 controller、repository、runtime transport 层补齐共享会话与调度。Web AI Workspace 不是用来反向改造 App 的原型，而是独立地、按既有 APP 功能语义逐步对齐。

MVP 的唯一主链是：

```text
Namespace -> Session(TaskThread) -> append-only SessionEvent -> TaskRun -> Scheduler lease -> Bridge ACP -> terminal SessionEvent
```

- `TaskThread.threadId == sessionId`：沿用已确定的稳定身份，不允许空 key 或回退到 `main`。
- `accounts`：新增轻量 Session + Scheduler 控制面，持久化身份、权限、任务 ID 上下文、小型事件、任务运行和租约；是共享状态权威源。
- `xworkmate-bridge`：继续是 ACP 执行控制面，负责路由、运行、标准化结果；不保存跨端会话真相，也不承担多 Agent 编排。
- `xworkmate-app` 与 UAT Web：都是 Session 客户端。本地文件/SharedPreferences 只作缓存和离线草稿，不覆盖云端事件。
- `X-Memory-Hub`：MVP 只保存并检索 namespace 内已确认的记忆引用；不把原始聊天记录自动注入或跨 namespace 共享。

这与已存在的 `TaskThread == sessionKey`、Bridge `/acp` / `/acp/rpc` 和 OpenClaw `xworkmate.tasks.get` 恢复链兼容，但会替换 App 内存队列作为跨端调度真相的角色。

### 1.1 客户端交付原则

| 客户端 | 本 MVP 的要求 | 不做的事 |
| --- | --- | --- |
| 运行中的 XWorkmate APP | UI 不变；通过现有 TaskThread、会话列表、运行状态、设置入口消费新的云端 Session API。`SessionSyncCoordinator` 和 `CloudTaskThreadStore` 只改状态来源。 | 新增 namespace 选择器、页面、按钮、导航项、文案，或为了同步而改 widget/golden。 |
| Web AI Workspace | 保持现有工作台入口；以 API 合同逐步补齐 APP 的会话、任务、产物与运行能力。 | 把 Web 私有状态双写回本地，或要求 APP 跟随 Web 的页面结构改版。 |

APP 的 namespace 在 MVP 中不增加可见交互：服务端由现有账号默认 `personal` namespace 与 `workspaceBinding.workspaceId` 的绑定解析。第二 namespace 的创建/绑定先在 Web 管理面完成；APP 继续在当前 workspace 对应的 namespace 内工作。这样多 namespace 已进入主链，但不会改变已运行 APP 的界面。

## 2. 已有基础与缺口

| 现有基础 | 已能解决 | MVP 仍需补齐 |
| --- | --- | --- |
| App `TaskThread`（workspace/execution/context/lifecycle） | 线程身份、工作目录隔离、产物回写 | 云端权威快照、事件回放、跨端 attach |
| Bridge ACP、routing、OpenClaw task snapshot | 统一执行协议、异步运行恢复、产物合同 | durable task run、namespace 鉴权、可恢复排队 |
| Bridge distributed session route | 单次会话转发与 24h 粘性 | 跨实例持久租约、按 namespace 的公平策略 |
| App OpenClaw 内存队列（5 active / 20 queued） | 单进程限流 | 重启恢复、跨端可见、全局去重与公平 |
| Accounts 的账号、设备、Postgres、PGMQ | 身份与设备基础、已有队列运维能力 | namespace/session/task-run 领域表与 API |
| UAT 工作台 | TaskThread/专项/进度的可见入口 | 共享会话列表、运行状态流、namespace 切换 |

`scheduler_decisions` 是账户/节点调度审计表，不能直接拿来当任务队列；`vaultNamespace`、Kubernetes namespace、Postgres schema 也不能复用为产品任务 namespace。

## 3. MVP 范围

### 包含

1. 已登录同一账号可在 Desktop、Mobile、UAT Web 打开同一个会话，并看到同一轻量会话上下文与运行状态；APP 现有 UI 不变。
2. 一个账号至少有默认 `personal` namespace；可创建第二个 namespace，并在两个 namespace 间隔离会话、记忆引用与队列配额。
3. 用户发送消息时先写入 Session Event；“立即运行”或“定时运行”创建一个持久 `TaskRun`。
4. 共享调度器按 `not_before + priority + FIFO` 选任务，并实行 **每 namespace 最多 2 个 active、全局最多 5 个 active** 的 MVP 配额。各 namespace 轮转挑选，避免一个 namespace 吃满全局槽位。
5. 任务由一个 Bridge 获取带 fencing token 的执行租约；Bridge 通过现有 ACP/OpenClaw 主链执行，并只用内部回调追加运行事件、终态和产物摘要。
6. 客户端通过 snapshot + SSE 补事件；断线后按序号补洞。取消只取消未开始任务；已运行任务复用 `xworkmate.tasks.cancel`。

### 明确不包含

- 团队成员邀请、复杂 RBAC、跨组织共享、工作流 DAG、依赖排程、抢占、自动重试、跨区域容灾。
- 多 Agent 编排（Bridge 既有边界明确禁止）。
- 把终端、任意本地电脑都变成云端调度 worker；MVP 只调度已注册的受管 Bridge 执行目标。
- 自动将全量会话写入共享记忆或把记忆当作会话恢复来源。
- 迁移所有历史本地线程；首期只支持“导入为一次快照”的显式迁移。

## 4. 领域边界与身份

### 4.1 Namespace

`namespace_id` 是产品级的数据与调度隔离域，不是部署概念。

```text
Account (owner) 1 --- N Namespace 1 --- N Session 1 --- N TaskRun
                                         \--- N MemoryRef
```

建议字段：`id (UUID)`、`account_uuid`、`slug`、`display_name`、`status`、`max_active_runs`、`created_at`。账号创建时原子创建不可删除的 `personal` namespace。

所有外部请求使用 UUID，展示层可显示 slug；所有查询必须带 `account_uuid + namespace_id`，服务端从 token 得到账户，不接受客户端声称的 accountId。

### 4.2 会话、运行与租约

| 实体 | 关键字段 | 说明 |
| --- | --- | --- |
| `sessions` | `id`, `namespace_id`, `title`, `snapshot_version`, `last_event_seq`, `lifecycle_state` | 一行就是一个轻量 `TaskThread` 控制记录；`id` 同时是 app `threadId/sessionKey`。 |
| `session_events` | `session_id`, `seq`, `type`, `payload jsonb`, `actor_type`, `actor_id`, `client_request_id`, `created_at` | 追加式轻量事实流：消息文本/状态/上下文摘要；`(session_id, seq)` 与 `(session_id, client_request_id)` 唯一。 |
| `session_snapshots` | `session_id`, `version`, `last_event_seq`, `snapshot jsonb` | 加速首次 attach；仅保存任务上下文摘要、选择项、运行态和事件游标，不保存制品。 |
| `task_runs` | `id`, `session_id`, `namespace_id`, `state`, `priority`, `not_before`, `attempt`, `routing`, `lease_*`, `bridge_task_ref` | 持久队列和运行状态；不再把 App 内存队列当作权威。 |
| `memory_refs` | `namespace_id`, `session_id`, `memory_id`, `scope`, `status` | 指向 X-Memory-Hub 的已确认知识；MVP 可为空。 |

租约字段为 `lease_owner`、`lease_token_hash`、`lease_expires_at`、`fence`。每次 claim 递增 `fence`；任何 Bridge 回写均须携带匹配的 `task_run_id + fence + lease token`，过期或旧 worker 的回写一律拒绝。

### 4.3 PG 轻量化与制品边界

PG 只保存可用于恢复、调度和跨端继续的最小数据：任务 ID、会话标题、namespace、短消息/摘要、模型与路由选择、状态、时间、运行 ID、调度参数和 lease。单个事件 payload 设上限（建议 16 KiB），单个 snapshot 设上限（建议 128 KiB）；超限上下文先摘要后写入。

PG **不保存** 制品字节、文件内容、图片/音视频、附件正文、base64、完整工具日志、工作目录文件列表，也不建立 `artifacts` 表。Bridge/OpenClaw 保持现有 run-scoped artifact scope 和终态查询；PG 的 `task_runs.bridge_task_ref` 仅保存不透明任务引用。客户端需要制品时，使用 `taskRunId + bridge_task_ref` 向 Bridge 制品域查询，不能从 PG 恢复或推断制品。

## 5. 主流程

```mermaid
sequenceDiagram
  participant C as "Desktop / Mobile / UAT Web"
  participant A as "Accounts Session API"
  participant S as "Scheduler Worker"
  participant B as "XWorkmate Bridge"
  participant O as "Provider / OpenClaw"

  C->>A: append message event (idempotency key)
  C->>A: create TaskRun (now or not_before)
  A-->>C: session snapshot + event seq + run queued
  S->>A: atomically claim eligible run / issue lease
  S->>B: dispatch signed run envelope
  B->>O: existing ACP session.start/session.message
  B->>A: append running/progress/terminal state event with fence
  A-->>C: SSE events; reconnect by after_seq
  C->>A: GET snapshot?after_seq=n on gap/reconnect
```

细则：

- 在创建 `TaskRun` 前，`message.created` 必须已成功落库；同一 `client_request_id` 重试只返回原结果。
- Scheduler 使用 PostgreSQL 事务、`FOR UPDATE SKIP LOCKED` 与条件更新 claim，不能依赖单机内存 FIFO。
- 调度器只发派发命令；Bridge 不信任客户端提交的 namespace，而验证 Accounts 签发的短期内部令牌，并将 `namespaceId`、`sessionId`、`taskRunId`、`fence` 作为运行元数据透传。
- Bridge 保留现有 provider routing、artifact contract、OpenClaw terminal snapshot 与 cancellation；完成后调用 Accounts 内部 callback，Accounts 只写权威运行终态，制品仍留在 Bridge/OpenClaw 制品域。
- 会话可同时被多端浏览；只有 scheduler 发出的租约可以执行。客户端“接管”在 MVP 中等同于选择/注册另一个受管执行目标，不直接抢占正在运行的 lease。

## 6. 最小 API 合同

外部 API（`accounts`，Bearer 用户 token）：

```text
GET    /api/v1/namespaces
POST   /api/v1/namespaces
GET    /api/v1/namespaces/{namespaceId}/sessions?cursor=
POST   /api/v1/namespaces/{namespaceId}/sessions
GET    /api/v1/sessions/{sessionId}?after_seq=
POST   /api/v1/sessions/{sessionId}/events
POST   /api/v1/sessions/{sessionId}/task-runs
POST   /api/v1/task-runs/{runId}/cancel
GET    /api/v1/session-events?namespace_id=&after_seq=     (SSE)
```

内部 API（Accounts 与受管 Bridge 的服务身份）：

```text
POST /api/internal/task-runs/claim
POST /api/internal/task-runs/{runId}/events
POST /api/internal/task-runs/{runId}/heartbeat
```

事件首批仅需：`message.created`、`session.title_changed`、`run.queued`、`run.running`、`run.progressed`、`run.completed`、`run.failed`、`run.cancelled`。所有 event payload 必须带 schema version；客户端遇到未知事件只保留序号并重新拉 snapshot，不能猜测状态。

## 7. 仓库改造责任

| 仓库 | MVP 改动 | 不应做的事 |
| --- | --- | --- |
| `xworkmate-app` | 增加 `CloudTaskThreadStore`、Session API client、SSE sync coordinator；把现有本地 store 降为 cache；提交消息/任务时走 Session API；通过既有 workspace binding 传入 namespace，沿用既有 UI 呈现共享运行状态。 | 不保留 local/cloud 两套可执行队列；不直接拼 provider 地址；不新增 namespace UI。 |
| `xworkmate-bridge` | 增加受管 task-run dispatcher/callback adapter；将 lease/fence 写入 ACP metadata；把现有 session/task snapshot 映射为规范运行回调事件，并继续提供制品查询。 | 不把 session event store、账号权限或调度策略塞进 Bridge；不把制品上传到 Accounts/PG；不扩展 multi-agent。 |
| `accounts` | 新 migration、repository、鉴权、snapshot/event API、SSE、atomic claimer 与内部 Bridge callback 验证；复用 Postgres 运维链路。 | 不复用 billing `scheduler_decisions` 作为队列；不把 Vault/K8s namespace 当业务 namespace。 |
| UAT AI Workspace | 将任务列表/新对话/详情绑定 Session API：默认 namespace、attach、实时状态、断线恢复；按下述顺序逐步补齐 APP 功能语义。 | 不以浏览器 localStorage 作为共享状态源，也不要求 APP UI 按 Web 变化。 |
| `X-Memory-Hub` | 后续接入：memory write/search 加 `namespace_id` 服务端过滤；只由已确认 `memory_refs` 关联。 | 不把项目字符串当安全隔离；不自动跨 namespace 搜索。 |

## 8. 实施顺序与验收门槛

1. **合同与迁移**：在 `accounts` 定义 schema、OpenAPI/事件 JSON Schema、namespace 鉴权与默认 personal namespace；先写 repository/API 测试。
2. **APP 无 UI 改造的可恢复会话**：实现 session snapshot + append-only events + SSE/replay；以 runtime adapter 替换 App 状态来源，先只读 attach，再将创建/发消息切换到云端主链。不得修改 Flutter UI 文件或 golden。
3. **持久调度**：实现 `task_runs`、transactional claim、配额与取消；跑两个 namespace 的公平性及重启恢复测试。
4. **Bridge 接入**：使用服务身份、短 lease 和 fence callback 把现有 ACP/OpenClaw task snapshot 写回；完成幂等、过期回写拒绝、断桥重连测试。
5. **Web 功能对齐（分批）**：先对齐 APP 的 TaskThread 列表、新建/继续会话、消息与运行状态；再对齐取消、归档、产物和恢复；最后对齐当前 APP 已有的模型/技能/附件/设置语义。每批共享同一 API 合同，并做 Desktop ↔ Web 接续验证。
6. **显式导入与记忆引用**：仅在前五步稳定后，提供一次性本地 TaskThread 导入、受确认的记忆链接。

MVP 完成定义：

- Desktop 创建会话后，UAT Web 在同一 namespace 中可在 2 秒内通过 SSE 或回放看到同一 message/event；刷新与断网重连不重复消息。
- Flutter 的现有关键 widget/golden 与导航快照不变；同步功能仅由 runtime/repository/API 集成测试覆盖，APP 不出现新的 namespace UI。
- 在两个 namespace 各提交至少 3 个任务时，全局 active 不超过 5、单 namespace 不超过 2，且两边在有可运行任务时都能获得调度机会。
- Scheduler、Bridge 或 App 重启后，`queued/running` TaskRun 可由数据库状态恢复；同一 `taskRunId` 只被一个有效 fencing lease 终结。
- 非所有者不可读、写、订阅或取消其他 namespace/session；Bridge 不能靠客户端伪造 namespace 执行。
- OpenClaw 的当前 run 制品可由另一端用 `taskRunId + bridge_task_ref` 从 Bridge 制品域查询，且不会混入其他 session/run 的文件；会话快照本身不含制品。

## 9. 风险与先决决策

1. **UAT 后端归属**：UAT 已展示 TaskThread/专项，但需确认其服务仓库和当前数据源；接入必须切换到上述 Session API，不能做网页侧双写。
2. **执行目标**：MVP 假定任务运行在受管 Bridge。若要让任意 Desktop 成为 worker，需要单独设计设备 attestation、连通性与本地工作目录授权，不能悄悄加入本期。
3. **本地路径**：`WorkspaceBinding.workspacePath` 不能被其他设备当作可写共享路径。跨端快照只暴露安全的 display/ref，真正路径只给获得执行租约的设备。
4. **消息冲突**：MVP 只追加消息，不做 CRDT 编辑；标题等可变字段采用 `expected_version`，冲突时返回 409 并让客户端刷新。
5. **记忆隐私**：X-Memory-Hub 的当前 `project` 维度不是授权边界；未完成 namespace 过滤前，只能把它作为人工确认的辅助，不进入自动上下文。

## 10. TDD 进度记录

已落地并合并回当前分支：

- `accounts/internal/tasksession`：namespace/session/event/task-run 内存领域实现；覆盖默认 personal namespace、账号隔离、client request 幂等、16 KiB payload 限制、跨 namespace 公平 claim、namespace/global active 限制和 fencing lease。
- `accounts/sql/20260810_task_session_control_plane.sql`：`task_namespaces`、`task_sessions`、`task_session_events`、`task_runs` 四张轻量 PG 表；无 `artifacts` 表。
- `xworkmate-bridge/internal/acp/task_run_envelope.go`：校验 scheduler lease、强制注入权威 namespace/session/fence，拒绝客户端伪造或过期租约。
- `xworkmate-app/lib/runtime/session_sync_contract.dart`：轻量 snapshot、task-run 引用、事件 cursor、gap/replay coordinator；没有修改任何 UI 文件。

验证结果：

- Bridge：`go test ./...`、`go vet ./...` 通过。
- App：定向 session sync 测试、`flutter analyze` 通过；UI/widget/golden 未改动。
- Accounts：领域包测试、`go vet ./...` 通过；全仓既有 `overlayctl` E2E 因本机缺少 `xray` 二进制失败，与本切片无关。

下一条 TDD 切片必须补齐：PG repository 的事务实现、Accounts authenticated API/SSE、Bridge dispatcher/callback，以及 App 现有 controller 对 `SessionSyncCoordinator` 的接入；完成这些前不宣称跨端端到端闭环完成。
