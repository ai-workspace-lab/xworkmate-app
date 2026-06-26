# Gateway Turn 稳定性与健壮性｜全链路分析与编码改进规划

> 适用目录：`xworkmate-app/docs/cases/`
>
> 相关仓库（`/Users/shenlan/workspaces/`）：
> - `ai-workspace-infra/`（Caddy 入口、OpenClaw gateway 部署、playbooks）
> - `ai-workspace-lab/`（`xworkmate-app` Flutter 客户端、`xworkmate-bridge` Go 网桥）
> - `ai-workspace-service/`（accounts / console / litellm 等旁路服务）
>
> 触发现象：任务进度条 `任务运行中...` 永不结束、`停止` 无效，**实际 OpenClaw gateway 已执行完毕**；
> 伴随报错 `Bridge 响应读取中断，本轮结果未完成。错误码：ACP_HTTP_CONNECTION_CLOSED`。

---

## 1. The full chain (one gateway turn)

一次 gateway turn 的完整时序：

```
App turn ──SSE POST──▶ Bridge http_handler ──▶ handleRequest ──▶ OpenClaw gateway submit
  (executeTask)         (text/event-stream)      (阻塞 6min/60min)   (WS 127.0.0.1:18789)
       │                      │                        │
       │   keepalive 20s ◀────┘                        ▼
       │                              返回 "running task handle"(runId + artifactScope)
       ▼                                               │
  persist association ──▶ pollOpenClawTaskAssociationInternal (tasks.get 每 2s)
                                       │
                          isOpenClawRunningTaskHandle? ──yes──▶ persist + continue ──┐
                                       │                                              │
                                       no ──▶ applyGatewayChatResult (terminal)       └─ ∞ (无 deadline)
```

完成信号（completion signal）只活在**两个脆弱位置**：

1. **带内 SSE 结果帧**（result envelope / `[DONE]`）—— 依赖那条长连接活到任务结束；
2. **Gateway 对 `tasks.get` 的内存态应答** —— 依赖 bridge↔gateway 的 WS 连接仍持有该 run 的状态。

截图场景里这两条同时被打断，于是"任务跑完了，但客户端永远收不到终态"。

关键代码锚点：

| 环节 | 位置 |
|---|---|
| App 发起 SSE turn | `xworkmate-app/lib/app/app_controller_desktop_thread_actions.dart:644` (`executeTask`) |
| Bridge SSE handler / keepalive 20s | `xworkmate-bridge/internal/acp/http_handler.go:198-283`、`:19` |
| Bridge 阻塞等待 gateway（6min 默认 / 60min 上限） | `xworkmate-bridge/internal/acp/orchestrator.go:31-33` |
| Bridge↔Gateway WebSocket（dial 18789） | `xworkmate-bridge/internal/gatewayruntime/runtime.go:372-376` |
| App 持久化 + 轮询 run | `app_controller_desktop_thread_actions.dart:680-693`、`:747` |
| running handle 判定 | `xworkmate-app/lib/runtime/go_task_service_client.dart:519` |
| 进度条 phase（仅看 pending） | `xworkmate-app/lib/widgets/assistant_task_progress_bar.dart:190` |

---

## 2. 三仓库端到端拓扑（实测自代码）

```
┌─ ai-workspace-lab/xworkmate-app  (Flutter)
│     executeTask → SSE POST  Accept: text/event-stream
▼
┌─ ai-workspace-infra  Caddy 入口  xworkmate-bridge.svc.plus
│     handle /acp*  : flush_interval -1 ✓   read_timeout 30m   write_timeout 30m   keepalive 5m
│     handle /api*  : (Caddy 默认超时, 无 flush_interval) ⚠
│     handle /      : (Caddy 默认) ⚠
▼
┌─ ai-workspace-lab/xworkmate-bridge  (Go)
│     SSE handler  keepalive 20s  →  handleRequest 阻塞 6min(默认)/60min(max)
│     gatewayruntime: WebSocket → 127.0.0.1:18789  (pending map 绑定在连接生命周期上)
▼
┌─ ai-workspace-infra  deploy_gateway_openclaw  (roles/vhosts/gateway_openclaw)
│     OpenClaw gateway runtime, WS 18789
▼
   OpenClaw 执行 → artifacts → tasks.get 回查
```

