# Chain Map: Task Execution (App → Bridge → OpenClaw → Plugin)

Repo chain: xworkmate-app → xworkmate-bridge → openclaw.svc.plus → openclaw-multi-session-plugins

## Entry Points (xworkmate-app)

```
1. AssistantPage.sendChatMessage()
   lib/features/assistant/assistant_page_state_actions.dart

2. AppController.resendChatMessage() (retry)
   lib/app/app_controller_desktop_thread_actions.dart

3. drainOpenClawGatewayQueue() (queue drain)
   lib/app/app_controller_openclaw_task_queue.dart
```

## Call Flow

```
xworkmate-app
  AssistantPage.sendChatMessage()
    └─ AppController.sendChatMessage()
       ├─ Resolve/create TaskThread by sessionKey/threadId
       ├─ Prepare local workspace: ~/.xworkmate/threads/<session>/
       ├─ Build task context prompt (TaskThread.sessionKey, workspace, contract)
       ├─ Attach metadata.xworkmateTaskArtifactContract
       │  └─ schemaVersion, appThreadKey, expectedArtifactDirs
       └─ Select execution path:
          ├─ Agent providers (codex/opencode/gemini/hermes)
          │   └─ DesktopGoTaskService.startSession()
          └─ OpenClaw gateway
              ├─ Check admission: isOpenClawLaneIdle()
              │   ├─ Idle → send immediately
              │   └─ Busy → queueOpenClawGatewayWork()
              └─ DesktopGoTaskService.startSession()

  DesktopGoTaskService
    └─ ExternalCodeAgentAcpDesktopTransport.executeTask()
       ├─ acp.capabilities → verify provider availability
       ├─ xworkmate.routing.resolve → pre-resolve route
       ├─ session.start (WebSocket /acp)
       │   ├─ params: sessionId, threadId, prompt, workingDirectory
       │   ├─ routing: executionTarget=gateway, preferredGatewayProviderId=openclaw
       │   └─ metadata: xworkmateTaskArtifactContract
       └─ Listen for SSE session.update events
          ├─ status=running → poll xworkmate.tasks.get
          ├─ terminal snapshot → applyGatewayChatResult()
          └─ artifacts → sync to local workspace

───────────────────────────────────────────────────────────
Protocol: ACP JSON-RPC 2.0 over WebSocket
Path:     wss://xworkmate-bridge.svc.plus/acp
Auth:     Bearer <BRIDGE_AUTH_TOKEN>
───────────────────────────────────────────────────────────

xworkmate-bridge
  internal/acp/http_handler.go: WebSocket handler
    └─ handleRequest() (rpc_handler.go)
       ├─ Validate routing params
       ├─ forceOpenClawGatewayRequest() — ensure gateway routing
       └─ orchestrator.Process()
          ├─ Routing engine: Resolve(params, prompt, memory)
          │   ├─ Heuristic: looksLocal() / looksOnline()
          │   ├─ Memory preferences
          │   └─ LLM classifier path
          │
          ├─ openClawGatewayAdmissionGate.acquire()
          │   ├─ maxActive: 5, maxQueued: 20
          │   ├─ queueTimeout: 10 min
          │   └─ Returns: admission slot or OPENCLAW_GATEWAY_BUSY
          │
          └─ startOpenClawGatewayTask()
             ├─ ensureProductionGatewayConnected()
             ├─ openClawArtifactPrepare()
             │   └─ gateway.request('xworkmate.session.prepare')
             │       ├─ schemaVersion: 1
             │       ├─ appThreadKey: App TaskThread key
             │       ├─ openclawSessionKey: OpenClaw SessionEntry key
             │       ├─ expectedArtifactDirs: typed artifact contract
             │       └─ scope: tasks/<openclawSessionKey>/<runId>/
             │
             ├─ gateway.request('chat.send')
             │   └─ payload: sessionKey, message, attachments, idempotencyKey
             │      sessionKey is the OpenClaw native field and equals openclawSessionKey
             │      (no expectedArtifactDirs root field)
             │
             ├─ Create OpenClawTaskRecord
             │   ├─ SessionID, ThreadID, TurnID, RunID
             │   ├─ SessionKey (from gateway response)
             │   ├─ TaskLoadClass (short_task/long_task/complex_chain_task)
             │   ├─ RuntimeBudgetMinutes (10/30/60)
             │   └─ PreparedArtifact scope ref
             │
             └─ startOpenClawTaskMonitor()
                └─ Every 1s: probeOpenClawTask()
                   └─ gateway.request('agent.wait', timeout=1s)
                      ├─ completed → completeOpenClawTask()
                      ├─ failed    → failOpenClawTask()
                      ├─ SLA expired → TASK_SLA_EXPIRED
                      └─ silent failure >10min → cleanup

───────────────────────────────────────────────────────────
Protocol: Custom JSON-RPC v4 over WebSocket
Auth:     Ed25519 device identity + shared token
───────────────────────────────────────────────────────────

openclaw.svc.plus
  Gateway: receives 'chat.send'
    └─ Agent runner processes turn
       ├─ Model inference (Claude/GPT/Gemini)
       ├─ Tool execution loop
       │   ├─ browser → screenshot → saveMediaBuffer(browser)
       │   ├─ image-generation → GeneratedImageAsset (in-memory)
       │   ├─ file-write → write to working directory or arbitrary path
       │   └─ video-render → output to media dir or /tmp
       │
       └─ Tool output destinations:
          ├─ ~/.openclaw/media/browser/<uuid>.png   ← NOT in tasks/<session>/<run>/
          ├─ ~/.openclaw/media/inbound/<uuid>.<ext> ← NOT in tasks/<session>/<run>/
          ├─ /tmp/openclaw/downloads/               ← NOT in tasks/<session>/<run>/
          └─ tasks/<session>/<run>/output.md        ← MAY be written here

openclaw-multi-session-plugins
  Receives gateway RPC: xworkmate.session.prepare
    recordXWorkmateSessionMapping()
      ├─ Validate schemaVersion=1 typed metadata
      ├─ Require appThreadKey and openclawSessionKey
      ├─ Write SessionEntry.pluginExtensions
      │   └─ ["openclaw-multi-session-plugins"]["xworkmate.sessionMapping"]
      └─ Fail closed on appThreadKey/openclawSessionKey conflicts

    prepareXWorkmateArtifacts()
      ├─ resolveWorkspaceDir() → workspace root
      ├─ safeScopeSegment(openclawSessionKey) → sanitize
      ├─ safeScopeSegment(runId) → sanitize
      └─ mkdir <workspace>/tasks/<safeSessionKey>/<safeRunId>/

  Receives gateway RPC: xworkmate.artifacts.export
    exportXWorkmateArtifacts()
      ├─ resolveScopeRoot(workspaceRoot, artifactScope)
      ├─ collectCandidates(scopeRoot)
      │   ├─ Walk tasks/<session>/<run>/ recursively  ← ONLY THIS DIRECTORY
      │   ├─ Skip symlinks
      │   ├─ Skip .git, .openclaw, node_modules, etc.
      │   └─ Apply artifact-ignore.md rules
      │
      ├─ Read each candidate file, compute SHA-256
      ├─ signArtifactRef(sessionKey, runId, relativePath)
      └─ Return manifest + base64 file contents

  `expectedArtifactDirs` source:
    session.start.metadata.xworkmateTaskArtifactContract.expectedArtifactDirs
      → bridge artifact contract
      → xworkmate.session.prepare mapping
      → xworkmate.artifacts.collect-and-snapshot / export only

  Forbidden compatibility paths:
    session.start.metadata.xworkmateTaskArtifactContract.sessionKey
    session.start.expectedArtifactDirs
    session.start.metadata.expectedArtifactDirs
    chat.send.expectedArtifactDirs
    xworkmate.tasks.get.sessionKey

  Receives gateway RPC: xworkmate.artifacts.collect-and-snapshot
    collectAndSnapshotXWorkmateArtifacts()
      ├─ Scan ~/.openclaw/media/ and /tmp/openclaw/ for files changed since task start
      ├─ Copy regular files into tasks/<session>/<run>/artifacts/
      ├─ Preserve source grouping such as artifacts/media/... and artifacts/tmp-openclaw/...
      └─ Reject symlinks and paths outside the fixed source roots

───────────────────────────────────────────────────────────
FIXED GAP: Bridge calls collect-and-snapshot after agent.wait
terminal completion and before xworkmate.artifacts.export.
Tool outputs in ~/.openclaw/media/* or /tmp/openclaw/* are
now copied into tasks/<session>/<run>/artifacts/ before export.
───────────────────────────────────────────────────────────

  Back to xworkmate-bridge:
    completeOpenClawTask()
      ├─ Call xworkmate.artifacts.collect-and-snapshot via gateway
      ├─ Call xworkmate.artifacts.export via gateway
      ├─ Collect artifact manifest
      ├─ Build terminal snapshot with:
      │   ├─ status: completed/failed/cancelled
      │   ├─ artifacts: { items: [...], scope: "..." }
      │   └─ text: final output
      │
      ├─ decorateOpenClawArtifactDownloadURLs()
      │   └─ Replace artifact refs with signed download URLs
      │       Format: /artifacts/openclaw/download?ref=<signed>&t=<expiry>
      │
      └─ Send SSE session.update to app

  Back to xworkmate-app:
    ExternalCodeAgentAcpDesktopTransport
      ├─ Receive terminal snapshot via SSE or xworkmate.tasks.get
      ├─ applyGatewayChatResult()
      │   ├─ Terminal snapshot → lifecycleStatus=ready
      │   ├─ success=true && artifacts present → syncArtifactsFromBridge()
      │   ├─ success=false → lastResultCode=failed
      │   └─ no-exported-artifacts → lastArtifactSyncStatus=no-exported-artifacts
      │
      └─ syncArtifactsFromBridge()
         └─ Download each artifact via /artifacts/openclaw/download
            → Save to ~/.xworkmate/threads/<session>/

Rule: the app must not keep an OpenClaw task in `running` after a bridge
terminal snapshot. Missing or incomplete artifacts are represented only through
`lastArtifactSyncStatus` (`no-exported-artifacts`, `partial`, `download-failed`,
etc.), not by extending the task execution lifecycle.
```

