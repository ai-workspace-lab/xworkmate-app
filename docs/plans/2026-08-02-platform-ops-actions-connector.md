# 对话式运维：Harness 插件 × 技能 × platform-ops-toolkit

日期：2026-08-02（v2，按"App 轻量、Gateway 驱动"修订）
工作仓库：`ai-workspace-lab/xworkmate-app`
技能仓库：`ai-workspace-infra/xworkspace-core-skills-ops-metadata`
目标仓库：`ai-workspace-infra/platform-ops-toolkit`
前置：`docs/tasks/2026-07-31-github-api-conversation-publisher-handoff.md`

---

## 〇、执行链

```text
对话
  → select（workflow plugin + skills）      ← 插件侧，本次扩展；选择先发生
  → plan / think                            ← 在已选定的插件与技能约束下规划
  → work                                    ← Gateway 侧执行
  → 发布连接器（结果去哪）                    ← 连接器侧，完全不动
```

选择**先于** plan/think，这决定了两件事：插件与技能是**规划的约束条件**而不是执行时才
挑的工具——agent 在 plan 阶段就已经知道自己只能动 `platform-ops-toolkit` 的 4 个
workflow、只能按 `input-rules.md` 组合参数；以及 App 只在这一个时点介入，之后整段
plan → work 都在 Gateway 侧连续跑完，App 不需要中途接管。

两条链仍然独立：本次**只往插件侧加东西**，`ConversationPublishConnectorId` 一个字节都不改。
不新增"第三条链"，也不把派发能力做成连接器——派发不是"结果去哪"，是"work 本身"。

### 边界（本方案的第一原则）

**App 不获取任何运维凭据、不发任何 GitHub Actions 请求、不实现轮询状态机。**
派发、观测、重试、证据收集全部由 Gateway 侧的 agent 执行，能力以**技能包**形式声明。
App 只做三件事：让用户选（插件 + 技能 + 交付目标）、把选择渲染成任务下发、展示回流。

这与既有约定一致：`BuiltinPluginDescriptor` 的注释已经写死"Built-in plugins are not a new
execution channel"（`lib/features/plugins/builtin_plugin_catalog.dart:23`），插件只产出
composer 模板 + `requiredSkills`，执行在 gateway workspace。本方案沿用这一条，不为运维
破例。

---

## 一、职责切分

| 层 | 归属 | 内容 |
|---|---|---|
| 意图与编排 | **Gateway agent** | 对话 → plan → 参数推导 → 预检 → 派发 → 轮询 → 验收 → 报告 |
| 能力与规则 | **技能包**（新建） | workflow 输入 schema、非法组合规则、危险动作清单、验收探针、runbook |
| 凭据 | **Gateway 主机** | `gh` 认证 / GitHub App token；App 侧永不出现 |
| 选择与呈现 | **App** | 插件目录项、技能依赖展示、交付目标绑定、下发、回流渲染 |
| 结果外发 | **App（既有）** | GitHub API 发布连接器，不变 |

App 侧新增的 Dart 代码量应当接近于零业务逻辑：一个插件描述符 + 一次 `requiredSkills`
声明。凡是需要写"如果 A 则 B"的地方，都应该写进技能包，而不是写进 Dart。

---

## 二、技能包设计（Gateway 侧的真正主体）

新建 `skills/operations-management/platform-ops-delivery/`，与既有
`service-catalog-and-runbook-standard`、`network-dns-tls-edge-management` 同级同构
（`SKILL.md` + `references/` + 可选 `agents/`）。

```
platform-ops-delivery/
├── SKILL.md                      # 何时触发、执行纪律、人工确认点
├── references/
│   ├── workflow-catalog.yaml     # 4 个 workflow 的输入 schema + 默认值 + 危险度
│   ├── input-rules.md            # 非法组合与强制覆盖规则（见 §3.3）
│   ├── preflight.md              # 派发前必须先查什么
│   └── verification.md           # 派发后验收什么（不止看 run 绿）
└── agents/
```

`SKILL.md` 的执行纪律至少要写死四条：