旁路（`ai-workspace-service`）：`accounts.svc.plus`（登录 / Token）、`console.svc.plus`（自带 openclaw assistant route）、`litellm` / `AI-Relay-Kit` / `codex-relay`（模型出口）、`qmd`（记忆）。
它们不在本次卡死主链上，但 **Token 失效 / 出口异常会以同样的"连接中断"形态**表现出来，排查时需先用 `runId` 区分是主链断还是旁路断。

入口配置出处：`ai-workspace-infra/playbooks/roles/vhosts/xworkmate_bridge/templates/xworkmate-bridge-site.caddy.j2`
Gateway 部署出处：`ai-workspace-infra/playbooks/deploy_gateway_openclaw.yml` → `roles/vhosts/gateway_openclaw/`

---

## 3. 跨层失效点清单（按链路从上到下）

| # | 层 | 失效描述 | 证据 |
|---|---|---|---|
| ① | App | running 轮询分支**无 deadline / 无 maxAttempts**；只要 `tasks.get` 一直回 `running` 就永远轮询 | `app_controller_desktop_thread_actions.dart:788-794`（对比 `:831` 的 artifact-sync 分支**有**封顶 `openClawArtifactSyncLimitReachedInternal`） |
| ② | App | 进度条 phase 仅由 `pending` 驱动，而 `pending` 被该 loop 独占持有，loop 不退出 = 永远 `任务运行中...` | `assistant_task_progress_bar.dart:190`；`pending` 源 = `aiGatewayPendingSessionKeysInternal` |
| ③ | App | `停止`（abortRun → cancelAssistantTaskForSessionInternal）只向 gateway 发 `tasks.cancel`，**从不本地清 `pending`**；gateway 不可达 / run 已丢时为空操作 → 永远停不下 | `app_controller_desktop_thread_actions.dart:1793-1809` |
| ④ | **入口 / Bridge 超时错配** | Caddy `/acp*` `read/write_timeout 30m`，但 bridge `openClawAgentWaitMaxTimeout = 60min`。**>30min 的 complex_chain_task，SSE 在入口被掐断**，而 gateway 仍在跑 → `ACP_HTTP_CONNECTION_CLOSED` | caddy.j2 `read_timeout 30m` vs `orchestrator.go:32` |
| ⑤ | 入口 | 仅 `/acp*` 有 `flush_interval -1` 与长超时；`/api*`、`/` 用 Caddy 默认（短超时、无即时 flush），任何走这两条的流式 / 轮询都更脆 | caddy.j2 |
| ⑥ | **Bridge↔Gateway WS 关联绑定连接** | WS 一抖，`onConnLost` 把**所有在途请求**立即判 `SOCKET_CLOSED`——包括 OpenClaw 仍在执行的那个 run；重连后无任何 pending 复关联 | `gatewayruntime/runtime.go:802-823`、`:935-938`（`takePendingLocked` 清空） |
| ⑦ | **Bridge 无持久 run 仓** | 同步 SSE 路径不落 `xworkmate.jobs.*`，结果只活在内存 `responseCh`；连接一断即丢（已存在 jobs.submit/get/list 未被 gateway submit 复用） | `rpc_handler.go:73`（jobs.*）vs http_handler 同步路径 |
| ⑧ | Gateway 重连丢 run 态 | 重连到新 WS 后 `tasks.get` 经 `ensureProductionGatewayConnected` 落到新连接，查不到 terminal → 回 stale `running` 或 `not_found` | `rpc_handler.go:143-175` |
| ⑨ | Bridge | `gatewayRPCError` 把可重试错误统一映射为 `OPENCLAW_GATEWAY_SOCKET_CLOSED`，但缺少"run 仍在后台、稍后可查"的语义，客户端只能当硬失败 | `orchestrator.go:1678-1702` |

