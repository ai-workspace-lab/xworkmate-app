# Cross-Repo Task State Workflow

This document records the task-state workflow across:

- `xworkmate-app`
- `xworkmate-bridge`
- `openclaw-multi-session-plugins`

The core ownership split is:

- `xworkmate-app` owns task UI state, `TaskThread` persistence, local thread workspaces, and the OpenClaw submit queue.
- `xworkmate-bridge` owns public session/routing contracts, provider compatibility, normalized results, and OpenClaw task-submit routing.
- `openclaw-multi-session-plugins` owns OpenClaw task-scoped artifact preparation, export, and artifact-scope isolation.

## Overall Flow

```mermaid
flowchart LR
  U["User input / follow-up"] --> APP["xworkmate-app<br/>TaskThread + UI state"]
  APP -->|session.start / session.message| BR["xworkmate-bridge<br/>/acp/rpc"]
  BR -->|xworkmate.routing.resolve| ROUTE{"Execution target"}
  ROUTE -->|single-agent| AG["codex / opencode / gemini / hermes"]
  ROUTE -->|gateway=openclaw| OC["OpenClaw Gateway Runtime"]
  OC --> PLUG["openclaw-multi-session-plugins<br/>task-scoped artifacts"]
  PLUG -->|artifactRef / files / downloadUrl| BR
  BR -->|normalized result / SSE update| APP
  APP -->|write files| LOCAL["$HOME/.xworkmate/threads/<session>"]
  APP -->|persist index| STORE["~/Library/Application Support/xworkmate/tasks/threads.json"]
```

## App TaskThread State Machine

`TaskThread.lifecycleState.status` is intentionally small. Most terminal outcomes return to `ready`; the specific terminal result is stored in `lastResultCode`.

```mermaid
stateDiagram-v2
  [*] --> Ready: create task / restore persisted task

  Ready --> Queued: OpenClaw gateway active slot is full
  Queued --> Running: drainOpenClawGatewayQueue
  Queued --> Ready: abortRun\nlastResultCode=aborted
  Queued --> Ready: queue full\nlastResultCode=OPENCLAW_GATEWAY_QUEUE_FULL

  Ready --> Running: sendChatMessage\nmarkGatewayChatRun
  Running --> Ready: GoTaskServiceResult.success=true\nlastResultCode=success
  Running --> Ready: result.status / result.code\nlastResultCode=<status|code>
  Running --> Ready: no displayable output\nlastResultCode=failed
  Running --> Ready: ACP interrupted / timeout\nlastResultCode=ACP_*
  Running --> Ready: abortRun\nlastResultCode=aborted

  Ready --> Archived: user archives task
  Archived --> Ready: user restores task

  note right of Ready
    lifecycleStatus terminal state is usually ready.
    Read lastResultCode for result detail:
    success / failed / error / aborted /
    artifact_missing / ACP_HTTP_*
  end note
```

## Task Workspace Context Injection

Every app-owned task has a local workspace under `$HOME/.xworkmate/threads/<session>`. For remote execution, the bridge/runtime may also resolve a remote task workspace hint. The app passes the task workspace in two ways:

- Structured request fields: `workingDirectory` and, when available, `remoteWorkingDirectoryHint`.
- External conversation context: a `TaskThread workspace context` prefix is added to the prompt sent to Bridge/OpenClaw.

The local chat transcript still stores the user's original text. Only the external task prompt is enriched, so the UI does not show internal workspace rules as user content.

```mermaid
sequenceDiagram
  participant UI as "XWorkmate UI"
  participant APP as "TaskThread runtime"
  participant BR as "Bridge session"
  participant OC as "OpenClaw / provider"
  participant WS as "Task workspace"

  UI->>APP: "user message"
  APP->>WS: "ensure $HOME/.xworkmate/threads/<session>"
  APP->>APP: "build TaskThread workspace context"
  APP->>BR: "taskPrompt + workingDirectory + remoteWorkingDirectoryHint"
  BR->>OC: "session.start / session.message"
  OC->>WS: "final files must be exported into task scope"
  BR-->>APP: "result + artifact refs"
  APP->>WS: "sync inline/downloaded artifacts"
```

Prompt-level workspace rules are deliberately strict. `remoteWorkingDirectoryHint` is the writable task workspace for remote OpenClaw/provider execution when present; otherwise `workingDirectory` is used.

- Treat the current task workspace as the only writable workspace for the task execution.
- Create, modify, and export task files inside that workspace or its task artifact scope.
- Do not use global OpenClaw media/cache paths, `/tmp`, Downloads, Desktop, or other arbitrary directories as final deliverable locations.
- If a tool creates output outside the task workspace, copy/export the final deliverables into the task workspace before claiming completion.
- Prefer local task-workspace paths, or paths relative to that workspace, when reporting files back to the user.

## OpenClaw Gateway Queue

The app serializes OpenClaw gateway execution locally because OpenClaw task execution is treated as a constrained gateway lane.

