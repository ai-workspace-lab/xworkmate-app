#!/bin/bash
# Generate FFI bindings using flutter_rust_bridge
# Usage: ./scripts/generate_ffi_bindings.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Generating FFI bindings..."

# Check if flutter_rust_bridge is installed
if ! command -v flutter_rust_bridge_codegen &> /dev/null; then
    echo "Installing flutter_rust_bridge_codegen..."
    cargo install flutter_rust_bridge_codegen --version 2.0.0
fi

# Generate bindings
cd "$PROJECT_ROOT"

flutter_rust_bridge_codegen \
    --rust-input rust/src/lib.rs \
    --dart-output lib/runtime/codex_ffi_generated.dart \
    --dart-format-line-length 120 \
    --c-symbol-prefix codex_

echo "FFI bindings generated!"
echo "Dart output: lib/runtime/codex_ffi_generated.dart"

# Generate C header for reference
cbindgen rust/src/lib.rs -o rust/codex_ffi.h 2>/dev/null || echo "cbindgen not installed, skipping C header generation"

echo "Done!"
