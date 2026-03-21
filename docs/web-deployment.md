# XWorkmate Web Deployment

This repo now ships a browser-safe Flutter Web variant intended to be deployed at the root site:

- `https://xworkmate.svc.plus/`

## Product Scope

The Web app keeps only:

- `Assistant`
- `Settings`
- `Direct AI Gateway`
- `Relay OpenClaw Gateway`

The following remain desktop-only:

- local OpenClaw gateway mode
- local CLI orchestration
- workspace file and attachment access
- native desktop integrations
- desktop diagnostics/runtime surfaces

## Build Commands

Use a root-site build:

```bash
flutter build web --release --base-href /
```

Recommended validation before deployment:

```bash
flutter analyze
flutter test
flutter test --platform chrome test/widget_test.dart test/web
flutter build web --release --base-href /
```

## Static Hosting Notes

- Deploy the contents of `build/web/` at the site root.
- Keep `index.html` served from `/`.
- Flutter emits fingerprinted assets; publish the full directory together so `flutter_service_worker.js` and asset hashes stay aligned.
- Cache `index.html` conservatively or with revalidation so new asset manifests are picked up quickly after each release.
- Static assets under `build/web/assets/` and hashed JS files can be cached aggressively.

## Network Requirements

- `Direct AI Gateway` must be browser-reachable from the end user device.
- Direct gateway endpoints must allow the Web origin with correct CORS headers.
- If a provider cannot satisfy browser reachability or CORS constraints, users must use `Relay OpenClaw Gateway` instead.
- Relay endpoints should stay on TLS in production and must not silently downgrade to insecure transport for remote usage.

## Persistence and Secrets

- Web configuration is stored in browser-local persistent storage on the current device.
- This includes the selected execution target, direct gateway settings, relay settings, and Web conversation metadata.
- Web persistence is less secure than desktop secure storage; use trusted devices only.
- `.env` remains desktop/development prefill-only and is not auto-imported into Web runtime behavior.