1. **先复述后执行**：把最终 inputs 逐字段列给用户，等明确确认再派发。危险字段
   （`confirm_dns_switch`、`action=destroy`、`vault_env_path=prod`、`toolkit_action=restore`）
   需要用户复述该字段本身，不接受"好/继续"这类泛化同意。
2. **预检不通过就不派发**：见 `preflight.md`，把 CI 里 20 分钟后才 `exit 1` 的错误提前到
   派发前。
3. **run 绿 ≠ 事情做成**：必须按 `verification.md` 取独立证据（详见 §4）。
4. **只碰白名单内的 workflow**，不代用户新建分支、不改 gitops、不改 Vault。

### 2.1 为什么规则放技能包而不是 Dart

- 上游 workflow 的输入随时会变（`platform-ops.yaml` 近一个月改过多次）。技能包改一行
  Markdown 就生效；Dart 要发版。
- 同一套规则 gateway 侧 agent 和人都要读，Markdown 是共同格式。
- App 一旦持有规则就等于持有了运维语义，下一步必然被要求持有凭据。切在这里最干净。

---

## 三、目标 workflow 的事实核查（写 `workflow-catalog.yaml` 前必须先认账）

### 3.1 `cron-rotate-domain-tls-certs.yaml` —— 零输入，第一个打通

- `workflow_dispatch:` **没有任何 inputs**，派发体只有 `ref`。
- `VAULT_ROLE: github-actions-platform-ops-toolkit-prod`，该 role 现绑
  `["refs/tags/v*", "refs/heads/main"]`（`docs/tasks/vault_auth_split.sh:331-334`），
  **从 main 派发可以认证**。旧笔记"prod 只绑 release/*"已过期。
- 没有参数 → 价值全在观测与验收，正好用来验证骨架而不被表单问题干扰。

### 3.2 `daily-main-snapshot.yaml` —— 4 个输入，其中一个是死的

| input | 类型 | 现状 |
|---|---|---|
| `snapshot_tag` | string | 留空 → `daily-build-$(date -u +%Y.%m.%d)` |
| `snapshot_source_ref` | string | **死输入** |
| `deploy_env` | choice sit/uat/prod | 默认 uat |
| `repositories` | string，逗号分隔 | 留空 → 默认 5 个业务仓 |

- **`snapshot_source_ref` 从未生效**：workflow 把它作为 `SNAPSHOT_REF` 传进 step
  （`daily-main-snapshot.yaml:81`），但 `.github/scripts/tag-daily-main-snapshot.sh:26`
  写死 `args=(--tag "${tag}" --ref main ...)`，从不读它。
  → catalog 里标 `exposed: false`，技能须主动告诉用户"这个参数不会生效"。
- tag 命名两套并存：脚本默认产出**不带环境前缀**的 `daily-build-YYYY.MM.DD`，
  `tag-ai-workspace-mains.sh:86` 的 `infer_deploy_env_from_tag` 对无前缀 tag 兜底成 `uat`；
  另一套运维约定是 `uat-daily-build-YYYY-MM-DD-rN`。两者命中**不同的** Vault role
  bound_claims。→ 默认留空用 workflow 自己的默认值，不替用户发明 tag。
- 跨 4 个 org 的矩阵，`wait-daily-snapshot-builds.sh` 还要等下游构建 → 单次 run 是分钟级
  甚至更久，轮询节奏要按此设计。

### 3.3 `platform-ops.yaml` —— 约 20 个输入，危险项最多，放最后

以下都是路由脚本
（`.github/scripts/platform-ops_provision_route-ref-to-an-explicit-profile.sh`）
和 workflow 头部的硬逻辑，必须原样写进 `input-rules.md`：

1. `run_application_deploy=true` 必须同时 `run_infrastructure=true`，否则脚本 `exit 1`
   （inventory/CMDB 是 provision 阶段才生成的）。
2. `run_full_stack=true` **强制覆盖**上面两个开关并打开 DNS 发布。
3. `action=destroy` 强制 `run_infrastructure=true` / `run_application_deploy=false`，
   不受复选框影响。
4. `deploy_tag` **必填**，且 CD 是 pull-only：传一个 gitops 没 pin 的 tag 会在 Deploy Web
   SaaS 阶段**主动 fail**（`gitops pins 'latest', requested '<tag>'`）。这是设计内守卫。
