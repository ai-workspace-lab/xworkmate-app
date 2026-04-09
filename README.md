# XWorkmate

XWorkmate is a Flutter-based AI workspace shell for running assistant threads, local or remote gateway tasks, and multi-agent collaboration in one app.

## Project

XWorkmate combines a desktop-first Flutter app, persistent assistant task threads, and optional multi-agent orchestration.
It is designed for users who want a single workspace for AI chat, gateway-backed execution, and packaged local tooling across macOS, web, and other client surfaces.

## Companion Repository

The ACP Bridge Server and embedded Go helper now live in the standalone companion repository:

- [`xworkmate-bridge`](https://github.com/x-evor/xworkmate-bridge)

For local development, keep `xworkmate-bridge` checked out alongside `xworkmate-app`, or set `XWORKMATE_BRIDGE_DIR` explicitly before building the helper.

## TL;DR

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

## Xcode Run For macOS

XWorkmate only supports launching the macOS app from the workspace entrypoint:

```bash
open macos/Runner.xcworkspace
```

If you prefer a repo-native shortcut, run:

```bash
make open-macos-xcode
```

In Xcode:

- Select the shared `Runner` scheme.
- Select `My Mac` as the destination.
- Configure signing only on the `Runner` target.
- Leave CocoaPods plugin targets under `Pods` alone. They appear in the workspace by design and are not app signing targets.

For release builds, archives, and packaging, continue to use:

```bash
flutter build macos
make build-macos
```

## Downloads

| Platform | Download |
| --- | --- |
| macOS | [Latest Release](https://github.com/x-evor/xworkmate.svc.plus/releases/latest) |
| Windows | [Latest Release](https://github.com/x-evor/xworkmate.svc.plus/releases/latest) |
| Linux | [Latest Release](https://github.com/x-evor/xworkmate.svc.plus/releases/latest) |
| iOS | [Latest Release](https://github.com/x-evor/xworkmate.svc.plus/releases/latest) |
| Android | [Latest Release](https://github.com/x-evor/xworkmate.svc.plus/releases/latest) |

All download buttons currently point to the latest GitHub release page.

## Snapshots

| Mobile | Desktop | Web |
| --- | --- | --- |
| ![XWorkmate Mobile](./images/mobile-app.PNG) | ![XWorkmate Desktop](./images/Desktop-APP.png) | ![XWorkmate Web](./images/web-online-services.png) |

## Learn More

- [Release Notes](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/releases/xworkmate-release-notes.md)
- [Changelog](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/releases/xworkmate-changelog.md)
- [Feature Matrix](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/plans/xworkmate-ui-feature-matrix.md)
- [Roadmap](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/plans/xworkmate-ui-feature-roadmap.md)
- [Gateway Dev Runbook](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/runbooks/gateway-dev-runbook.md)
- [Web Deployment](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/web-deployment.md)
- [Security Rules](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/security/secure-development-rules.md)
