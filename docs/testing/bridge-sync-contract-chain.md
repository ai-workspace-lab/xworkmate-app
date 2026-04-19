# Bridge Sync Contract Chain

## Scope

This note is a companion to the canonical state model in
[Account Sync, Settings, and Bridge State Model](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/account-sync-settings-bridge-state-model.md).

It focuses on the sync-contract path between:

- `accounts.svc.plus`
- `xworkmate-app`
- `xworkmate-bridge`

and the two client-side parsing assertions:

- `BRIDGE_SERVER_URL` may be retained in account sync metadata, but does not drive runtime endpoint selection
- `BRIDGE_AUTH_TOKEN` is written into secure storage
- account sync no longer parses `INTERNAL_SERVICE_TOKEN` as a bridge token fallback

## Sync Chain

```mermaid
flowchart LR
    A["accounts.svc.plus\nprotected login / MFA / sync / bootstrap response"] -->|returns| B["xworkmate-app\nparse BRIDGE_SERVER_URL metadata\nparse BRIDGE_AUTH_TOKEN"]
    B -->|write metadata only| C["AccountSyncState.syncedDefaults.bridgeServerUrl"]
    B -->|write secure only| D["Secure Storage\nbridge.auth_token"]
    B -->|resolve runtime endpoint via settings + sync state| E["AcpBridgeServerModeConfig.effective.endpoint\nhttps://xworkmate-bridge.svc.plus"]
    D -->|Authorization: Bearer <token>| F["xworkmate-app runtime requests"]
    F --> G["xworkmate-bridge"]
```

## Field Ownership

```mermaid
flowchart TD
    A["accounts.svc.plus"] --> A1["BRIDGE_SERVER_URL\nplain response field"]
    A --> A2["BRIDGE_AUTH_TOKEN\nprotected response field only"]

    B["xworkmate-app"] --> B1["sync state\nmay retain BRIDGE_SERVER_URL-derived bridgeServerUrl as metadata"]
    B --> B2["secure storage\nstores BRIDGE_AUTH_TOKEN as bridge.auth_token"]
    B --> B3["normal settings/profile\nmust not persist BRIDGE_AUTH_TOKEN"]
    B --> B4["runtime bridge origin\nfixed to managed bridge unless selfHosted is configured"]

    C["xworkmate-bridge"] --> C1["consume runtime request"]
    C1 --> C2["does not depend on BRIDGE_SERVER_URL"]
    C1 --> C3["uses BRIDGE_AUTH_TOKEN"]
```

## Parsing And Persistence Checks

```mermaid
sequenceDiagram
    participant Accounts as accounts.svc.plus
    participant App as xworkmate-app
    participant SyncState as Account Sync State
    participant SecureStore as Secure Storage
    participant Bridge as xworkmate-bridge

    Accounts->>App: protected response\nBRIDGE_SERVER_URL\nBRIDGE_AUTH_TOKEN
    App->>SyncState: save bridgeServerUrl as metadata when present
    App->>SecureStore: save bridge.auth_token from BRIDGE_AUTH_TOKEN
    App->>App: resolve runtime bridge origin from settings effective config
    App->>Bridge: connect with Authorization: Bearer <token>
```

## Test Coverage Targets

```mermaid
flowchart TD
    T["Account sync parsing tests"] --> T1["assert BRIDGE_SERVER_URL metadata can enter AccountSyncState.syncedDefaults.bridgeServerUrl"]
    T --> T2["assert runtime bridge endpoint stays pinned to managed bridge unless selfHosted is configured"]
    T --> T3["assert BRIDGE_AUTH_TOKEN -> secure storage target bridge.auth_token"]
    T --> T4["assert BRIDGE_AUTH_TOKEN never enters normal settings/profile persistence"]
    T --> T5["assert offline path can still read token from secure storage"]
```

## Expected Invariants

- Runtime bridge endpoint selection must not depend on `BRIDGE_SERVER_URL`.
- The app-facing managed bridge origin is fixed to `https://xworkmate-bridge.svc.plus` unless manual `selfHosted` is configured.
- `BRIDGE_SERVER_URL`, when present, is metadata only.
- `BRIDGE_AUTH_TOKEN` is the only bridge token field used by the sync contract.
- `INTERNAL_SERVICE_TOKEN` is not part of the app-side account sync token contract.
- `BRIDGE_AUTH_TOKEN` must never be written into normal settings snapshot, profile JSON, or UI-visible text.
- Client requests must assemble the header as `Authorization: Bearer <token>`.
