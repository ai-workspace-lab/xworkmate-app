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

> **结论速览（2026-06-26 live 验证后）**
> - **「采集AI资讯无法产出」的主根因**＝OpenClaw 网关启动时**未加载 `openclaw-multi-session-plugins` 插件**（插件文件在临时路径，网关启动早于文件就位），导致 `xworkmate.*` 网关方法全部 `unknown method`。重启网关即恢复（详见 §4「2026-06-26 决定性根因」）。
> - 本文 §3/§5 的 **T1–T9** 是**健壮性加固**（入口超时、客户端 deadline/停止、bridge 持久 run 仓），用于让上述故障表现为「有界可恢复」而非「无限运行/丢结果」——它们正确且应保留，但**不是**该故障的根因修复。
> - ⚠️ 作废：早期「`xworkmate.*` 协议命名空间漂移、需 bridge 改原生 `tasks.get`」的判断**错误**，`fix/gateway-task-protocol-alignment` 分支不要合并。

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
| ⑩ | **运行态 ≠ 源码（主根因，见 §4）** | 报 `unknown method: xworkmate.*` 时，根因通常是**网关未加载 `openclaw-multi-session-plugins` 插件**（这些方法由插件注册）；次因是本机 `launchd` 的 bridge 二进制为旧构建 | 网关启动日志 `N plugins` 是否含 `openclaw-multi-session-plugins`；`openclaw plugins inspect`；`curl /api/ping` 的 `commit` |

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

### 2026-06-26 本机联合调试结论

本次现场环境：

- App：`Version 1.1.4`，应用构建 commit `fb7e0ac`。
- 本地 Bridge：`http://127.0.0.1:8787`，launchd 服务 `plus.svc.xworkspace.bridge`。
- OpenClaw gateway 控制台：`http://127.0.0.1:18789/channels`。

实际复现：

```bash
curl -sS -X POST http://127.0.0.1:8787/acp/rpc \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer $BRIDGE_AUTH_TOKEN' \
  --data '{"jsonrpc":"2.0","id":"probe","method":"xworkmate.session.prepare","params":{"openclawSessionKey":"probe-session","runId":"probe-run","workspaceDir":"/tmp/xworkmate-probe","gatewayProviderId":"openclaw"}}'
```

修复前返回：

```json
{"error":{"code":-32601,"message":"unknown method: xworkmate.session.prepare"},"ok":false}
```

结论：这不是 OpenClaw gateway 控制台 `18789` 的页面问题，也不是 App 展示误判；`/acp/rpc` 上 `acp.capabilities` 正常而 `xworkmate.session.prepare` 不认识，说明本地 Bridge 运行态没有加载到包含 `handleSessionPrepare` 的新二进制。源码中 `rpc_handler.go` 和 `orchestrator.go` 已有 fallback，但 `/usr/local/bin/xworkmate-go-core` 仍是旧/无元信息构建。

现场处理：

1. 在 `xworkmate-bridge` 当前源码重建 `xworkmate-go-core`。
2. 备份并替换 `/usr/local/bin/xworkmate-go-core`。
3. macOS 上移除 `com.apple.provenance` / quarantine 并 `codesign --force --sign -`，否则 launchd 会以 `OS_REASON_CODESIGNING` 拒绝启动。
4. 重载 `plus.svc.xworkspace.bridge`。

修复后探针：

```json
{
  "ok": true,
  "payload": {
    "fallback": true,
    "compatibilityMode": "local-session-prepare",
    "artifactScope": "tasks/probe-session/probe-run",
    "artifactDirectory": "/tmp/xworkmate-probe/tasks/probe-session/probe-run"
  }
}
```

回归要求：每次本地替换 Bridge 后，先用 `/api/ping` 确认 `commit`，再用上面的 `xworkmate.session.prepare` 探针确认返回 `ok:true`；不能只看 App 设置页的 `Status: ok`。

### 2026-06-26 决定性根因（已 live 验证）：OpenClaw gateway 未加载 `openclaw-multi-session-plugins` 插件

> 四层调用链（与 `openclaw-gateway-e2e-regression/ROOT_CAUSE_ANALYSIS.md` 一致）：
> `App → xworkmate-bridge(Go) → openclaw-multi-session-plugins(TS 插件) → OpenClaw gateway runtime(127.0.0.1:18789)`

**`xworkmate.*` 系列网关方法不是「虚构/漂移」的——它们由 `openclaw-multi-session-plugins` 插件在运行时注册**：
`index.ts` 里 `api.registerGatewayMethod("xworkmate.session.prepare" | "xworkmate.tasks.get" | "xworkmate.artifacts.export" | ".list" | ".read" | ".collect-and-snapshot")`。所以 bridge 发 `xworkmate.tasks.get` 是**正确契约**，前提是该插件被网关加载。

