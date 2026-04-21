# Account Sync, Settings, and Bridge State Model

Last Updated: 2026-04-21

This document is the canonical state model for:

- `SettingsSnapshot`
- `AccountSyncState`
- `BRIDGE_SERVER_URL`
- `BRIDGE_AUTH_TOKEN`

The goal is to keep three ownership layers distinct:

- **Persistent settings**: user-visible, non-secret configuration
- **Account sync metadata**: sync outcome plus bridge metadata derived from protected account responses
- **Secure secrets**: tokens and other material that must never enter normal settings persistence

## Ownership Model

```mermaid
flowchart TD
    A["accounts.svc.plus\nprotected login / MFA / sync / bootstrap response"] --> B["xworkmate-app"]

    B --> C["SettingsSnapshot\npersistent settings"]
    B --> D["AccountSyncState\nsync result + metadata"]
    B --> E["Secure storage / managed secret\nBRIDGE_AUTH_TOKEN"]

    D --> D1["syncState / syncMessage / lastSyncAtMs / lastSyncError"]
    D --> D2["syncedDefaults.bridgeServerUrl\nmetadata only"]
    D --> D3["tokenConfigured.bridge\nbridge token availability flag"]

    E --> E1["bridge.auth_token"]
    E --> E2["Authorization: Bearer <token>"]

    C --> F["AcpBridgeServerModeConfig.selfHosted"]
    D --> G["AcpBridgeServerModeConfig.cloudSynced"]
    F --> H["AcpBridgeServerModeConfig.effective"]
    G --> H
    H --> I["runtime effective endpoint"]
```

## State Flow

```mermaid
stateDiagram-v2
    [*] --> SignedOut

    SignedOut: no account session
    SignedOut --> SignedOut: do not send\nno fallback\nno stale token read
    SignedOut --> Syncing: svc.plus login

    Syncing: sync bridge config after login
    Syncing --> SyncBlocked: missing BRIDGE_AUTH_TOKEN\nor sync failed
    Syncing --> BridgeDiscovering: bridge URL + token synced

    SyncBlocked: signed in but bridge unavailable
    SyncBlocked --> Syncing: user syncs again
    SyncBlocked --> SignedOut: logout clears session/token/catalog

    BridgeDiscovering: load acp.capabilities from /acp/rpc
    BridgeDiscovering --> SyncBlocked: 401/403/token missing\nor endpoint missing
    BridgeDiscovering --> BridgeReady: providerCatalog/gatewayProviders valid

    BridgeReady: assistant can send
    BridgeReady --> ProviderDispatch: user submits message
    BridgeReady --> SignedOut: logout clears session/token/catalog

    ProviderDispatch: resolve endpoint by selected provider
    ProviderDispatch --> AgentEndpoint: Hermes/Codex/Gemini/OpenCode
    ProviderDispatch --> GatewayEndpoint: OpenClaw Gateway

    AgentEndpoint: /acp-server/{provider}/acp/rpc
    GatewayEndpoint: /gateway/openclaw/acp/rpc

    AgentEndpoint --> BridgeReady: result returned
    GatewayEndpoint --> BridgeReady: result returned
    AgentEndpoint --> SyncBlocked: auth failure
    GatewayEndpoint --> SyncBlocked: auth failure
```

## Field Semantics

```mermaid
flowchart LR
    A["BRIDGE_SERVER_URL"] --> B["AccountSyncState.syncedDefaults.bridgeServerUrl"]
    A --> C["account sync metadata only"]
    A --> D["not runtime source of truth"]

    E["BRIDGE_AUTH_TOKEN"] --> F["secure storage / managed secret"]
    E --> G["never in SettingsSnapshot"]
    E --> H["runtime Authorization header"]
```

## Runtime Resolution

```mermaid
flowchart TD
    A["AcpBridgeServerModeConfig.selfHosted"] --> C["effective endpoint"]
    B["AccountSyncState + secure storage"] --> D["cloudSynced path"]
    D --> C
    C --> E["bridge runtime"]

    note1["Priority order\n1. selfHosted when explicitly configured\n2. cloudSynced when account sync is ready and token exists\n3. disconnected"] --> C
```

### Runtime Invariants

- `selfHosted` always wins when it is configured.
- `cloudSynced` is valid only when account sync is ready and the managed bridge token exists.
- Signed-out state is disconnected: runtime must not use a default managed endpoint, stale managed secret, gateway profile token, or loopback ACP endpoint.
- Missing `BRIDGE_AUTH_TOKEN` is disconnected for the managed cloud-sync path.
- `BRIDGE_SERVER_URL` may be retained in `AccountSyncState.syncedDefaults.bridgeServerUrl`, but it is metadata only.
- `BRIDGE_AUTH_TOKEN` is written to secure storage only, never to normal settings.
- Bridge runtime requests use `Authorization: Bearer <token>` from secure storage.
- Capabilities and routing discovery use the bridge root `/acp/rpc`; assistant execution uses provider-specific public endpoints.

## Persistence Rules

- `SettingsSnapshot`
  - stores user-facing configuration and bridge mode config
  - stores the effective `AcpBridgeServerModeConfig`
  - must not store `BRIDGE_AUTH_TOKEN`

- `AccountSyncState`
  - stores sync state, timestamps, sync error, and token availability flags
  - stores `BRIDGE_SERVER_URL` as sync metadata only
  - can be persisted safely in secure storage because it contains no raw token

- Secure storage / managed secret
  - stores `BRIDGE_AUTH_TOKEN`
  - is the only place that should hold the bridge authorization token

## Cross-References

- [Bridge Sync Contract Chain](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/testing/bridge-sync-contract-chain.md)
- [Settings Integration Configuration Model](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/settings-integration-configuration-model.md)
- [Secure Development Rules](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/security/secure-development-rules.md)
