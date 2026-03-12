# Gateway Dev Runbook

This runbook covers the `XWorkmate.svc.plus` client when it connects directly to an OpenClaw gateway for local and remote development, pairing approval, and release verification.

## Scope

- UI repo: `/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus`
- Gateway repo: `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw.svc.plus`
- macOS reference implementation:
  - `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw.svc.plus/apps/macos/Sources/OpenClaw/GatewayEndpointStore.swift`
  - `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw.svc.plus/apps/macos/Sources/OpenClaw/GatewayRemoteConfig.swift`
  - `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw.svc.plus/apps/macos/Sources/OpenClaw/DevicePairingApprovalPrompter.swift`

## Security Boundary

- `.env` is development prefill only. It must not become the persisted source of truth and must not auto-connect the gateway.
- Shared tokens and passwords are user-entered auth inputs. Never hardcode them in Dart, native code, tests, or scripts.
- Long-lived secrets belong in secure storage. XWorkmate also keeps a file-backed fallback for device identity and operator device token so release builds keep a stable paired identity.
- Local mode may use plain `ws://127.0.0.1:18789`.
- Remote mode must use TLS, for example `wss://openclaw.svc.plus:443`.

## Endpoint Matrix

- XWorkmate direct local gateway auth:
  - `ws://127.0.0.1:18789`
- XWorkmate direct remote gateway auth:
  - `wss://openclaw.svc.plus:443`
