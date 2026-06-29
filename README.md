# xworkmate-app

Flutter-based AI workspace shell for running assistant threads with local and remote gateway task execution via ACP bridge.

## Architecture

Single execution path: **Flutter → GoTaskServiceClient → ACP Transport → xworkmate-bridge → Remote Provider**

See [docs/architecture/](./docs/architecture/) for the full architecture documentation.

## Dependencies

| Repository | Role |
| --- | --- |
| [xworkmate-bridge](https://github.com/x-evor/xworkmate-bridge) | Go-based ACP control plane and bridge backend |
| [xworkspace-core-skills](https://github.com/x-evor/xworkspace-core-skills) | Core skill bundles (pptx, docx, xlsx, pdf, image, browser automation) |
| [openclaw-multi-session-plugins](https://github.com/x-evor/openclaw-multi-session-plugins) | OpenClaw Gateway multi-session plugin runtime |
| [playbooks](https://github.com/x-evor/playbooks) | Deployment playbooks and infrastructure automation |

## Quick Start

```bash
git clone https://github.com/x-evor/xworkmate-app.git
cd xworkmate-app
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

For local development, keep `xworkmate-bridge` checked out alongside `xworkmate-app`, or set `XWORKMATE_BRIDGE_DIR` explicitly before building.

## macOS (Xcode)

```bash
open macos/Runner.xcworkspace
# or
make open-macos-xcode
```

In Xcode:
- Select the shared `Runner` scheme
- Select `My Mac` as the destination
- Configure signing only on the `Runner` target
- Leave CocoaPods plugin targets under `Pods` alone

For release builds:

```bash
flutter build macos
make build-macos
```

For a one-line install from the latest GitHub release:

```bash
curl -sfL https://install.svc.plus/xworkmate-app | bash -
```

## Downloads

| Platform | Download |
| --- | --- |
| macOS | [Latest Release](https://github.com/x-evor/xworkmate-app/releases/latest) |
| Windows | [Latest Release](https://github.com/x-evor/xworkmate-app/releases/latest) |
| Linux | [Latest Release](https://github.com/x-evor/xworkmate-app/releases/latest) |
| iOS | [Latest Release](https://github.com/x-evor/xworkmate-app/releases/latest) |
| Android | [Latest Release](https://github.com/x-evor/xworkmate-app/releases/latest) |

## Learn More

- [Architecture Overview](./docs/architecture/README.md)
- [Core Integration Test Cases](./docs/cases/README.md)
- [Cross-Repo Task State Workflow](./docs/architecture/cross-repo-task-state-workflow.md)
- [CHANGELOG](./CHANGELOG.md)