现场实际故障：**运行中的网关没有加载这个插件**，于是所有 `xworkmate.*` 都回 `unknown method`。证据链：

- 网关启动日志：`2026-06-23` 前每次都是 `listening (6 plugins: … openclaw-multi-session-plugins)`；**`2026-06-26 09:21:14` 那次只有 `5 plugins`，缺了 multi-session**。
- 插件注册的源路径是**临时目录** `/private/tmp/openclaw-multi-session-plugins/dist/index.js`；该文件直到 `18:40` 才被填充——**晚于网关 09:21 启动约 9 小时**。启动时路径不存在 → 插件未加载。
- `openclaw plugins inspect` 警告：`loaded without install/load-path provenance; treat as untracked local code`（无 install 记录的本地代码）。

**修复（已 live 验证通过）**：`launchctl kickstart -k gui/$UID/ai.openclaw.gateway` 重启网关（此时插件文件已就位）→ 日志变 `listening (6 plugins: … openclaw-multi-session-plugins)`；`xworkmate.*` 方法的报错从 `unknown method` 变为**插件内部参数校验**（`xworkmate.session.prepare → appThreadKey required`、`xworkmate.tasks.get → artifactScope does not match sessionKey/runId`）——证明方法已注册、插件正在处理请求。

> ⚠️ **更正**：此前一版本文档曾判为「bridge↔gateway `xworkmate.*` 协议命名空间漂移、需在 bridge 侧改原生 `tasks.get`/`artifacts.*`」——**该结论错误**，源于当时未发现 `openclaw-multi-session-plugins` 插件提供这些方法。对应的 `fix/gateway-task-protocol-alignment` 分支（native 重命名）**作废、不得合并**；bridge 原有 `xworkmate.*` 协议是对的。

#### 残留与加固项

- **插件安装路径必须稳定**：当前注册在 `/private/tmp/…`（重启 / tmp 清理即丢，正是本次故障诱因）。应用 `openclaw plugins install <stable-path>` 从 `~/.openclaw/extensions/openclaw-multi-session-plugins/` 或仓库路径重装，落正式 install 记录，避免再次「启动早于插件就位」。
- **会话面**：现场 console 的 `…:dashboard:bcde1b0f…` 与提交的 `…:draft:…` 不同面；task 建在 `draft`（requesterSessionKey），dashboard 仅是 console 自带会话视图，非断点。
- **手工探针注意**：直接构造 `tasks.get` 时 `sessionId` 不要预带 `agent:main:` 前缀——bridge 会再加一层导致 `agent:main:agent:main:…` 双前缀，触发插件的 `artifactScope does not match sessionKey/runId`。app 正常路径传 `draft:<id>`，bridge 补一层。

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

> ✅ T7/T8/T9 已实现（本地验证 commit `2333c3e`，需确保运行态 `/api/ping.commit` 与发布 commit 对齐）。
> 实现取舍：**复用已存在的 per-session 持久 store**（`s.sessions[sessionID]` 内的 `task`/`openClaw`/`lastResult`，生命周期独立于 bridge↔gateway WebSocket），把 `tasks.get` 从「强依赖 gateway 应答」改造为「优先用持久 run 仓兜底」。
> 新增 `internal/acp/openclaw_run_registry.go`（+ `_test.go`），改动 `rpc_handler.go: handleTaskGet` 与 `orchestrator.go: startOpenClawGatewayTask`。

- [x] **T7 run 关联与 WS 连接解耦** — `openClawTaskGetGatewayUnconfirmedFallback`（`openclaw_run_registry.go`）
  gateway 无法确认（unavailable / socket closed / not_found）但 run 仍在预算内时，按 `runId` 从持久 session store 合成 `running` 句柄让客户端继续轮询，跨越瞬时抖动。
  **取舍**：未直接改 `gatewayruntime.onConnLost`（`runtime.go:802`）的 pending 判死逻辑——在途请求被判死后会以 gateway error 冒泡到 `handleTaskGet`，新兜底按 runId 续轮询到 deadline 已等价覆盖，且风险远低于重写连接层 pending 关联。chat.send 初次提交若 WS 中断则尚无 runId、无可复关联，客户端重发即可。
  验收：WS 瞬断 + 重连后，已完成的 run 仍能被 `tasks.get` 查到 terminal + artifacts（见 `TestGatewayUnconfirmedFallbackWithinBudgetKeepsPolling`）。

- [x] **T8 终态结果落持久 run 仓** — `cacheOpenClawTaskGetResultIfTerminal` / `cachedTerminalForRunLocked`
  gateway 确认终态后，把**最终客户端形态**（已 decorate 下载 URL + strip 内联内容）缓存进 `sess.lastResult`，后续轮询直接回放，gateway 之后查不到也不丢。带 `runId` 校验 + 新 turn 复用 session 时重置 `ProgressTerminal`，防旧 run 终态错配新 run。
  **取舍**：未新建独立 `xworkmate.jobs.*` 落库；现阶段复用 per-session 内存 store（已满足「跨 WS 抖动不丢结果」）。bridge **进程重启**后仍会丢——若需跨重启持久化，再起 T8b 接 `jobs.*` / 磁盘。
  验收：连接抖动后结果与 artifacts 仍可检索（见 `TestTerminalResultCachedAndServedAfterGatewayLoss`、`TestCachedTerminalNotServedForDifferentRunId`）。

