import 'package:flutter/foundation.dart';

/// Where a plugin's definition (and optional local step handlers) come from
/// (plan §8.4).
///
/// Execution of heavy work always routes through the existing gateway
/// pipeline; a runtime binding only decides how the app obtains the plugin's
/// workflow manifest and, later, optional local pre/post-processing hooks.
enum BuiltinPluginRuntimeKind {
  /// Compiled into the app as Dart code (`BuiltinPluginCatalog.firstBatch`).
  builtinDart,

  /// Loaded at runtime from an external JSON workflow manifest
  /// (Gateway/Bridge or plugin repository — plan §8.2).
  manifest,

  /// Bridged over `dart:ffi` from a native library with a C ABI, the porting
  /// path for plugins written in Rust / C / C++ / Go / Zig. Contract (to be
  /// implemented in a later batch):
  ///
  /// - `xwm_plugin_abi_version() -> int32`
  /// - `xwm_plugin_manifest() -> const char*` — UTF-8 workflow JSON
  ///   (`BuiltinPluginWorkflow` schema)
  /// - `xwm_plugin_step_run(const char* step_id, const char* context_json)
  ///   -> const char*` — optional local step handler, JSON result
  nativeFfi,

  /// Bridged to an external process speaking JSON over stdio, the porting
  /// path for plugins written in Python / Node.js and other VM languages.
  sidecarProcess,
}

/// How a plugin binds to its runtime. Scaffold for plan §8.4 — only
/// [BuiltinPluginRuntimeKind.builtinDart] is active today; the other kinds
/// carry enough metadata (library / command, integrity hash, version) for the
/// loader batches to build on without another schema change.
@immutable
class BuiltinPluginRuntimeBinding {
  const BuiltinPluginRuntimeBinding({
    required this.kind,
    this.libraryPath = '',
    this.entrySymbolPrefix = 'xwm_plugin',
    this.command = '',
    this.args = const <String>[],
    this.version = '',
    this.sha256 = '',
  });

  /// The binding every compiled-in plugin uses.
  static const BuiltinPluginRuntimeBinding builtinDart =
      BuiltinPluginRuntimeBinding(kind: BuiltinPluginRuntimeKind.builtinDart);

  final BuiltinPluginRuntimeKind kind;

  /// Dynamic library path for [BuiltinPluginRuntimeKind.nativeFfi]
  /// (`.dylib` / `.so` / `.dll`).
  final String libraryPath;

  /// C symbol prefix for the FFI contract functions.
  final String entrySymbolPrefix;

  /// Executable for [BuiltinPluginRuntimeKind.sidecarProcess].
  final String command;
  final List<String> args;

  /// Plugin version, independent of the app release (plan §8.2 decoupling).
  final String version;

  /// Integrity hash of the library/manifest, verified before loading.
  final String sha256;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        if (libraryPath.isNotEmpty) 'libraryPath': libraryPath,
        if (entrySymbolPrefix != 'xwm_plugin')
          'entrySymbolPrefix': entrySymbolPrefix,
        if (command.isNotEmpty) 'command': command,
        if (args.isNotEmpty) 'args': args,
        if (version.isNotEmpty) 'version': version,
        if (sha256.isNotEmpty) 'sha256': sha256,
      };

  factory BuiltinPluginRuntimeBinding.fromJson(Map<String, dynamic> json) {
    final rawKind = (json['kind'] as String?)?.trim() ?? '';
    final kind = BuiltinPluginRuntimeKind.values
            .where((value) => value.name == rawKind)
            .firstOrNull ??
        BuiltinPluginRuntimeKind.builtinDart;
    return BuiltinPluginRuntimeBinding(
      kind: kind,
      libraryPath: json['libraryPath'] as String? ?? '',
      entrySymbolPrefix:
          json['entrySymbolPrefix'] as String? ?? 'xwm_plugin',
      command: json['command'] as String? ?? '',
      args: json['args'] is List
          ? (json['args'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
          : const <String>[],
      version: json['version'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
    );
  }
}
