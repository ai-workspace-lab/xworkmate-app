# macOS Frameworks

This directory contains native libraries for macOS integration.

## libcodex_ffi.dylib

The Rust FFI library for Codex CLI integration.

### Building

Run the build script from the project root:

```bash
make rust-build-release
```

### Integration

The library is linked by the Xcode project and loaded at runtime by `CodexFFIBindings`.

### Architecture

- `libcodex_ffi.dylib` - Universal binary (arm64 + x86_64)
- `libcodex_ffi.a` - Static library (for debugging)

### FFI Functions

| Function | Description |
|----------|-------------|
| `codex_init()` | Initialize the library |
| `codex_runtime_create()` | Create a runtime instance |
| `codex_runtime_destroy()` | Destroy a runtime instance |
| `codex_start_thread()` | Start a new thread |
| `codex_send_message()` | Send a message |
| `codex_poll_events()` | Poll for events |
| `codex_shutdown()` | Shutdown the runtime |
| `codex_last_error()` | Get last error message |

### Dependencies

- macOS 11.0 or later
- No external dependencies beyond system libraries
