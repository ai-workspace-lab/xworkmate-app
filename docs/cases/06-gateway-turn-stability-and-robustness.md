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

## 1. The full chain (one gateway turn) — 四层，含 `openclaw-multi-session-plugins`

一次 gateway turn 跨**四层**：App → bridge(Go) → **openclaw-multi-session-plugins(TS 插件)** → OpenClaw gateway runtime。
插件是关键中间层：它给「多会话/多线程」补上**逻辑隔离的 artifact scope** 与**会话映射 + 任务快照**，并以 `xworkmate.*` 网关方法暴露给 bridge。

```
App.executeTask ──SSE POST /acp/rpc──▶ Bridge.handleRequest
   │                                      │
   │  ① xworkmate.session.prepare ───────▶ Gateway ──▶ [plugin] recordXWorkmateSessionMapping
   │       (建 appThreadKey⇄openclawSessionKey 映射 + prepareXWorkmateArtifacts)
   │       ◀── { artifactScope: tasks/<sani(sessionKey)>/<runId>, artifactDirectory, expectedArtifactDirs }
   │  ② chat.send (gateway 原生) ────────▶ Gateway ──▶ 派发 agent run，返回 runId（~25ms，detached）
   │       ◀── { runId, status: started }
   ▼
 Bridge 记 sess.openClaw + DeadlineAt(budget by taskLoadClass)，返回 running 句柄
   │
   ▼  App 持久化 association，pollOpenClawTaskAssociationInternal 轮询：
 ③ xworkmate.tasks.get(runId/openclawSessionKey/artifactScope) ─▶ Gateway ─▶ [plugin] getXWorkmateTaskSnapshot
      ├─ resolveNativeTask(host task registry by runId)  ──有──▶ 回 status(running/completed/failed) + 经 export 取 artifacts
      └─ 无 native task ──▶ exportArtifactsForTaskLookup 兜底：扫 scope 目录 + expectedArtifactDirs（workspace 根 reports//artifacts/）
                            ├─ 有产物 ─▶ status=unknown, evidence=artifacts_present, 带 artifacts
                            └─ 无产物 ─▶ code=no_native_task_record / task_not_found
 ④ 终态后取产物：xworkmate.artifacts.export / .list / .read（插件 exportXWorkmateArtifacts）
      scopeRoot = workspaceRoot/tasks/<sani(sessionKey)>/<runId>；按 requiredArtifactExtensions(.md) 判 constraintSatisfied
```

**多会话/多线程隔离的核心（插件提供）**：
- `artifactScopeFor(sessionKey, runId)` = `tasks/<sanitize(sessionKey)>/<runId>`（冒号→下划线，如 `agent:main:draft:e2e` → `agent_main_draft_e2e`），每个 (会话,运行) 独立目录，互不串扰（`exportArtifacts.ts:126/164`）。
- `recordXWorkmateSessionMapping` 把 `appThreadKey ⇄ openclawSessionKey` 持久成会话扩展（`taskState.ts`），让跨连接/重连仍能按 appThreadKey 找回 run。
- `exportXWorkmateArtifacts` 严校 `requestedArtifactScope === artifactScopeFor(sessionKey,runId)`，不匹配抛 `artifactScope does not match sessionKey/runId`——**调用方必须传一致的 sessionKey/runId/artifactScope 三元组**（bridge 的 `taskGetParamsWithSessionScope` 负责从 session 记录补齐；外部手工探针易踩此坑）。
- **workspace 根兜底扫描**：agent 常把产物写到 workspace 根的 `reports/`、`artifacts/` 而非 task scope；插件用 `expectedArtifactDirs` 回扫这些目录纳入产物（见 `openclaw-gateway-e2e-regression/ROOT_CAUSE_ANALYSIS.md` Fix 0）。

**live 实测（2026-06-26，8787，插件已加载）**：① session.prepare 回真实 mapping ✓；② chat.send `runId=turn-…438450000` ✓（bridge 日志 `request_timing method=chat.send`）；③ tasks.get 经插件返回 `code=no_native_task_record`（mapping 在、但 gateway 无该 run 的 native task record）+ scope 目录空、无 `news.md`。即**链路打通到插件层**，但本轮 agent 未注册可查 task、也未落产物（属第 4 层 agent 执行/落盘问题，见 §4「残留」与 §7）。

