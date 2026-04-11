# Settings Config / State / Workflow Redesign

Status: Implementing V1

Date: 2026-04-11

Scope:
- `xworkmate-app`
- Settings / account sync / local UI state / task thread persistence

## V1 Decision

This worktree implements the first app-side simplification:

- keep a single persisted config file: `config/settings.yaml`
- move local recoverable UI state to `ui/state.json`
- keep task title/archive in `tasks/*.json`
- make account sync one-way overwrite for sync-owned fields
- keep bridge provider catalog / runtime capabilities runtime-only

## Overview Workflow

```mermaid
flowchart TD
  UI["Settings UI / App Startup"] --> INIT["SettingsController.initialize()"]

  subgraph LocalStores["APP Local Stores"]
    YAML["config/settings.yaml"]
    UISTATE["ui/state.json"]
    SYNCJSON["account/sync_state.json"]
    SECRET["secrets/*.secret\naccount session token / managed secrets"]
    TASKS["tasks/*.json\nthread title / archived / thread-owned state"]
  end

  INIT --> LOAD["SecureConfigStore.loadSettingsSnapshot()"]
  LOAD --> YAML

  INIT --> LOADUI["SecureConfigStore.loadAppUiState()"]
  LOADUI --> UISTATE

  INIT --> LOADTHREADS["loadTaskThreads()"]
  LOADTHREADS --> TASKS

  INIT --> RESTORE["restoreAccountSession()"]
  RESTORE --> TOKEN["loadAccountSessionToken()"]
  TOKEN --> SECRET

  TOKEN --> CHECK{"baseUrl + session token ready?"}
  CHECK -->|no| BLOCK["blocked\nAccount session is unavailable"]
  CHECK -->|yes| SYNC["syncAccountSettingsInternal(baseUrl)"]

  SYNC --> API["AccountRuntimeClient.loadProfile(token)"]
  API --> SAVE_SYNC["saveAccountSyncState(nextState)"]
  SAVE_SYNC --> SYNCJSON

  API --> MODECFG["saveSnapshot(\naccountLocalMode=false,\nacpBridgeServerModeConfig.cloudSynced=remote summary\n)"]
  MODECFG --> YAML

  API --> APPLY["applyAccountSyncedDefaultsSettingsInternal(state)"]

  APPLY --> O1["overwrite remote gateway endpoint"]
  APPLY --> O2["overwrite gateway tokenRef"]
  APPLY --> O3["overwrite vault address / namespace"]
  APPLY --> O4["overwrite aiGateway baseUrl / apiKeyRef"]
  APPLY --> O5["overwrite ollamaCloud apiKeyRef"]
  APPLY --> O6["update cloudSynced metadata"]

  O1 --> SAVE["saveSnapshot(next settings)"]
  O2 --> SAVE
  O3 --> SAVE
  O4 --> SAVE
  O5 --> SAVE
  O6 --> SAVE

  SAVE --> YAML
  SAVE --> DERIVED["reloadDerivedStateInternal()"]
  DERIVED --> VIEW["Settings / Runtime ViewModel"]

  VIEW --> NOTE1["does not auto-connect gateway"]
  APPLY -. not touched .-> NOTE2["providerSyncDefinitions\n(sync payload definitions)\nnot overwritten here"]

  UI --> LOCAL_EDIT["local settings edit"]
  LOCAL_EDIT --> SAVE_LOCAL["saveSnapshot()"]
  SAVE_LOCAL --> YAML

  UI --> UI_EDIT["local ui restore edit"]
  UI_EDIT --> SAVE_UI["saveAppUiState()"]
  SAVE_UI --> UISTATE

  UI --> THREAD_EDIT["rename / archive / restore thread"]
  THREAD_EDIT --> SAVE_THREAD["saveTaskThreads()"]
  SAVE_THREAD --> TASKS
```

## V1 Boundaries

- `settings.yaml` only stores current schema V1 config intent and sync-owned local snapshots.
- `ui/state.json` stores `assistantLastSessionKey`, `assistantNavigationDestinations`, and `savedGatewayTargets`.
- `tasks/*.json` stores thread-owned display facts such as `title` and `archived`.
- `account/sync_state.json` stores sync metadata only, not local override policy.
- bridge-advertised providers and ACP capability state stay runtime-only.