- [x] **T9 服务端 DeadlineAt 兜底终态** — `markOpenClawRunDeadlineInterruptedLocked`
  run 过期（`sess.task.DeadlineAt`）且 gateway 无法确认时，bridge 主动回 terminal `interrupted`（`OPENCLAW_RUN_DEADLINE_EXCEEDED`），与 T3 客户端 deadline 形成双保险。
  **取舍**：仅在 gateway **无法确认**时按 deadline 强制终态；gateway 明确回 `running` 时**不**强杀，避免误伤合法长任务（那一侧由客户端 T3 兜底）。
  验收：gateway 失联超过 budget 后，`tasks.get` 返回确定 terminal（见 `TestGatewayUnconfirmedFallbackPastDeadlineInterrupts`）。

- [ ] **T10 错误语义细化**
  `gatewayRPCError`（`orchestrator.go:1678`）区分"连接断但 run 仍在后台可查" vs "run 确实失败"，前者携带 `runId` + `retryable/poll` 提示，供客户端走 T5 续轮询而非硬失败。
  验收：客户端能据错误语义区分"重连续跑"与"真失败"。

- [x] **T13 运行态同步校验（bridge 二进制 + 网关插件）**
  「源码已修但跑的不是它」是反复踩的坑，需双侧确认：
  - **Bridge**：`/api/ping.commit` 非空且等于目标 commit（本机 launchd 可能仍跑旧 `/usr/local/bin/xworkmate-go-core`）。
  - **网关插件**：网关启动日志含 `… openclaw-multi-session-plugins`，且 `/acp/rpc xworkmate.session.prepare` **不**返回 `unknown method`（插件已加载时返回真实 mapping；未加载时 bridge 才走 `compatibilityMode=local-session-prepare` 降级）。
  验收：App 不再显示 `unknown method: xworkmate.*`；网关 `N plugins` 列表含 multi-session。

### L3 可观测性（横切 · infra/service/lab）

- [ ] **T11 端到端贯穿 runId**
  App 日志 → Caddy access log → bridge SSE 日志（已有 `component=acp_sse`，`http_handler.go:221`）→ gateway run，全链路带同一 `runId`，便于定位"入口断"还是"WS 断"。
  验收：任一 `runId` 可在四层日志串联。

- [ ] **T12 关键指标 + 告警**
  bridge 暴露：`SOCKET_CLOSED 在途任务数`、gateway WS 重连计数、running 轮询超 deadline 计数。
  验收：⑥ 类事件发生即在监控可见，无需靠用户截图。

---

## 6. 落地顺序建议

0. ✅ **主根因修复**（live 验证）：让 OpenClaw 网关稳定加载 `openclaw-multi-session-plugins`——`openclaw plugins install` 从稳定路径重装 + 重启网关，确认启动日志 `6 plugins … openclaw-multi-session-plugins`、`xworkmate.*` 不再 `unknown method`。这是「采集AI资讯能产出」的前提（详见 §4）。
1. ✅ **当天止血**（已合并 main）：T1 + T2（入口配置）+ T3 + T4 + T6（客户端）+ session.prepare 数字 code 降级，消除"30min 必断 / 路由漏配 / 无限 running / 停不掉"。
   说明：session.prepare 数字 code 降级仍有价值——当插件**未**加载时，让 bridge 优雅 fallback 而非硬失败；插件加载后走真实 plugin 路径。
2. ✅ **健壮性加固**（本地验证 commit `2333c3e`）：T7 + T8 + T9（bridge 持久 run 仓与 WS 解耦），把网关短暂不可达 / 抖动收敛为「有界续轮询 → deadline 终态」，而非无限运行/丢结果。
3. **跟进（待办）**：T5 + T10（断连续跑语义）、T11 + T12（可观测性）、T8b（跨进程重启持久化，接 `xworkmate.jobs.*` / 磁盘）；运行态校验：每次替换 bridge 二进制 / 网关重启后，核对 `/api/ping.commit` 与网关 `N plugins` 列表。

> 回归对照：本目录 `00-review-env-and-matrix.md` 第 2 节"通用验收标准"中"长任务执行期间状态流 / 取消 / 重试稳定""同一任务重复执行 3 次不卡死"，即本规划的回归出口。
> 产物交付链（artifact scope / workspace 路径）的独立缺陷与修复，见 `openclaw-gateway-e2e-regression/ROOT_CAUSE_ANALYSIS.md`。