5. `concurrency.group: deploy-env-migration` + `cancel-in-progress: false` → 全局串行排队，
   "排队中"不是卡死。
6. `switch_dns` job 挂 `environment: production`（需环境审批）且要求
   `confirm_dns_switch == 'true'`。

### 3.4 任务 1 的直接回答：**是的，两台；web-saas 2C4G，agent-proxy 1C2G**

但成因不是矩阵，别记错：

- `iac_modules/.../config/resources/uat/web-saas.yaml` 的 host plan 是
  `{{ env.get('INSTANCE_PLAN_API', 'vc2-4c-8gb') }}` → 传 `2C4G` 渲染成 `vc2-2c-4gb`。
- `.../uat/agent-proxy.yaml` 的 host plan **硬编码 `vc2-1c-2gb`**，根本不读
  `INSTANCE_PLAN_API`，所以永远 1C2G。
- `platform-ops_provision_map-instance-plan.sh` 里"agent-proxy 默认 1C2G"的特判
  **本场景不触发**——它要求 `target_domains == "agent-proxy"` 且 `plan == "4C8G"`。

**必须在确认环节说清的 state 边界**：`target_domains="web-saas + agent-proxy"` 走
`rf="web-saas-agent-proxy"`，workspace `uat-vultr-vps-platform-ops-toolkit-web-saas-agent-proxy`、
state key `uat/vultr-vps/platform-ops-toolkit/web-saas-agent-proxy.tfstate`——与 `all` /
`web-saas` 用的 `...-web-saas` **不是同一份 state**。所以这是**新建两台**，不是给现有
`console-uat` 加一台 agent-proxy。

"发布 DNS 验证"要拆成两件事：
- 常规 `observe_web_saas` job **不看** `confirm_dns_switch`，用 `OBSERVE_RESOLVE_IP` 把域名
  钉到本次部署的 IP 验收，DNS 没切也能跑；
- `switch_dns` 才是改 Cloudflare 记录 + 切流量，需 `confirm_dns_switch=true` 且过
  `production` 审批。默认**不替用户勾**。

### 3.5 `data-migration.yaml`

同时有 `workflow_call` 与 `workflow_dispatch` 两套 inputs（字段同名但类型不同：call 是
string，dispatch 是 choice）。catalog 只建模 dispatch 版。
`toolkit_action=restore` + `vault_env_path=prod` 是最危险的组合。

---

## 四、验收：run 绿不等于事情做成（`verification.md` 的由来）

这套流水线的历史故障几乎全是"绿而未成"，所以技能包必须为每个 workflow 声明**独立于
run 结论的证据**：

- **建库/部署**：`ansible-playbook --list-hosts` 命中数为 0 仍 `exit 0` 是已发生过的事故
  形态（`--limit` 与 playbook `hosts` 求交为空）。验收要落到端点：
  `accounts-uat.onwalk.net/api/account/service-readiness` 返回 **401** 才算通
  （`/` 返回 404 是正常的，该服务只挂 `/api/*`）；console 可在主机内
  `docker exec web-saas-caddy wget -qS -O /dev/null http://console:3000/` 看 200。
- **证书轮换**：run 绿不代表证书换了。要查实际证书有效期；`console-uat` 撞过 Let's
  Encrypt duplicate-certificate 限流（5 次/168h），限流期内**任何重跑都无效**，技能须
  识别 429 并直接告诉用户"等窗口"，而不是建议重试。
- **快照打 tag**：`wait-daily-snapshot-builds.sh` 曾把失败状态写进 JSONL 却 `exit 0`
  （已修）。验收要核对每个仓的 release assets 是否真的存在。

---

## 五、App 侧要动的（尽量少）

1. `ConversationPluginId` 增加运维插件项（与 `harnessWorkflow` 并列，或作为 Harness 的一个
   预置 workflow 定义），其 `BuiltinPluginWorkflow.steps` 就是
   plan → preflight → confirm → dispatch → watch → verify → report 七步，
   `requiredSkills: ['platform-ops-delivery']`。步骤的
   `failurePolicy` 全部设 `abort`——运维步骤没有"降级继续"这回事。