关键代码锚点：

| 环节 | 位置 |
|---|---|
| App 发起 SSE turn / 轮询 | `xworkmate-app/.../app_controller_desktop_thread_actions.dart:644`、`:747` |
| Bridge session.prepare / tasks.get / cancel | `xworkmate-bridge/internal/acp/rpc_handler.go:96`、`:126`、`taskGetParamsWithSessionScope:177` |
| Bridge↔Gateway WebSocket（dial 18789） | `xworkmate-bridge/internal/gatewayruntime/runtime.go:372` |
| 插件注册 `xworkmate.*` 网关方法 | `openclaw-multi-session-plugins/index.ts:126/162/176/206/221`（session.prepare/tasks.get/artifacts.export/.list/.read）|
| 插件 artifact scope / 会话映射 / 任务快照 | `src/exportArtifacts.ts`、`src/taskState.ts:208 getXWorkmateTaskSnapshot` |

---

## 2. 端到端拓扑（实测自代码 + live 8787 验证）

```
┌─ ai-workspace-lab/xworkmate-app  (Flutter)            executeTask → SSE POST Accept: text/event-stream
▼
┌─ ai-workspace-infra  Caddy 入口  xworkmate-bridge.svc.plus   （本机直连 127.0.0.1:8787 不经 Caddy）
│     /acp* : flush_interval -1 ✓  read/write_timeout 70m(对齐 bridge 60min) keepalive 5m   ← T1/T2 已修
▼
┌─ ai-workspace-lab/xworkmate-bridge  (Go)   live commit 2333c3e
│     /acp/rpc handleRequest → session.prepare / chat.send / xworkmate.tasks.get / tasks.cancel
│     gatewayruntime: WebSocket → 127.0.0.1:18789；per-session 持久 run 仓(T7/T8/T9)
▼ (WS, gateway 原生 chat.send + 插件注册的 xworkmate.*)
┌─ ai-workspace-lab/openclaw-multi-session-plugins  (TS 插件, enabled)   ← 多会话/多线程 artifact 隔离层
│     index.ts registerGatewayMethod: xworkmate.session.prepare / .tasks.get / .artifacts.export/.list/.read/.collect-and-snapshot
│     会话映射(taskState) + artifactScope=tasks/<sani(sessionKey)>/<runId>(exportArtifacts) + workspace 根兜底扫描
▼ (插件运行在网关进程内)
┌─ OpenClaw gateway runtime   npm-global openclaw 2026.6.1  @ /opt/homebrew/lib/node_modules/openclaw
│     launchd ai.openclaw.gateway, WS 18789；host task registry(detached task) + agent 执行(deepseek-v4-flash)
▼
   workspace ~/.openclaw/workspace/tasks/<sani(sessionKey)>/<runId>/  → 产物(.md 等)
```

**live 验证状态（2026-06-26 23:xx）**：
- ✅ 网关加载 `6 plugins … openclaw-multi-session-plugins`（重启后；详见 §4）。
- ✅ `/api/ping` commit=2333c3e；session.prepare 回真实 mapping；chat.send 成功返回 runId。
- ⚠️ `xworkmate.tasks.get` → `no_native_task_record`、scope 目录空：链路通到插件，但本轮 agent 未注册可查 task / 未落产物（第 4 层执行问题）。

旁路（`ai-workspace-service`）：`accounts.svc.plus`（登录/Token）、`console.svc.plus`（openclaw assistant route）、`litellm`/`AI-Relay-Kit`/`codex-relay`（模型出口）、`qmd`（记忆）——不在主链，但 Token/出口异常以「连接中断」形态出现，用 `runId` 区分。

出处：Caddy `…/xworkmate_bridge/templates/xworkmate-bridge-site.caddy.j2`；网关部署 `deploy_gateway_openclaw.yml`；插件 `~/.openclaw/extensions/openclaw-multi-session-plugins`（注册源当前指向临时 `/private/tmp/…`，见 §4 加固项）。

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

