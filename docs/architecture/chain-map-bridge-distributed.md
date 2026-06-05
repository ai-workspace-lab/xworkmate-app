# Chain Map: Bridge Distributed Forwarding

Repo chain: xworkmate-app → xworkmate-bridge (primary) → cn-xworkmate-bridge (edge) → OpenClaw

## Topology

```
┌─────────────────────────────────────────┐
│ xworkmate-app                           │
│ POST https://xworkmate-bridge.svc.plus  │
└──────────────────┬──────────────────────┘
                   │ Internet
                   ▼
┌─────────────────────────────────────────┐
│ xworkmate-bridge (primary)              │
│ Node: jp-xhttp-contabo.svc.plus         │
│ IP:   172.29.10.1:8787                  │
│ Role: primary, zone: jp                 │
└──────────────────┬──────────────────────┘
                   │ WireGuard VPN tunnel
                   │ (wg-xwm interface)
                   ▼
┌─────────────────────────────────────────┐
│ cn-xworkmate-bridge (edge)              │
│ Node: cn-xworkmate-bridge.svc.plus      │
│ IP:   172.29.10.2:8787                  │
│ Role: edge, zone: cn                    │
└─────────────────────────────────────────┘
                   │
                   ▼
           OpenClaw Gateway
```

## Config Structure

```yaml
# xworkmate-bridge config.yaml
distributed:
  strategy: dual-node   # or star, mesh
  nodes:
    - id: xworkmate-bridge
      endpoint: https://172.29.10.1:8787
      roles: [primary]
      zone: jp
      capabilities: [gateway, acp-provider]

    - id: cn-xworkmate-bridge
      endpoint: https://172.29.10.2:8787
      roles: [edge]
      zone: cn
      capabilities: [gateway]

  forwarding:
    rules:
      - match:
          methods: ["session.start", "session.message"]
          providers: ["openclaw"]
        route: xworkmate-bridge

      - match:
          methods: ["session.start", "session.message"]
          zones: ["cn"]
        route: cn-xworkmate-bridge

    routes:
      - name: xworkmate-bridge
        strategy: direct
        target: xworkmate-bridge

      - name: cn-xworkmate-bridge
        strategy: direct
        target: cn-xworkmate-bridge

    session_stickiness:
      ttl: 24h   # session.message follows session.start
```

## Forward Flow

```
App sends session.start with routing params
  └─ xworkmate-bridge primary: handleRequest()
     └─ distributedTaskRouter.shouldForward(request)
        ├─ Check forwarding.rules
        ├─ Match methods: ["session.start", "session.message"]
        ├─ Match providers: ["openclaw"] → select target based on zone
        │
        ├─ Primary (jp) target → handle locally
        │   └─ orchestrator.Process() → gateway.send(chat.send)
        │
        └─ Edge (cn) target → forward
           └─ HTTP POST https://172.29.10.2:8787/acp/rpc
              Headers:
                X-XWorkmate-Bridge-Forwarded: 1
                X-XWorkmate-Forward-Source: xworkmate-bridge
                X-XWorkmate-Forward-Target: cn-xworkmate-bridge
                X-XWorkmate-Forward-Trace: <id>
                X-XWorkmate-Forward-Hop: 1
                Authorization: Bearer <BRIDGE_TASK_FORWARD_TOKEN>
              Body: original JSON-RPC request

  Edge bridge receives forwarded request:
    └─ handleRequest() (same handler)
       ├─ Checks X-XWorkmate-Forward-Hop < 3 (hop limit)
       ├─ Session route store:
       │   └─ For session.start:
       │       └─ Store mapping: sessionId → target node
       │   └─ For session.message:
       │       └─ Lookup sessionId → target node
       │       └─ Route to the node that handled session.start
       │
       └─ orchestrator.Process() → gateway.send(chat.send)

  Response flows back through the same chain.
```

## Session Stickiness

```
session.start arrives at primary bridge:
  → distributedTaskRouter stores:
    session_routes[sessionId] = {
      targetNode: "xworkmate-bridge",
      createdAt: <timestamp>,
      ttl: 24h
    }

session.message arrives (any bridge):
  → distributedTaskRouter looks up sessionId:
    if found:
      → forward to targetNode (the node that handled session.start)
    if not found (expired or new bridge instance):
      → re-evaluate forwarding rules from scratch

This ensures all turns in a session go to the same node,
which holds the in-memory session state.
```

## Security Constraints

```
Forwarding endpoints MUST be:
  - Loopback (127.0.0.0/8)
  - Private (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
  - Link-local (169.254.0.0/16)

Public URLs are REJECTED for forwarding endpoints.

Auth:
  - XWORKMATE_BRIDGE_TASK_FORWARD_TOKEN (env var)
  - Falls back to BRIDGE_AUTH_TOKEN if not set

Hop limit:
  - X-XWorkmate-Forward-Hop: max 3
  - Exceeded → 502 Bad Gateway
```

## Deployment (playbooks)

```
roles/vhosts/xworkmate_bridge_distributed_vpn/
  ├─ WireGuard tunnel setup (wg-xwm interface)
  ├─ Xray + tproxy for VPN transport
  └─ systemd: wg-quick@wg-xwm, xray-wg-tproxy

group_vars/xworkmate_bridge_distributed.yml:
  ├─ Node IDs and roles
  ├─ WireGuard keys
  └─ Node endpoints

host_vars/cn-xworkmate-bridge.svc.plus.yml:
  └─ Host-specific: wg address, listen IP

host_vars/jp-xhttp-contabo.svc.plus/xworkmate_bridge_distributed.yml:
  └─ Host-specific: wg address, listen IP
```

## Call Chain for Forwarded Request

```
1. Primary bridge receives session.start
   → distributedTaskRouter.SelectNode(params):
     ├─ Match forwarding.rules against (method, provider, zone)
     ├─ If exact match → use target node
     ├─ If no match → handle locally
     └─ Log forwarding decision

2. Primary bridge forwards
   → httpForwardTask(node, request):
     ├─ Validate endpoint is private (no public URLs)
     ├─ Add forwarding headers
     ├─ HTTP POST to target node
     └─ Stream response back to caller

3. Edge bridge processes
   → Same handler as primary
   → Hop limit check
   → Session route registration
   → Normal task processing

4. Bridge identity per node
   → Each node has its own Ed25519 identity
   → Stored at ~/.xworkmate-bridge/openclaw-device.json
   → Different device IDs for primary vs edge
   → OpenClaw gateway sees them as separate runtimes
```

## Fragile Points

1. **D1: Session stickiness breaks on node failure**
   Session routes TTL is 24h. If primary node goes down and edge takes over, existing sessions can't be re-routed to edge. The session.message will try primary, fail, and the session is lost (in-memory state on primary).

2. **D2: Forward token mismatch**
   `XWORKMATE_BRIDGE_TASK_FORWARD_TOKEN` must be the same on all nodes. If it differs, forwarded requests are rejected with 401.

3. **D3: Hop limit too low for future topology**
   Current max 3 hops. If topology expands beyond star/double-node (mesh, relay chains), 3 hops may be insufficient.

4. **D4: Forwarding endpoint IP changes**
   Endpoints are hardcoded IPs in config.yaml. If VPN IPs change (recreated WireGuard tunnels), forwarding breaks until config is updated and bridge restarted.

5. **D5: Config drift between nodes**
   Primary and edge bridge instances run the same binary but may have different config.yaml. If distributed section differs, forwarding decisions may be inconsistent.

6. **D6: All-in-memory state amplifies risk**
   Both session state and session route store are in-memory. If either node restarts, both session data and routing stickiness are lost simultaneously.