---

## 4. 根因链（Root cause）

> "实际 gateway 已执行完毕，但任务永远停不下" =
>
> **服务端把已完成的结果弄丢（⑥ + ⑦ + ⑧）** ：bridge↔gateway 的请求关联随 WS 连接销毁、且无持久副本，run 完成事件投递到已被放弃的 channel；重连后无法复关联。
>
> **+ 客户端把"无限 running"固化（① + ② + ③）** ：轮询无截止、进度条只看 pending、停止不本地生效。
>
> **+ 触发器（④ / ⑤）** ：长任务在入口 30min 处必断，把链路推向上述失效（尤其 complex_chain_task budget=60min）。

最小可复现路径：
1. 提交一个 budget > 30min 或网络抖动概率高的 gateway 任务；
2. SSE 在入口（30min）或 WS（瞬断）处断开 → App 收 `ACP_HTTP_CONNECTION_CLOSED`；
3. OpenClaw 后台继续跑完，但 bridge 已丢失该 run 的 pending / 无持久记录；
4. App 落入 running 轮询（或失败后仍 pending），`tasks.get` 拿不到 terminal；
5. 进度条永远 `任务运行中...`，`停止` 不本地生效 → 卡死。

---

## 5. 编码改进规划（Stability / Robustness TODO）

> 排序原则：先**当天可上、零协议变更**的止血项（L0 配置 + L2 客户端），再**治本**的服务端持久化（L1），最后横切可观测性（L3）。
> 每项标注：所属仓库 · 改动面 · 验收要点。

### L0 入口配置（ai-workspace-infra · 改配置即可 · 当天可上）

- [ ] **T1 对齐入口与 bridge 的超时上限**
  `caddy.j2` `/acp*` 的 `read_timeout` / `write_timeout` 提到 **≥ bridge `openClawAgentWaitMaxTimeout`（60min）+ 余量**。
  最好让入口超时与 `orchestrator.go` 的上限**由同一变量 / 同源常量**渲染，避免再次漂移。
  验收：budget=60min 的 complex_chain_task 全程 SSE 不被入口掐断。

- [ ] **T2 收敛 / 补齐非 /acp 路由的流式配置**
  给 `/api*`（及任何承载 `tasks.get` 轮询、流式响应的路由）补 `flush_interval -1` + 同样长超时；或显式把所有 gateway 流量收敛到 `/acp*`。
  验收：轮询 / 流式不再依赖 Caddy 默认短超时。

### L2 App 客户端止血（ai-workspace-lab/xworkmate-app · 纯客户端 · 零协议变更）

- [ ] **T3 running 轮询加硬截止**
  在 `pollOpenClawTaskAssociationInternal` 的 running-handle 分支（`thread_actions.dart:788`）引入 deadline / maxAttempts，复用 bridge 下发的 `deadlineAt`（`openclaw_async_tasks.go:92`）+ grace；到点落 `interrupted`（可恢复态，`isRecoverableAssistantTaskStateInternal` 已支持），退出 loop。
  参照同函数 `:831` artifact-sync 分支的封顶写法 `openClawArtifactSyncLimitReachedInternal`。
  验收：gateway 始终回 `running` 时，客户端在 deadline 后必终止，不再无限轮询。

- [ ] **T4 `停止` 本地权威化**
  `abortRun` / `cancelAssistantTaskForSessionInternal`（`:1793`）改为：**先**乐观清 `aiGatewayPendingSessionKeysInternal`、置 lifecycle=`aborted`、退出 loop，**再** best-effort 发 `tasks.cancel`。UI 终止不得依赖 gateway 往返。
  验收：gateway 不可达时点 `停止` 仍能立刻停下。

