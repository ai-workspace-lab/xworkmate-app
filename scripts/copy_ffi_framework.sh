#!/bin/bash
# Copy FFI library to macOS Frameworks
# Add this to Xcode Build Phases > Run Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FRAMEWORKS_DIR="$PROJECT_ROOT/macos/Frameworks"
RUST_DIR="$PROJECT_ROOT/rust"

# Source FFI library location
UNIVERSAL_LIB="$RUST_DIR/target/universal/libcodex_ffi.dylib"
ARM_LIB="$RUST_DIR/target/aarch64-apple-darwin/release/libcodex_ffi.dylib"
RELEASE_LIB="$RUST_DIR/target/release/libcodex_ffi.dylib"
DEBUG_LIB="$RUST_DIR/target/debug/libcodex_ffi.dylib"

# Ensure Frameworks directory exists
mkdir -p "$FRAMEWORKS_DIR"

# Copy universal binary if available, otherwise fall back to single architecture
if [[ -f "$UNIVERSAL_LIB" ]]; then
    echo "Copying universal FFI library..."
    cp "$UNIVERSAL_LIB" "$FRAMEWORKS_DIR/"
elif [[ -f "$ARM_LIB" ]]; then
    echo "Copying arm64 FFI library..."
    cp "$ARM_LIB" "$FRAMEWORKS_DIR/"
elif [[ -f "$RELEASE_LIB" ]]; then
    echo "Copying release FFI library..."
    cp "$RELEASE_LIB" "$FRAMEWORKS_DIR/"
elif [[ -f "$DEBUG_LIB" ]]; then
    echo "Copying debug FFI library..."
    cp "$DEBUG_LIB" "$FRAMEWORKS_DIR/"
else
    echo "Warning: FFI library not found. Run make rust-build-release first."
    echo "Expected one of:"
    echo "  - $UNIVERSAL_LIB"
    echo "  - $ARM_LIB"
    echo "  - $RELEASE_LIB"
    echo "  - $DEBUG_LIB"
    exit 0  # Don't fail the build if library doesn't exist yet
fi

echo "FFI library copied to $FRAMEWORKS_DIR/"
