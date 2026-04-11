# Bridge Sync Contract Chain

## Scope

This note documents the account-driven bridge sync chain after the naming unification to:

- `BRIDGE_SERVER_URL`
- `BRIDGE_AUTH_TOKEN`

It focuses on the runtime data path:

- `accounts.svc.plus`
- `xworkmate-app`
- `xworkmate-bridge`

and the two key client-side parsing assertions:

- `BRIDGE_SERVER_URL` is written into account sync state
- `BRIDGE_AUTH_TOKEN` is written into secure storage

## Sync Chain

```mermaid
flowchart LR
    A["accounts.svc.plus\nprotected login / MFA / sync / bootstrap response"] -->|returns| B["xworkmate-app\nparse BRIDGE_SERVER_URL\nparse BRIDGE_AUTH_TOKEN"]
    B -->|write| C["AccountSyncState.syncedDefaults.bridgeServerUrl"]
    B -->|write secure only| D["Secure Storage\nbridge.auth_token"]
    C -->|drive runtime metadata| E["cloudSynced.remoteServerSummary.endpoint"]
    D -->|Authorization: Bearer <token>| F["xworkmate-app runtime requests"]
    F --> G["xworkmate-bridge"]
```

## Field Ownership

```mermaid
flowchart TD
    A["accounts.svc.plus"] --> A1["BRIDGE_SERVER_URL\nplain response field"]
    A --> A2["BRIDGE_AUTH_TOKEN\nprotected response field only"]

    B["xworkmate-app"] --> B1["sync state\nstores BRIDGE_SERVER_URL-derived bridgeServerUrl"]
    B --> B2["secure storage\nstores BRIDGE_AUTH_TOKEN as bridge.auth_token"]
    B --> B3["normal settings/profile\nmust not persist BRIDGE_AUTH_TOKEN"]

    C["xworkmate-bridge"] --> C1["consume bootstrap response"]
    C1 --> C2["uses BRIDGE_SERVER_URL"]
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
    App->>SyncState: save bridgeServerUrl from BRIDGE_SERVER_URL
    App->>SecureStore: save bridge.auth_token from BRIDGE_AUTH_TOKEN
    App->>Bridge: connect with Authorization: Bearer <token>
```

## Test Coverage Targets

```mermaid
flowchart TD
    T["Account sync parsing tests"] --> T1["assert BRIDGE_SERVER_URL -> AccountSyncState.syncedDefaults.bridgeServerUrl"]
    T --> T2["assert BRIDGE_SERVER_URL -> cloudSynced.remoteServerSummary.endpoint"]
    T --> T3["assert BRIDGE_AUTH_TOKEN -> secure storage target bridge.auth_token"]
    T --> T4["assert BRIDGE_AUTH_TOKEN never enters normal settings/profile persistence"]
    T --> T5["assert offline path can still read token from secure storage"]
```

## Expected Invariants

- `BRIDGE_SERVER_URL` is the only bridge endpoint field used by the sync contract.
- `BRIDGE_AUTH_TOKEN` is the only bridge token field used by the sync contract.
- `BRIDGE_AUTH_TOKEN` must never be written into normal settings snapshot, profile JSON, or UI-visible text.
- Client requests must assemble the header as `Authorization: Bearer <token>`.