```mermaid
flowchart TD
  A["APP selects Gateway + OpenClaw"] --> B{"active < 1 ?"}
  B -->|yes| C["Run immediately<br/>lifecycleStatus=running"]
  B -->|no| D{"queue < 20 ?"}
  D -->|yes| E["Enqueue<br/>lifecycleStatus=queued<br/>lastArtifactSyncStatus=queued"]
  D -->|no| F["Queue full<br/>lastResultCode=OPENCLAW_GATEWAY_QUEUE_FULL"]

  E --> G["drain queue"]
  G --> C
  C --> H["Bridge /acp/rpc<br/>routing=gateway/openclaw"]
  H --> I["OpenClaw execution"]
  I --> J{"Result"}
  J -->|success + output/files| K["APP ready<br/>lastResultCode=success<br/>sync artifacts"]
  J -->|artifact guard| L["APP ready<br/>lastResultCode=artifact_missing"]
  J -->|failure/interruption| M["APP ready<br/>lastResultCode=failed/error/ACP_*"]
```

## Bridge Session And Routing Workflow

The bridge exposes one public session contract while keeping provider-specific behavior behind bridge-owned routing. OpenClaw task submit uses `/acp/rpc` with explicit gateway routing metadata, not a separate app-facing path.

```mermaid
flowchart TD
  REQ["APP request"] --> EP{"HTTP / WS entry"}
  EP -->|/acp or /acp/rpc| RPC["General JSON-RPC"]

  RPC --> METHOD{"method"}
  METHOD -->|acp.capabilities| CAP["Return agent providers + gatewayProviders=openclaw"]
  METHOD -->|xworkmate.routing.resolve| ROUTE["Resolve single-agent / gateway"]
  METHOD -->|session.start| START["Create / start session turn"]
  METHOD -->|session.message| MSG["Continue existing session"]
  METHOD -->|session.cancel / session.close| CTRL["Cancel / close session"]

  START --> ORCH["session_orchestrator"]
  MSG --> ORCH
  ORCH --> PROVIDER{"provider compat"}
  PROVIDER -->|single-agent| SA["codex / opencode / gemini / hermes"]
  PROVIDER -->|gateway| OCG["OpenClaw runtime"]

  SA --> NORM["normalized result"]
  OCG --> NORM
  NORM --> OUT["success / status / turnId / output / artifacts / resolved*"]
```

## OpenClaw Plugin Artifact Scope

OpenClaw artifacts are scoped by task session and run. This prevents one task or turn from borrowing files from another.

```mermaid
flowchart TD
  CTX["OpenClaw plugin context<br/>sessionKey + runId + workspaceDir"] --> PREP["prepareXWorkmateArtifacts"]
  PREP --> SCOPE["artifactScope = tasks/<sessionKey>/<runId>"]
  SCOPE --> DIR["artifactDirectory"]
  DIR --> RUN["OpenClaw writes files"]
  RUN --> EXPORT["exportXWorkmateArtifacts"]
  EXPORT --> VALIDATE{"scope matches sessionKey/runId ?"}
  VALIDATE -->|no| ERR["Reject cross-task / cross-run artifact"]
  VALIDATE -->|yes| MANIFEST["manifest + artifactRef + files"]
  MANIFEST --> BR["Bridge result"]
  BR --> APP["APP downloads or inlines into local thread workspace"]

  note right of SCOPE
    Concurrent task isolation is based on:
    tasks/<session>/<run>
    Do not reuse other sessions or previous run files.
  end note
```

## Status Field Mapping

```mermaid
flowchart LR
  APP1["APP TaskThread.lifecycleState.status"] --> A1["queued / running / ready / archived"]
  APP2["APP TaskThread.lifecycleState.lastResultCode"] --> A2["queued / running / success / failed / error / aborted / artifact_missing / ACP_HTTP_*"]
  APP3["APP lastArtifactSyncStatus"] --> A3["queued / running / synced / no-artifacts / failed"]
  BR1["Bridge result.status"] --> B1["available / success / failed / provider status"]
  BR2["Bridge result.success"] --> B2["true / false"]
  PL1["Plugin artifact export"] --> P1["scopeKind=task<br/>artifactScope=tasks/session/run"]
```

## Boundary Rules

- The app does not store OpenClaw URLs. It only consumes bridge capabilities where `gatewayProviders` includes `openclaw`.
- OpenClaw `session.start` and `session.message` use `/acp/rpc` with explicit OpenClaw gateway routing metadata; `/gateway/openclaw` is not an app-facing endpoint.
- Follow-up conversation uses the same `sessionKey` / `threadId`. Bridge `session.message` must continue the provider session state or return a structured continuation error.
- Artifact ownership is enforced by `openclaw-multi-session-plugins` with `tasks/<session>/<run>` scope. The app syncs only the current run's artifacts into the local thread workspace.
- Upgrade/install flows must preserve real local history. Cleanup must only remove explicitly known test-pollution session keys.