- [ ] **T5 传输中断降级为"后台续跑·重连中"**
  收到实时 `ACP_HTTP_CONNECTION_CLOSED` 时，不直接当硬失败把任务留在 running，而是降级为"已转后台 / 重连中"，触发 `resumeOpenClawTaskAssociationsInternal`（`:906`，目前仅在 thread 加载时触发）续轮询。
  验收：SSE 瞬断后，任务能自动恢复轮询并最终拿到终态或明确终止。

- [ ] **T6 失败路径与 pending 清理一致性**
  审计 `applyGatewayChatFailureInternal`（`:1613`，置 `ready` 但不清 pending）与调用方 `finally`（`:715` 仅 `!handedOffToBridgeTask` 才清 pending）之间的竞态，确保任一终态路径都能确定性地清 pending，杜绝"错误已渲染但仍 running"。
  验收：失败 / 中断 / 取消三类终态后，`pending` 必为 false。

### L1 Bridge 持久化（ai-workspace-lab/xworkmate-bridge · 根因修复 · 有协议/状态面改动）

- [ ] **T7 run 关联与 WS 连接解耦**
  维护 `runId → {status, result, artifacts, deadline}` 的持久 / 独立登记表，由 gateway notification 更新。`onConnLost`（`runtime.go:802`）时**不要把长任务 pending 直接判死**，而是标记 `detached`，重连后用 `runId` 复关联 / 回放完成事件。
  验收：WS 瞬断 + 重连后，已完成的 run 仍能被 `tasks.get` 查到 terminal + artifacts。

- [ ] **T8 OpenClaw submit 接入 `xworkmate.jobs.*` 持久存储**
  让 gateway submit 落 `xworkmate.jobs.*`（`rpc_handler.go:73` 已有 submit/get/list/stats），使结果不再只活在内存 `responseCh`。
  验收：bridge 重启 / 连接抖动后，结果与 artifacts 仍可检索。

- [ ] **T9 服务端 DeadlineAt 兜底终态**
  run 过期且 gateway 无法确认时，bridge 主动回 terminal `interrupted`（而非无限 `running`），给客户端确定终态。与 T3 客户端 deadline 形成双保险。
  验收：gateway 失联超过 budget 后，`tasks.get` 返回确定 terminal。

- [ ] **T10 错误语义细化**
  `gatewayRPCError`（`orchestrator.go:1678`）区分"连接断但 run 仍在后台可查" vs "run 确实失败"，前者携带 `runId` + `retryable/poll` 提示，供客户端走 T5 续轮询而非硬失败。
  验收：客户端能据错误语义区分"重连续跑"与"真失败"。

### L3 可观测性（横切 · infra/service/lab）

- [ ] **T11 端到端贯穿 runId**
  App 日志 → Caddy access log → bridge SSE 日志（已有 `component=acp_sse`，`http_handler.go:221`）→ gateway run，全链路带同一 `runId`，便于定位"入口断"还是"WS 断"。
  验收：任一 `runId` 可在四层日志串联。

- [ ] **T12 关键指标 + 告警**
  bridge 暴露：`SOCKET_CLOSED 在途任务数`、gateway WS 重连计数、running 轮询超 deadline 计数。
  验收：⑥ 类事件发生即在监控可见，无需靠用户截图。

---

## 6. 落地顺序建议

1. **当天止血**：T1 + T2（入口配置）+ T3 + T4 + T6（客户端），消除"30min 必断 / 路由漏配 / 无限 running / 停不掉"。
2. **本周治本**：T7 + T8 + T9（bridge 持久化与解耦），让"gateway 跑完 = 结果一定拿得到"。
3. **跟进**：T5 + T10（断连续跑语义）、T11 + T12（可观测性）。

> 回归对照：本目录 `00-review-env-and-matrix.md` 第 2 节"通用验收标准"中"长任务执行期间状态流 / 取消 / 重试稳定""同一任务重复执行 3 次不卡死"，即本规划的回归出口。