- [x] **T5 传输中断降级为"后台续跑·重连中"** — `pollOpenClawTaskAssociationInternal` catch（`thread_actions.dart`）
  轮询期间 App↔bridge 传输瞬断（`ACP_HTTP_CONNECTION_CLOSED`）时，不硬失败丢结果，而是**有界重试续轮询**：连续瞬断 `< kOpenClawPollTransientRetryLimit(=5)` 则保持 running、2s 后重试下一次 `getTask`；每次成功重置计数；超限才落终态。bridge 侧 T7/T9 负责网关侧抖动，这里只兜 App↔bridge 这一跳。
  **取舍**：未引入新的「重连中」UI 相位（避免改进度条布局）；任务保持「运行中」即降级态。未走 `resumeOpenClawTaskAssociationsInternal` 全量恢复（那是 thread 重载路径），而是就地有界重试，风险更低、不会无限重连。
  验收：轮询瞬断 ≤5 次能自动续轮询；持续不可达则在有界次数后落终态。

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

- [x] **T10 错误语义细化** — `gatewayRPCError`（`orchestrator.go`）
  对 `OPENCLAW_GATEWAY_SOCKET_CLOSED` 在 Data 中带 `retryable=true`、`poll=true`，表达「连接断但 run 可能仍在后台、可续轮询」语义，供客户端 T5 据此续轮询而非硬失败。
  验收：socket-closed 错误带 retryable/poll 标记。

- [x] **T13 运行态同步校验（bridge 二进制 + 网关插件）**
  「源码已修但跑的不是它」是反复踩的坑，需双侧确认：
  - **Bridge**：`/api/ping.commit` 非空且等于目标 commit（本机 launchd 可能仍跑旧 `/usr/local/bin/xworkmate-go-core`）。
  - **网关插件**：网关启动日志含 `… openclaw-multi-session-plugins`，且 `/acp/rpc xworkmate.session.prepare` **不**返回 `unknown method`（插件已加载时返回真实 mapping；未加载时 bridge 才走 `compatibilityMode=local-session-prepare` 降级）。
  验收：App 不再显示 `unknown method: xworkmate.*`；网关 `N plugins` 列表含 multi-session。

### L3 可观测性（横切 · infra/service/lab）

- [x] **T11 端到端贯穿 runId** — `openclaw_run_registry.go`
  在 `tasks_get_unconfirmed_fallback`、`run_deadline_interrupt` 两处加 `runId`/`openclawSessionKey` 标记的 warn 日志，可与 App→bridge→插件→gateway 按 `runId` 串联（既有 `component=acp_sse` 已带 requestId）。
  验收：socket 抖动 / deadline 终态在 bridge 日志可按 runId 定位。

- [x] **T12 关键指标** — `internal/acp/metrics.go`，经 `/api/ping.metrics` 暴露
  进程内计数：`gatewaySocketClosed`、`taskGetUnconfirmedFallback`、`runDeadlineInterrupt`。live 验证 `/api/ping` 已返回 `metrics` 字段（commit `0a50621`）。
  验收：三类不稳定事件可监控，无需靠用户截图。（告警接入留运维侧）

---

## 6. 落地顺序建议

0. ✅ **主根因修复**（live 验证）：让 OpenClaw 网关稳定加载 `openclaw-multi-session-plugins`——`openclaw plugins install` 从稳定路径重装 + 重启网关，确认启动日志 `6 plugins … openclaw-multi-session-plugins`、`xworkmate.*` 不再 `unknown method`。这是「采集AI资讯能产出」的前提（详见 §4）。
1. ✅ **当天止血**（已合并 main）：T1 + T2（入口配置）+ T3 + T4 + T6（客户端）+ session.prepare 数字 code 降级，消除"30min 必断 / 路由漏配 / 无限 running / 停不掉"。
   说明：session.prepare 数字 code 降级仍有价值——当插件**未**加载时，让 bridge 优雅 fallback 而非硬失败；插件加载后走真实 plugin 路径。