2. 交付目标沿用既有 `HarnessTarget`：`org=ai-workspace-infra`、
   `project=platform-ops-toolkit`，`environments[].deploy = ghWorkflowDispatch`（枚举本来
   就有，此前无人使用），`healthProbe` 填 §4 的探针。
   `effectiveRequiresHumanGate` 已经把 tag 触发的环境强制为人工确认，直接复用。
3. `renderHarnessDeliveryContextBlock` 已经会把 org/repos/environments 渲进提示词，
   不需要新的上下文通道。
4. 发布链、连接器设置页：**不动**。

不做的事：不加 Actions token 输入框、不加 REST 客户端、不加 run 轮询状态机、不在 Dart 里
写输入校验规则。

---

## 六、交付批次

| 批次 | 主体 | 内容 | 验收 |
|---|---|---|---|
| **B0** | 技能仓 | 建 `platform-ops-delivery` 骨架 + `workflow-catalog.yaml` 的 3.1 部分 | gateway 侧手动对话能派发证书轮换并给出验收结论 |
| **B1** | App | 插件描述符 + `requiredSkills` + 交付目标预置 | 从对话页选中该插件即可复现 B0 的链路，App 无新增网络请求 |
| **B2** | 技能仓 | 补 `daily-main-snapshot`（含 `exposed:false` 死输入提示）+ 长时轮询纪律 | 打 tag 全流程 + 逐仓 release assets 核对 |
| **B3** | 技能仓 | 补 `platform-ops` 全量输入 + `input-rules.md` + `preflight.md`（gitops pin 预检） | 非法组合在派发前被拦、危险字段需复述确认 |
| **B4** | 技能仓 | 补 `data-migration`；把 §4 的三类验收固化 | restore/prod 组合被标危险并要求复述 |
| **B5** | 上游 | 提 PR 修 `snapshot_source_ref` 死输入 | 输入生效或被删除 |

B0/B1 先各一个批次，是为了验证"技能包换一行即生效、App 不需要跟着发版"这个判断成立；
成立之后 B2-B4 全部落在技能仓，App 不再改动。

---

## 七、三个目标任务的最终参数

**任务 1 · 拉起 UAT web-saas + agent-proxy**
```
workflow: platform-ops.yaml    ref: main
vault_env_path=uat, target_domains="web-saas + agent-proxy",
cloud_provider=vultr-vps, instance_plan=2C4G, action=deploy,
run_infrastructure=true, run_application_deploy=true,
target_domain_base=onwalk.net, deploy_tag=<gitops 已 pin 的值>,
confirm_dns_switch=false
```
确认环节须复述：两台主机（`vc2-2c-4gb` / `vc2-1c-2gb`）、**独立 state = 新建而非扩容**、
`deploy_tag` 预检结果、DNS 只做 observe 不切流量。

**任务 2 · 发版打 tag**
```
workflow: daily-main-snapshot.yaml   ref: main
deploy_env=uat；snapshot_tag 留空；repositories 留空；snapshot_source_ref 不暴露
```

**任务 3 · 轮换证书**
```
workflow: cron-rotate-domain-tls-certs.yaml   ref: main   （无输入）
```

---

## 八、待决策

1. Gateway 侧凭据形态：复用现有 `gh` 登录，还是给运维单独一个 GitHub App？后者可以把
   `actions:write` 限死在 platform-ops-toolkit 一个仓。
2. `confirm_dns_switch` / `action=destroy` 要不要**根本不进技能包白名单**（只允许人去
   GitHub 页面手动跑）？这是最省事也最安全的一刀。
3. `deploy_tag` 的 gitops pin 预检需要读 `ai-workspace-infra/gitops`，是否给 gateway 侧
   凭据加这个仓的读权限。

---

## 九、本仓工程约束

- 分支前缀逐字匹配：进 `main` 只接受 `feature/` `bugfix/` `cherry-pick/`。
- 已知失败基线（非本次引入）：`flutter test` 全量 6 个 mobile golden/page 用例失败；
  `build-and-release.yml` 在所有分支都 failure。开 PR 时如实写明。
- widget 测试默认 `TargetPlatform.android`，desktop-only feature flag 会解析成 false。
- 推送走 HTTPS URL（本机 `known_hosts` 无 github.com 条目）。