## Key Files by Repo

### xworkmate-app
- `lib/runtime/external_code_agent_acp_desktop_transport.dart` — 核心 ACP transport
- `lib/runtime/go_task_service_client.dart` — GoTaskService 数据模型
- `lib/runtime/gateway_acp_client.dart` — ACP HTTP RPC client
- `lib/app/app_controller_openclaw_task_queue.dart` — OpenClaw 并发队列
- `lib/app/app_controller_desktop_thread_sessions.dart` — session 恢复逻辑
- `lib/app/app_controller_desktop_thread_actions.dart` — 消息发送
- `lib/runtime/agent_registry.dart` — agent registry

### xworkmate-bridge
- `internal/acp/http_handler.go` — HTTP server + WebSocket handler
- `internal/acp/rpc_handler.go` — JSON-RPC dispatcher
- `internal/acp/orchestrator.go` — 会话编排 (2000+ lines)
- `internal/acp/openclaw_gateway_admission.go` — 并发控制
- `internal/acp/openclaw_async_tasks.go` — 异步任务管理
- `internal/acp/openclaw_artifact_download.go` — artifact 下载代理
- `internal/gatewayruntime/runtime.go` — gateway WebSocket client
- `internal/router/router.go` — 路由引擎

### openclaw-multi-session-plugins
- `src/exportArtifacts.ts` — artifact prepare/export/read (963 lines)
- `src/taskState.ts` — task snapshot adapter + SessionEntry.pluginExtensions mapping
- `index.ts` — plugin entry + gateway method registration

### openclaw.svc.plus (reference)
- `src/config/paths.ts` — ~/.openclaw/ state directory
- `src/infra/tmp-openclaw-dir.ts` — /tmp/openclaw/
- `dist/store-ezT1dexf.js` — saveMediaBuffer() → media/<subdir>/

## Fragile Points

1. **F1: Tool output path mismatch** — Tools save to media/, plugin exports from tasks/ → gap
2. **F2: Session key mismatch** — Bridge maps App `appThreadKey` to an explicit `openclawSessionKey` before prepare/chat/export and the plugin persists that mapping in SessionEntry.pluginExtensions
3. **F3: Prepare timing** — If prepare fails after send, no scope directory exists
4. **F4: Admission gate rejection** — Queue full → OPENCLAW_GATEWAY_BUSY → app must handle
5. **F5: Bridge restart** — In-memory sessions lost → app must detect and recover
6. **F6: Artifact ref key rotation** — Secret change invalidates all signed refs
7. **F7: SSE stream interruption** — Recovery polling must align with bridge task deadlines and must apply terminal snapshots immediately
