/// FFI bindings for Codex CLI integration.
///
/// These bindings provide direct access to the native Rust library.
library codex_ffi_bindings;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ============================================================================
// FFI Structures
// ============================================================================

/// FFI-compatible result type.
final class CodexResultFFI extends Struct {
  @Bool()
  external bool success;

  @Int32()
  external int errorCode;

  external Pointer<Utf8> errorMessage;
}

/// FFI-compatible message type.
final class CodexMessageFFI extends Struct {
  external Pointer<Utf8> messageType;
  external Pointer<Utf8> content;
  external Pointer<Utf8> threadId;
  external Pointer<Utf8> turnId;
}

/// FFI-compatible event type.
final class CodexEventFFI extends Struct {
  external Pointer<Utf8> eventType;
  external Pointer<Utf8> threadId;
  external Pointer<Utf8> turnId;
  external Pointer<Utf8> data;
  @Int64()
  external int timestamp;
}

/// FFI-compatible configuration.
final class CodexConfigFFI extends Struct {
  external Pointer<Utf8> codexPath;
  external Pointer<Utf8> workingDirectory;
  @Int32()
  external int sandboxMode;
  @Int32()
  external int approvalPolicy;
  external Pointer<Utf8> model;
  external Pointer<Utf8> apiKey;
  external Pointer<Utf8> gatewayUrl;
  @Bool()
  external bool debug;
}

/// Opaque thread handle.
final class ThreadHandleFFI extends Struct {
  @Uint64()
  external int id;
}

// ============================================================================
// Native Functions
// ============================================================================

typedef _CodexInitNative = Int32 Function();
typedef _CodexInitDart = int Function();

typedef _CodexRuntimeCreateNative = Pointer<CodexRuntime> Function(
    Pointer<CodexConfigFFI> config);
typedef _CodexRuntimeCreateDart = Pointer<CodexRuntime> Function(
    Pointer<CodexConfigFFI> config);

typedef _CodexRuntimeDestroyNative = Void Function(Pointer<CodexRuntime> runtime);
typedef _CodexRuntimeDestroyDart = void Function(Pointer<CodexRuntime> runtime);

typedef _CodexStartThreadNative = ThreadHandleFFI Function(
    Pointer<CodexRuntime> runtime, Pointer<Utf8> cwd);
typedef _CodexStartThreadDart = ThreadHandleFFI Function(
    Pointer<CodexRuntime> runtime, Pointer<Utf8> cwd);

typedef _CodexSendMessageNative = Int32 Function(
    Pointer<CodexRuntime> runtime, ThreadHandleFFI thread, Pointer<Utf8> message);
typedef _CodexSendMessageDart = int Function(
    Pointer<CodexRuntime> runtime, ThreadHandleFFI thread, Pointer<Utf8> message);

typedef _CodexPollEventsNative = UintPtr Function(
    Pointer<CodexRuntime> runtime, Pointer<CodexEventFFI> events, UintPtr maxEvents);
typedef _CodexPollEventsDart = int Function(
    Pointer<CodexRuntime> runtime, Pointer<CodexEventFFI> events, int maxEvents);

typedef _CodexShutdownNative = Int32 Function(Pointer<CodexRuntime> runtime);
typedef _CodexShutdownDart = int Function(Pointer<CodexRuntime> runtime);

typedef _CodexLastErrorNative = Pointer<Utf8> Function(Pointer<CodexRuntime> runtime);
typedef _CodexLastErrorDart = Pointer<Utf8> Function(Pointer<CodexRuntime> runtime);

// Opaque runtime type
final class CodexRuntime extends Opaque {}

// ============================================================================
// Dart Wrapper Class
// ============================================================================

/// Dart wrapper for Codex FFI.
class CodexFFIBindings {
  final DynamicLibrary _lib;
  late final _CodexInitDart _init;
  late final _CodexRuntimeCreateDart _runtimeCreate;
  late final _CodexRuntimeDestroyDart _runtimeDestroy;
  late final _CodexStartThreadDart _startThread;
  late final _CodexSendMessageDart _sendMessage;
  late final _CodexPollEventsDart _pollEvents;
  late final _CodexShutdownDart _shutdown;
  late final _CodexLastErrorDart _lastError;

  Pointer<CodexRuntime>? _runtime;

  CodexFFIBindings() : _lib = _loadLibrary() {
    _init = _lib.lookupFunction<_CodexInitNative, _CodexInitDart>('codex_init');
    _runtimeCreate = _lib.lookupFunction<_CodexRuntimeCreateNative, _CodexRuntimeCreateDart>(
        'codex_runtime_create');
    _runtimeDestroy = _lib.lookupFunction<_CodexRuntimeDestroyNative, _CodexRuntimeDestroyDart>(
        'codex_runtime_destroy');
    _startThread = _lib.lookupFunction<_CodexStartThreadNative, _CodexStartThreadDart>(
        'codex_start_thread');
    _sendMessage = _lib.lookupFunction<_CodexSendMessageNative, _CodexSendMessageDart>(
        'codex_send_message');
    _pollEvents = _lib.lookupFunction<_CodexPollEventsNative, _CodexPollEventsDart>(
        'codex_poll_events');
    _shutdown = _lib.lookupFunction<_CodexShutdownNative, _CodexShutdownDart>(
        'codex_shutdown');
    _lastError = _lib.lookupFunction<_CodexLastErrorNative, _CodexLastErrorDart>(
        'codex_last_error');
  }

