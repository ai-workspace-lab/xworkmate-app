#!/bin/bash
# Build Rust FFI library for macOS
# Usage: ./scripts/build_rust_ffi.sh [release|debug]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/rust"

BUILD_MODE="${1:-release}"
TARGET_DIR="$RUST_DIR/target"

echo "Building codex-ffi ($BUILD_MODE)..."

cd "$RUST_DIR"

# Check if cargo is available
if ! command -v cargo &> /dev/null; then
    echo "Error: cargo not found. Please install Rust: https://rustup.rs"
    exit 1
fi

# Build for macOS (arm64 and x86_64)
if [[ "$BUILD_MODE" == "release" ]]; then
    echo "Building release mode..."
    cargo build --release --target aarch64-apple-darwin
    cargo build --release --target x86_64-apple-darwin
    
    # Create universal binary
    mkdir -p "$TARGET_DIR/universal"
    lipo -create \
        "$TARGET_DIR/aarch64-apple-darwin/release/libcodex_ffi.a" \
        "$TARGET_DIR/x86_64-apple-darwin/release/libcodex_ffi.a" \
        -output "$TARGET_DIR/universal/libcodex_ffi.a"
    
    lipo -create \
        "$TARGET_DIR/aarch64-apple-darwin/release/libcodex_ffi.dylib" \
        "$TARGET_DIR/x86_64-apple-darwin/release/libcodex_ffi.dylib" \
        -output "$TARGET_DIR/universal/libcodex_ffi.dylib"
    
    echo "Universal binary created at $TARGET_DIR/universal/"
else
    echo "Building debug mode..."
    cargo build --target aarch64-apple-darwin
    cargo build --target x86_64-apple-darwin
fi

# Copy to macOS Frameworks directory
FRAMEWORKS_DIR="$PROJECT_ROOT/macos/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"

if [[ "$BUILD_MODE" == "release" ]]; then
    cp "$TARGET_DIR/universal/libcodex_ffi.dylib" "$FRAMEWORKS_DIR/"
else
    cp "$TARGET_DIR/aarch64-apple-darwin/debug/libcodex_ffi.dylib" "$FRAMEWORKS_DIR/"
fi

echo "Library copied to $FRAMEWORKS_DIR/"
echo "Build complete!"
