# XWorkmate

XWorkmate is a desktop-first AI workspace shell built with Flutter.

## Platforms

- macOS
- Windows
- Linux
- iOS
- Android

## Development

```bash
flutter analyze
flutter test
flutter run -d macos
```

## Vendor Repositories

`vendor/codex` is tracked as a git submodule for future built-in code agent integration.

```bash
git submodule update --init --recursive
```

## macOS Packaging

```bash
pnpm desktop:package:mac
pnpm desktop:install:mac
```