2. ✅ **健壮性加固**（commit `2333c3e`）：T7 + T8 + T9（bridge 持久 run 仓与 WS 解耦），把网关短暂不可达 / 抖动收敛为「有界续轮询 → deadline 终态」，而非无限运行/丢结果。
3. ✅ **断连语义 + 可观测**（commit `0a50621`）：T10（socket-closed 带 retryable/poll）+ T5（App 轮询瞬断有界续轮询）+ T11（runId 日志）+ T12（`/api/ping.metrics` 计数）。
4. **剩余**：
   - **S1（已回退，待重做）**：缺省 `expectedArtifactDirs` 会让「期望产物但实际无产物」的 run 卡在「等待导出」（破坏 E2E 测试）。根因是 `openClawTaskGetRequiresArtifactExport` 把「有 expectedArtifactDirs」等同「必须导出/阻塞」。**正确做法**：解耦「扫描提示」与「阻塞式导出要求」——让缺省目录只驱动插件的兜底扫描、不触发 bridge 的等待导出。需单独一轮、对全 E2E 套件验证。
   - **T8b（跨进程重启持久化）**：把 per-session run 仓落磁盘 / 接 `xworkmate.jobs.*`，让 bridge **进程重启**后仍能回放终态。当前内存仓已覆盖「WS 抖动 / 网关瞬断」（同进程内），跨重启是较小边际收益、较大复杂度（序列化 / 启动加载 / 过期清理 / 并发），建议作为独立一轮带测试做。

> 回归对照：本目录 `00-review-env-and-matrix.md` 第 2 节"通用验收标准"中"长任务执行期间状态流 / 取消 / 重试稳定""同一任务重复执行 3 次不卡死"，即本规划的回归出口。
> 产物交付链（artifact scope / workspace 路径）的独立缺陷与修复，见 `openclaw-gateway-e2e-regression/ROOT_CAUSE_ANALYSIS.md`。

---

## 7. 全链路稳定性改进（基于 2026-06-26 四层 live 验证）

> 优先级按「直接决定一次任务能否产出」排序。S1/S2 是本轮 live 新发现。

- **S0 插件稳定安装（最高）— ✅ 已落实并验证（2026-06-27）**
  网关方法 `xworkmate.*` 全部依赖 `openclaw-multi-session-plugins`。**精确根因**：`~/.openclaw/extensions/openclaw-multi-session-plugins` 是个**符号链接 → `/tmp/openclaw-multi-session-plugins`**（临时盘，重启/清 tmp 即失效）；`openclaw plugins inspect` 标 `Source: /private/tmp/…` 且警告「loaded without install/load-path provenance（untracked local code）」。网关 09:21 启动早于该 tmp 路径就位 → 当次只加载 5 plugins、`xworkmate.*` 全 `unknown method`。
  **已执行**：① 删符号链接、把内容复制成真实目录 `~/.openclaw/extensions/openclaw-multi-session-plugins`；② `openclaw plugins install <该路径> --force` 落正式 `path` install 记录；③ `launchctl kickstart -k gui/$UID/ai.openclaw.gateway` 重启。
  **验证**：启动日志 `http server listening (6 plugins: … openclaw-multi-session-plugins)`；`inspect` 的 `Source` 变为 `~/.openclaw/extensions/…/dist/index.js`、provenance 警告消失；`xworkmate.session.prepare` 经 bridge 返回**真实插件响应**（`fallback=null`、带 `mapping`、`artifactScope=tasks/draft_s0verify/s0-run`），不再走 bridge 的 `local-session-prepare` 降级。
  收尾：`~/.openclaw/extensions/` 现为真实目录（非 /tmp 软链），重启/重启后不再丢插件；建议把它纳入部署（`deploy_gateway_openclaw`）从仓库 `openclaw-multi-session-plugins` 安装，避免再被软链到临时盘。

- **S1 `expectedArtifactDirs` 为空导致根目录兜底失效 — ⚠️ 一版本已合并后回退（commit `0280893` → 回退于 `81f65e3`）**
  根因：live 的 session mapping 为 `expectedArtifactDirs:[]`，而插件对「agent 把产物写到 workspace 根 `reports/`/`artifacts/` 而非 task scope」的兜底扫描**依赖 `expectedArtifactDirs`**；为空 → 兜底形同虚设 → 即便 agent 产出也收不到，表现「暂无文件」。
  **回退原因**：当时的实现给所有「推断出 requiredExts」的任务补缺省目录并置 `requiresExport=true`，导致 gateway run 成功但**实际无产物**时卡在「等待 artifact 导出」（`TestHTTPHandlerGatewayOpenClawHandlesFiveConcurrentE2ECases` 等转红）。阻塞来自 `openClawTaskGetRequiresArtifactExport` 把「有 expectedArtifactDirs」等同「必须导出」。
  **正确做法（待重做）**：解耦「扫描提示」与「阻塞式导出」——缺省目录只驱动插件兜底扫描、不触发 bridge 等待导出；或仅在客户端**显式**声明 `requiredArtifactExtensions` 时启用。需单独一轮、对全 E2E 套件验证后再上。

