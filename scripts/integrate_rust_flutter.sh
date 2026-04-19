#!/bin/bash
# Integrate Rust FFI library with Flutter macOS build
# This script should be run before flutter build macos

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Integrating Rust FFI with Flutter..."

# Build Rust library if not exists
RUST_LIB="$PROJECT_ROOT/rust/target/universal/libcodex_ffi.dylib"
if [[ ! -f "$RUST_LIB" ]]; then
    echo "Rust library not found, building..."
    # Attempt to build using Makefile target if available
    (cd "$PROJECT_ROOT" && make rust-build-release)
fi

# Ensure Frameworks directory exists
FRAMEWORKS_DIR="$PROJECT_ROOT/macos/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

# Copy library
if [[ -f "$RUST_LIB" ]]; then
    cp "$RUST_LIB" "$FRAMEWORKS_DIR/"
    echo "Copied libcodex_ffi.dylib to $FRAMEWORKS_DIR/"
else
    echo "Warning: Universal binary not found, using arm64..."
    ARM_LIB="$PROJECT_ROOT/rust/target/aarch64-apple-darwin/release/libcodex_ffi.dylib"
    if [[ -f "$ARM_LIB" ]]; then
        cp "$ARM_LIB" "$FRAMEWORKS_DIR/"
        echo "Copied arm64 library to $FRAMEWORKS_DIR/"
    else
        echo "Error: No Rust library found. Please run 'make rust-build-release' first."
        exit 1
    fi
fi

# Update Xcode project to link the library
# This would typically be done via Xcode build phases
echo ""
echo "Note: You may need to add the following to your Xcode project:"
echo "  1. Add libcodex_ffi.dylib to 'Link Binary With Libraries' build phase"
echo "  2. Add macos/Frameworks to 'Framework Search Paths'"
echo ""

# Generate FFI bindings if needed
if [[ ! -f "$PROJECT_ROOT/lib/runtime/codex_ffi_generated.dart" ]]; then
    echo "Generating FFI bindings..."
    "$SCRIPT_DIR/generate_ffi_bindings.sh"
fi

echo "Integration complete!"
