# Secure Development Rules

This project ships a Flutter desktop/mobile client that connects to an OpenClaw gateway and handles user-provided credentials, native entitlements, and file attachments. Treat auth, secret handling, storage, transport, and packaging as security-sensitive by default.

## 1. Configuration And Secrets

- `.env` is a bootstrap helper for local development and test only.
- `.env` values may prefill the Gateway form, but they must not silently become the persisted runtime configuration.
- `.env` values must never trigger an automatic gateway connection.
- Do not hardcode real hosts, tokens, passwords, or API keys into Dart, native code, Xcode project files, tests, or scripts.
- Persisted secrets belong in `FlutterSecureStorage` or an equivalent secure store, never in `SharedPreferences`.
- Error banners, logs, debug prints, and screenshots must not expose full secret values.

## 2. Gateway And Network Trust Boundary

- Keep the gateway endpoint, auth token, password, and TLS choice explicit.
- The managed bridge / gateway runtime path is remote-only and pinned to the managed bridge origin.
- `BRIDGE_SERVER_URL` must not become the runtime source of truth for bridge startup or task dialog sends.
- Remote connections must not silently downgrade from TLS to non-TLS.
- Explicit loopback / non-TLS behavior is only allowed in isolated external ACP self-host test flows, not in the managed bridge / gateway main path.
- A user-initiated connect action may use the current form values directly for the active handshake. Persistence is a separate concern and must not be required for the immediate request.
- When changing auth behavior, verify both success and rejection paths.

## 3. Storage, Logging, And UI Handling

- Separate display state from secret state. UI text fields may hold user input transiently, but persisted secret storage must be explicit.
- Do not copy secrets into analytics events, audit trails, widget snapshots, or test golden artifacts.
- Mask secret values anywhere they are shown after save.
- If a form field is security-sensitive, saving/submitting must use the current controller value even when the user has not pressed return or changed focus.

## 4. Files, Attachments, And Workspace Access

- Only send files the user explicitly selected.
- Do not auto-attach local files based on workspace discovery, current tab, or inferred context.
- Limit attachment metadata and payload construction to the selected files.
- If a feature requires filesystem or shell access, document the boundary and keep it least-privilege.

## 5. Native Permissions And Packaging

- Any new entitlement in `macos/Runner/*.entitlements`, `ios/Runner/*.entitlements`, or Xcode project capabilities must be minimal and feature-justified.
- Build or packaging scripts must not embed secrets into the app bundle, DMG, or generated metadata.
- Packaging and install steps must preserve the same runtime security assumptions as debug builds.

## 6. Required Verification

Run these baseline checks for security-sensitive changes:

```bash
flutter analyze
flutter test
rg -n "\\.env|RuntimeBootstrapConfig|saveGatewayToken|saveGatewayPassword|FlutterSecureStorage|SharedPreferences" lib test
rg -n "token|password|secret|api[_-]?key" lib test ios macos scripts --glob '!**/Pods/**' --glob '!**/*.g.dart'
```

If device-run integration is needed on macOS, run cases serially:

```bash
pkill -f '/build/macos/Build/Products/Debug/XWorkmate.app/Contents/MacOS/XWorkmate' || true
flutter test integration_test/desktop_navigation_flow_test.dart -d macos
pkill -f '/build/macos/Build/Products/Debug/XWorkmate.app/Contents/MacOS/XWorkmate' || true
flutter test integration_test/desktop_settings_flow_test.dart -d macos
```

If a device-run hangs instead of asserting, mark it as manual follow-up and leave a concrete test path.

## 7. Stop-Ship Conditions

Do not mark the change complete if any of these remain true:

- a real token or password is committed or shown in logs
- `.env` changed from prefill-only into runtime source of truth
- remote transport silently dropped TLS
- a new entitlement was added without justification
- auth or secret handling changed without regression coverage