- **S2 `no_native_task_record` 状态歧义** — `xworkmate.tasks.get` 的真值来自「gateway host task registry 有该 run 的 detached task」**或**「artifact 已存在」。live 中 chat.send 成功但 gateway 无 native task record（agent 可能以 inline chat 执行、未注册可查 task），且无产物 → 插件回 `no_native_task_record`，bridge 只能靠 T7 兜底续轮询到 deadline，**无法区分「还在跑」与「跑完没产物」**。
  改进：①确认 gateway 侧 chat.send 是否应产出 detached task（agent 配置/ `tasks.*` 注册）；②插件/bridge 在 `no_native_task_record` 且超过最小执行时长时，下发更明确的 `running(no-record)` vs `completed(no-artifact)` 语义，配合 §5 T9 deadline 收口。
  验收：agent 正常执行时 `tasks.get` 能返回真实 running→completed；异常时给确定终态而非无限 degraded。

- **S3 三元组一致性（已知约束）** — 插件严校 `sessionKey/runId/artifactScope` 三者一致（`exportArtifacts.ts:126`），且 bridge 的 openclawSessionKey 由 `agent:main:` + appThreadKey 组成。**调用方/探针不要预带 `agent:main:` 前缀**（否则双前缀 → `artifactScope does not match`）。bridge `taskGetParamsWithSessionScope` 已负责补齐；保持其为唯一可信来源，App/探针只传 `sessionId=draft:<id>` + `runId`。

- **S4 运行态可观测** — 沿用 §5 T11/T12：bridge `/api/ping.commit`、网关 `N plugins` 列表、`openclaw plugins inspect` 三处纳入健康检查；`runId` 贯穿 App→bridge→插件→gateway 日志，便于定位断点落在四层中的哪一层。

---

## 8. 2026-06-27 Cases 00–05 全面验收执行日志（进行中）

> 执行计划：`docs/plans/2026-06-27-cases-00-05-gateway-turn-acceptance.md`。本节只记录脱敏后的运行证据；API Key、Bridge Token、账号密码不写入仓库。
> 追溯参考：`.xcodeinsight/context/repo-summary.md`、`.xcodeinsight/index/risk-index.md`、`.xcodeinsight/index/callchain-index.md`，用于对齐 `xworkmate-app` / `xworkmate-bridge` / `openclaw-multi-session-plugins` / `playbooks` 的调用链与风险边界。

### 8.1 当前目标与状态

| 阶段 | 状态 | 当前证据 / 下一步 |
|---|---|---|
| 仓库与运行态基线 | ✅ 已完成 | App 基线 `ca9cba6` 已纳入回归；本轮修复最终提交为 `66fd0e4` |
| 本地 all-in-one 部署 | ✅ 已完成 | 稳定插件目录幂等迁移修复已提交 `xworkspace-console` main（`50c2d85` + `5093e21`），本地修复版已验证通过 |
| Gateway Turn 定向回归 | 🟢 已通过 | T5 两条新增定向测试通过；完整 `assistant_execution_target_test.dart` 74 条通过 |
| Cases 00–05 真实任务 | ✅ 已完成 | 任务跑完后已整理为本节日志；后续若有新增回归再追加 |
| 提交 / push / CI | ✅ 已完成 | `xworkmate-app` 已提交并推送 `main -> 66fd0e4`；相关支撑仓也已推送完成 |

### 8.2 08:47 CST 基线快照

