#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

forbidden_paths=(
  "scripts/copy_ffi_framework.sh"
  "scripts/generate_ffi_bindings.sh"
  "scripts/integrate_rust_flutter.sh"
  "flutter_rust_bridge.yaml"
  "lib/runtime/codex_ffi_generated.dart"
  "macos/Frameworks/libcodex_ffi.dylib"
  "macos/Frameworks/README.md"
  "macos/Runner.xcodeproj/add_ffi_framework.sh"
)

failures=0
for relative_path in "${forbidden_paths[@]}"; do
  if [[ -e "$ROOT_DIR/$relative_path" ]]; then
    echo "Forbidden app-side FFI artifact remains: $relative_path" >&2
    failures=$((failures + 1))
  fi
done

if rg -n \
  "copy_ffi_framework|generate_ffi_bindings|integrate_rust_flutter|flutter_rust_bridge|libcodex_ffi|codex_ffi_generated|ffi-(copy|generate|integrate)|build-macos-ffi" \
  "$ROOT_DIR/Makefile" \
  "$ROOT_DIR/scripts" \
  "$ROOT_DIR/lib" \
  "$ROOT_DIR/macos/Runner.xcodeproj" \
  --glob '!scripts/check-no-app-ffi.sh' \
  --glob '!**/Pods/**' \
  --glob '!**/Flutter/ephemeral/**' \
  --glob '!**/build/**'; then
  echo "Forbidden app-side FFI integration reference found." >&2
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi

echo "No app-side Codex FFI integration artifacts found."