- OpenClaw operator control page for pairing approval:
  - [https://openclaw.svc.plus/nodes](https://openclaw.svc.plus/nodes)
- Local web console style endpoint:
  - `http://127.0.0.1:18789`

Do not enter `http://` or `https://` into the XWorkmate gateway dialog unless the code explicitly expects a browser console URL. The app-level gateway connection is `ws://` or `wss://`.

## Config Sources

- Development prefill file:
  - `/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/.env`
- Persisted settings snapshot:
  - `~/Library/Containers/plus.svc.xworkmate/Data/Library/Preferences/plus.svc.xworkmate.plist`
  - key: `flutter.xworkmate.settings.snapshot`
- File-backed stable device identity fallback:
  - `~/Library/Containers/plus.svc.xworkmate/Data/Library/Application Support/plus.svc.xworkmate/xworkmate/gateway-auth/gateway-device-identity.json`
- File-backed operator device token fallback:
  - `~/Library/Containers/plus.svc.xworkmate/Data/Library/Application Support/plus.svc.xworkmate/xworkmate/gateway-auth/gateway-device-token.<deviceId>.operator.txt`

## Expected Remote Pairing Flow

1. Open `设置 -> 集成 -> Gateway`.
2. Choose `远程`.
3. Enter host `openclaw.svc.plus`, port `443`, TLS on.
4. Enter a valid shared token.
5. Click `连接`.
6. First successful auth should return `NOT_PAIRED: pairing required`.
7. Open [https://openclaw.svc.plus/nodes](https://openclaw.svc.plus/nodes) and approve the pending `XWorkmate Mac` device.
8. Return to XWorkmate and reconnect.
9. The second connect should succeed and the gateway should return an operator `deviceToken`.
10. Later reconnects should reuse the same `deviceId` and move to `device-token` auth instead of creating a fresh pairing request.

## Root Cause Analysis: Repeating `pairing required`

### Symptom

- XWorkmate could connect locally and chat normally.
- Remote shared-token auth reached the gateway, but remote connect repeatedly ended with `NOT_PAIRED: pairing required`.
- The operator page showed one `Pending` `XWorkmate Mac` entry and one older `Paired` `XWorkmate Mac` entry at the same time.

### Evidence Pattern

- `Pending.deviceId != Paired.deviceId`
- Reconnecting from the same installed app generated a fresh pending request instead of reusing the already paired device.
- This proves the failure was not “approval missing” alone. The client was presenting a different device identity on later remote connects.

### Why This Happened

OpenClaw pairing is keyed to the device identity:

- `device.id`
- `device.publicKey`
- signed device-auth payload
- pinned client metadata such as platform and device family

If the client does not persist and reload the same identity, the gateway must treat the connect as a new device and request pairing again.

The problematic path in XWorkmate was:

1. Remote connect created or loaded a device identity.
2. The identity and operator device token relied on secure storage only.
3. In the installed app path, that persistence was not stable enough for repeated remote reconnect debugging.
4. The next remote connect surfaced a different `deviceId`, so the gateway created another pending pairing request.

### Fix Strategy

Align XWorkmate with the OpenClaw macOS reference:

- Keep shared token and password in secure storage.
- Keep a stable file-backed fallback for:
  - device identity
  - operator device token
- Prefer secure storage on read, but hydrate from the fallback file when secure storage does not produce the identity/token.
- Show the current `deviceId` in the pairing-required UI so the operator can match it against the control page immediately.

### Code Locations

- XWorkmate stable device identity and device token fallback:
  - `/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/secure_config_store.dart`
- XWorkmate local device identity model:
  - `/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/runtime/runtime_models.dart`
- XWorkmate pairing diagnostics banner:
  - `/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/lib/widgets/gateway_connect_dialog.dart`
- OpenClaw macOS reference:
  - `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw.svc.plus/apps/macos/Sources/OpenClaw/GatewayEndpointStore.swift`
  - `/Users/shenlan/workspaces/cloud-neutral-toolkit/openclaw.svc.plus/apps/shared/OpenClawKit/Sources/OpenClawKit/DeviceIdentity.swift`

### Fix Validation

After the fix:

- The app keeps a stable local `deviceId`.
- The first remote shared-token connect may still need one approval if the previously paired record belongs to an older rotating identity.
- After that approval, reconnect must reuse the same `deviceId`.
- The operator page should stop accumulating a new `Pending` request for each reconnect.

## Pairing Loop Diagnosis

The critical check is whether `Pending` and `Paired` show the same `deviceId`.

- Healthy:
  - `Pending` appears once on first shared-token connect.
  - After approval, reconnect succeeds.
  - The same `deviceId` becomes `Paired`.
- Broken:
  - `Pending` keeps showing a new `deviceId`.
  - `Paired` already contains an older `deviceId`.
  - XWorkmate reconnects as a different device each time and loops on `pairing required`.

### Fast Diagnosis Steps

1. In XWorkmate, open the gateway dialog and read the error banner.
2. Note the `当前设备 ID` shown under pairing-required guidance.
3. In [https://openclaw.svc.plus/nodes](https://openclaw.svc.plus/nodes), compare that ID against:
   - `Pending`
   - `Paired`
4. If the IDs differ, the client is not reusing a stable local identity.

### Local Reset For A Broken Pairing Loop

Run these steps only when the device ID keeps changing or the stored operator token is clearly stale:

```bash
rm -f "$HOME/Library/Containers/plus.svc.xworkmate/Data/Library/Application Support/plus.svc.xworkmate/xworkmate/gateway-auth/gateway-device-identity.json"
rm -f "$HOME/Library/Containers/plus.svc.xworkmate/Data/Library/Application Support/plus.svc.xworkmate/xworkmate/gateway-auth/gateway-device-token."*.operator.txt
```

Then:

1. Remove stale paired `XWorkmate Mac` entries from the operator page if they are no longer valid.
2. Reopen XWorkmate.
3. Connect with the shared token once.
4. Approve the single new pending request.
5. Reconnect and verify the same `deviceId` now appears in `Paired`.

## Common Error Meanings

- `AUTH_TOKEN_MISSING`
  - The active handshake did not carry a shared token or device token.
  - Check the current form input first, then stored secure refs.
- `CONNECT_CHALLENGE_TIMEOUT`
  - Usually an invalid `ws/wss` endpoint, reverse proxy mismatch, or malformed stored host value.
  - Confirm the final gateway target is `openclaw.svc.plus:443` for remote mode.
- `PAIRING_REQUIRED`
  - Shared token auth succeeded, but the current device is not yet paired, or the gateway is treating the connect as a metadata or scope upgrade.
- `AUTH_DEVICE_TOKEN_MISMATCH`
  - Local operator device token is stale or revoked.
  - Clear the stored device token and reconnect once with the shared token.

## Runtime Debugging

- XWorkmate UI:
  - `设置 -> 运行日志`
  - Check `connect`, `auth`, `socket`, and `pairing` entries.
- macOS preferences snapshot:
  - `defaults read "$HOME/Library/Containers/plus.svc.xworkmate/Data/Library/Preferences/plus.svc.xworkmate.plist"`
- OpenClaw operator state:
  - [https://openclaw.svc.plus/nodes](https://openclaw.svc.plus/nodes)
- OpenClaw CLI on gateway host:
  - `openclaw devices list`

Do not paste real tokens into issues, commits, or logs.

## Development Validation

Baseline checks:

```bash
flutter analyze
flutter test
```

macOS integration tests must run serially:

```bash
pkill -f '/build/macos/Build/Products/Debug/XWorkmate.app/Contents/MacOS/XWorkmate' || true
flutter test integration_test/desktop_navigation_flow_test.dart -d macos
pkill -f '/build/macos/Build/Products/Debug/XWorkmate.app/Contents/MacOS/XWorkmate' || true
flutter test integration_test/desktop_settings_flow_test.dart -d macos
```

Build and install:

```bash
flutter build macos
flutter build ios --simulator
make install-mac
```

If a device-run test hangs instead of failing with an assertion, record it as manual follow-up.

## Manual Acceptance

1. Verify local mode can connect and chat through `ws://127.0.0.1:18789`.
2. Verify remote mode can connect through `wss://openclaw.svc.plus:443`.
3. Verify first remote connect creates one pending pairing request.
4. Approve that request from [https://openclaw.svc.plus/nodes](https://openclaw.svc.plus/nodes).
5. Reconnect and verify the same `deviceId` is now listed under `Paired`.
6. Restart the app and verify remote reconnect does not create a fresh pending request.