- Bridge：`127.0.0.1:8787` 正在监听，launchd `plus.svc.xworkspace.bridge` 为 running；匿名 `/api/ping` 返回 `401`，符合鉴权启用预期，后续用本机 token 脱敏核验 commit/metrics。
- Gateway：`127.0.0.1:18789` 正在监听，launchd `ai.openclaw.gateway` 为 running。
- 插件：`openclaw-multi-session-plugins` 为 `loaded`，Source/Install path 均为稳定目录 `~/.openclaw/extensions/openclaw-multi-session-plugins`，Recorded version `2026.6.1`；S0 的临时目录问题当前未复发。
- 仓库：`xworkmate-app`、`xworkmate-bridge`、`xworkspace-console` 均在 `main`；`openclaw-multi-session-plugins` 本地 `main` 比远端 ahead 1，验收过程不得误带该仓库已有提交。
- 安全边界：用户提供的三类模型 API Key 仅作为安装子进程环境变量传入，不落文档、不纳入 Git；首轮暴露出远端脚本会打印 provider key 的缺陷，已在 §8.3 记录并修复本地源码。

### 8.3 08:54 CST 首轮发现与修复

- **T5 测试缺口已补**：旧测试仍断言 OpenClaw `tasks.get` 第一次 `ACP_HTTP_CONNECTION_CLOSED` 就立即失败，与「有界续轮询」新契约冲突。现拆为：①一次瞬断后第二次快照成功，pending 清理且 lifecycle=`ready/success`；②连续 `kOpenClawPollTransientRetryLimit + 1`（当前 6）次瞬断后，确定性落 `ACP_HTTP_CONNECTION_CLOSED`、清 pending/association。两条定向测试均 `All tests passed!`。
- **测试速度可控**：`pollOpenClawTaskAssociationInternal` 新增默认仍为 2 秒的 `pollInterval` 可选参数，仅测试注入 `Duration.zero`，生产重试节奏不变。
- **安装日志泄密缺口**：托管 bootstrap 把 provider API Key 走普通 `append_var`，因此会打印明文；统一 auth token 则已脱敏。这不是模型调用失败原因，但违反安装安全边界。已在 `xworkspace-console` 本地改为六类 provider key 全走 `append_secret_var`，并新增 bootstrap 回归；`bash tests/setup-ai-workspace-all-in-one-test.sh` 全部通过。当前正在运行的脚本来自修复前远端，最终文档不记录任何 key 值。

### 8.4 08:59 CST 部署幂等修复与 App 完整定向回归

- 首轮 all-in-one 在 `Link openclaw-multi-session-plugins to extensions (macOS)` 失败：S0 已把目标改成稳定真实目录，而旧 patch 仍强制 `state: link` 指向 `/tmp`/源码目录；Ansible 正确拒绝 directory→symlink。自动重跑无法修复结构性错误，因此中止第二轮。
- `xworkspace-console` 修复：macOS patch 现在会识别并移除旧临时 symlink、确保 `~/.openclaw/extensions/openclaw-multi-session-plugins` 为真实目录、只复制构建产物/manifest，并执行 `openclaw plugins install <stable-path> --force` 记录 provenance；不再把 S0 修复倒退成临时链接。
- bootstrap 本地执行优先采用同 checkout 的 `patch-macos-playbooks.py`，远端 fallback 增加 cache-busting，避免 main 刚提交后又下载到 5 分钟 CDN 旧版本。
- 上述 installer 修复已分两次提交并 push 到 `xworkspace-console/main`：`50c2d85`、`5093e21`；bootstrap tests、`bash -n`、Python compile 均通过。
- App 完整定向回归：`flutter test test/runtime/assistant_execution_target_test.dart` → **74 tests / All tests passed**。覆盖 T3 running deadline、T4 本地停止、T5 断线恢复/耗尽、T6 pending 清理以及五类代表性 E2E admission/isolation 测试。

### 8.5 09:xx CST 收尾结果

- `xworkmate-app` 已完成最终提交并推送：`66fd0e4 fix(gateway): harden OpenClaw polling and acceptance notes`。
- `xworkspace-console` 与 `playbooks` 的相关修复提交也已分别推送到 `main`；`playbooks` 仍保留用户原有的 `roles/cloudflare_dns/tasks/main.yml` 本地改动，未触碰。
- `.xcodeinsight` 里的 repo-summary / risk / callchain 已用于对齐调用链、风险边界和收尾验证，后续同类问题可继续沿此索引追溯。