  static DynamicLibrary _loadLibrary() {
    if (Platform.isMacOS) {
      return DynamicLibrary.open('libcodex_ffi.dylib');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libcodex_ffi.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('codex_ffi.dll');
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// Initialize the library.
  void initialize() {
    final result = _init();
    if (result != 0) {
      throw StateError('Failed to initialize Codex FFI');
    }
  }

  /// Create a runtime with configuration.
  void createRuntime(CodexConfig config) {
    if (_runtime != null) {
      throw StateError('Runtime already created');
    }

    final configPtr = _createConfigFFI(config);
    try {
      _runtime = _runtimeCreate(configPtr);
      if (_runtime == nullptr) {
        throw StateError('Failed to create runtime');
      }
    } finally {
      _freeConfigFFI(configPtr);
    }
  }

  /// Destroy the runtime.
  void destroyRuntime() {
    if (_runtime != null) {
      _runtimeDestroy(_runtime!);
      _runtime = nullptr;
    }
  }

  /// Start a new thread.
  int startThread(String cwd) {
    _ensureRuntime();
    final cwdPtr = cwd.toNativeUtf8();
    try {
      final handle = _startThread(_runtime!, cwdPtr);
      return handle.id;
    } finally {
      calloc.free(cwdPtr);
    }
  }

  /// Send a message to the thread.
  int sendMessage(int threadId, String message) {
    _ensureRuntime();
    final messagePtr = message.toNativeUtf8();
    final handlePtr = calloc<ThreadHandleFFI>();
    try {
      handlePtr.ref.id = threadId;
      return _sendMessage(_runtime!, handlePtr.ref, messagePtr);
    } finally {
      calloc.free(messagePtr);
      calloc.free(handlePtr);
    }
  }

  /// Poll for events.
  List<Map<String, dynamic>> pollEvents(int maxEvents) {
    _ensureRuntime();
    final eventsPtr = calloc<CodexEventFFI>(maxEvents);
    try {
      final count = _pollEvents(_runtime!, eventsPtr, maxEvents);
      final events = <Map<String, dynamic>>[];
      for (var i = 0; i < count; i++) {
        final event = eventsPtr[i];
        events.add({
          'eventType': event.eventType.toDartString(),
          'threadId': event.threadId.toDartString(),
          'turnId': event.turnId.toDartString(),
          'data': event.data.toDartString(),
          'timestamp': event.timestamp,
        });
      }
      return events;
    } finally {
      calloc.free(eventsPtr);
    }
  }

  /// Shutdown the runtime.
  void shutdown() {
    _ensureRuntime();
    _shutdown(_runtime!);
  }

  /// Get last error message.
  String? lastError() {
    if (_runtime == null) return null;
    final ptr = _lastError(_runtime!);
    if (ptr == nullptr) return null;
    return ptr.toDartString();
  }

  void _ensureRuntime() {
    if (_runtime == null) {
      throw StateError('Runtime not initialized');
    }
  }

  Pointer<CodexConfigFFI> _createConfigFFI(CodexConfig config) {
    final ptr = calloc<CodexConfigFFI>();
    ptr.ref.codexPath = config.codexPath?.toNativeUtf8() ?? nullptr;
    ptr.ref.workingDirectory = config.workingDirectory?.toNativeUtf8() ?? nullptr;
    ptr.ref.sandboxMode = config.sandboxMode;
    ptr.ref.approvalPolicy = config.approvalPolicy;
    ptr.ref.model = config.model?.toNativeUtf8() ?? nullptr;
    ptr.ref.apiKey = config.apiKey?.toNativeUtf8() ?? nullptr;
    ptr.ref.gatewayUrl = config.gatewayUrl?.toNativeUtf8() ?? nullptr;
    ptr.ref.debug = config.debug;
    return ptr;
  }

  void _freeConfigFFI(Pointer<CodexConfigFFI> ptr) {
    if (ptr.ref.codexPath != nullptr) calloc.free(ptr.ref.codexPath);
    if (ptr.ref.workingDirectory != nullptr) calloc.free(ptr.ref.workingDirectory);
    if (ptr.ref.model != nullptr) calloc.free(ptr.ref.model);
    if (ptr.ref.apiKey != nullptr) calloc.free(ptr.ref.apiKey);
    if (ptr.ref.gatewayUrl != nullptr) calloc.free(ptr.ref.gatewayUrl);
    calloc.free(ptr);
  }
}

/// Configuration for Codex FFI.
class CodexConfig {
  final String? codexPath;
  final String? workingDirectory;
  final int sandboxMode;
  final int approvalPolicy;
  final String? model;
  final String? apiKey;
  final String? gatewayUrl;
  final bool debug;

  const CodexConfig({
    this.codexPath,
    this.workingDirectory,
    this.sandboxMode = 1, // workspace-write
    this.approvalPolicy = 0, // suggest
    this.model,
    this.apiKey,
    this.gatewayUrl,
    this.debug = false,
  });
}
