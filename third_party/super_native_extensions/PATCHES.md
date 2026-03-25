This directory vendors `super_native_extensions` 0.9.1 from pub.dev.

Local patch:
- `cargokit/build_tool/lib/src/artifacts_provider.dart`
  Adds retry coverage for transient `ClientException` download failures and
  falls back to `curl` for GitHub release assets so macOS packaging is less
  likely to fail on interrupted HTTP headers.
