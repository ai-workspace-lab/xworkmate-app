import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'codex_config_bridge.dart';
import 'codex_runtime.dart';
import 'gateway_runtime.dart';
import 'mode_switcher.dart';
import 'runtime_models.dart';

/// Coordination state for the runtime.
enum CoordinatorState {
  disconnected,
  connecting,
  connected,
  ready,
  error,
}

/// Code agent runtime mode for Codex integration.
///
/// - [builtIn]: XWorkmate internal runtime path (no external codex process).
/// - [externalCli]: Launch external `codex` executable via stdio bridge.
enum CodeAgentRuntimeMode {
  builtIn,
  externalCli,
}

/// Descriptor for additional external Code Agent CLI integrations.
class ExternalCodeAgentProvider {
  const ExternalCodeAgentProvider({
    required this.id,
    required this.name,
    required this.command,
    this.defaultArgs = const <String>[],
    this.capabilities = const <String>[],
  });

  final String id;
  final String name;
  final String command;
  final List<String> defaultArgs;
  final List<String> capabilities;
}

/// Unified runtime coordinator for managing Gateway and Code Agent runtime.
///
/// This class coordinates:
/// - GatewayRuntime: Connection to OpenClaw Gateway
/// - CodexRuntime: Code agent runtime (external CLI or built-in runtime mode)
/// - ModeSwitcher: Local/Remote/Offline mode switching
/// - Extensible external code-agent provider descriptors for future CLIs
class RuntimeCoordinator extends ChangeNotifier {
  final GatewayRuntime gateway;
  final CodexRuntime codex;
  final CodexConfigBridge configBridge;
  final ModeSwitcher modeSwitcher;

  final Map<String, ExternalCodeAgentProvider> _externalCodeAgents =
      <String, ExternalCodeAgentProvider>{};

  CoordinatorState _state = CoordinatorState.disconnected;
  String? _lastError;
  String? _codexPath;
  String? _cwd;
  CodeAgentRuntimeMode _runtimeMode = CodeAgentRuntimeMode.externalCli;

  CoordinatorState get state => _state;
  String? get lastError => _lastError;
  bool get isReady => _state == CoordinatorState.ready;

  /// Current code-agent runtime mode.
  CodeAgentRuntimeMode get runtimeMode => _runtimeMode;

  /// Current gateway mode.
  GatewayMode get currentMode => modeSwitcher.currentMode;

  /// Current capabilities based on mode.
  ModeCapabilities get capabilities => modeSwitcher.capabilities;

  /// Whether cloud memory is available.
  bool get hasCloudMemory => modeSwitcher.capabilities.hasCloudMemory;

  /// Whether task queue is available.
  bool get hasTaskQueue => modeSwitcher.capabilities.hasTaskQueue;

  /// Registered external code agent providers (future extension point).
  List<ExternalCodeAgentProvider> get externalCodeAgents =>
      List<ExternalCodeAgentProvider>.unmodifiable(_externalCodeAgents.values);

  RuntimeCoordinator({
    required this.gateway,
    required this.codex,
    CodexConfigBridge? configBridge,
    ModeSwitcher? modeSwitcher,
  })  : configBridge = configBridge ?? CodexConfigBridge(),
        modeSwitcher = modeSwitcher ?? ModeSwitcher(gateway);

  /// Register an external Code Agent CLI provider descriptor.
  ///
  /// This reserves integration slots for additional CLI-based agents while
  /// keeping invocation, capability discovery, and scheduling metadata unified.
  void registerExternalCodeAgent(ExternalCodeAgentProvider provider) {
    final normalizedId = provider.id.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(provider.id, 'provider.id', 'Cannot be empty');
    }

    _externalCodeAgents[normalizedId] = ExternalCodeAgentProvider(
      id: normalizedId,
      name: provider.name,
      command: provider.command,
      defaultArgs: provider.defaultArgs,
      capabilities: provider.capabilities,
    );
    notifyListeners();
  }

  /// Remove an external Code Agent CLI provider descriptor.
  bool unregisterExternalCodeAgent(String providerId) {
    final removed = _externalCodeAgents.remove(providerId.trim()) != null;
    if (removed) {
      notifyListeners();
    }
    return removed;
  }

  /// Check whether an external provider is known.
  bool hasExternalCodeAgent(String providerId) {
    return _externalCodeAgents.containsKey(providerId.trim());
  }

  /// Initialize the coordinator with Gateway profile and Codex.
  Future<void> initialize({
    GatewayConnectionProfile? profile,
    String? codexPath,
    String? workingDirectory,
    GatewayMode preferredMode = GatewayMode.remote,
    CodeAgentRuntimeMode runtimeMode = CodeAgentRuntimeMode.externalCli,
  }) async {
    _state = CoordinatorState.connecting;
    _runtimeMode = runtimeMode;
    _codexPath = codexPath;
    _cwd = workingDirectory ?? Directory.current.path;
    _lastError = null;
    notifyListeners();

    try {
      // Step 1: Connect to Gateway based on preferred mode
      final result = await _switchMode(preferredMode);

      if (!result.success) {
        throw StateError('Failed to connect: ${result.error}');
      }

      // Step 2: Start code-agent runtime according to selected mode.
      if (preferredMode != GatewayMode.offline) {
        await _ensureCodeAgentRuntime();
      }

      _state = CoordinatorState.ready;
      notifyListeners();
    } catch (e) {
      _state = CoordinatorState.error;
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Initialize with auto mode selection.
  Future<void> initializeAuto({
    String? codexPath,
    String? workingDirectory,
    bool preferRemote = true,
    CodeAgentRuntimeMode runtimeMode = CodeAgentRuntimeMode.externalCli,
  }) async {
    _state = CoordinatorState.connecting;
    _runtimeMode = runtimeMode;
    _codexPath = codexPath;
    _cwd = workingDirectory ?? Directory.current.path;
    _lastError = null;
    notifyListeners();

    try {
      // Auto-select best available mode
      final result = await modeSwitcher.autoSelect(preferRemote: preferRemote);

      if (!result.success) {
        throw StateError('No available connection mode: ${result.error}');
      }

      if (result.mode != GatewayMode.offline) {
        await _ensureCodeAgentRuntime();
      }

      _state = CoordinatorState.ready;
      notifyListeners();
    } catch (e) {
      _state = CoordinatorState.error;
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Configure Codex to use AI Gateway.
  Future<void> configureCodexForGateway({
    required String gatewayUrl,
    required String apiKey,
  }) async {
    await configBridge.configureForGateway(
      gatewayUrl: gatewayUrl,
      apiKey: apiKey,
    );
  }

  /// Switch to a different mode.
  Future<void> switchMode(GatewayMode newMode) async {
    final result = await _switchMode(newMode);

    if (!result.success) {
      throw StateError('Failed to switch mode: ${result.error}');
    }

    notifyListeners();
  }

  /// Check if current mode supports a capability.
  bool supportsCapability(String capability) {
    switch (capability) {
      case 'cloud-memory':
        return capabilities.hasCloudMemory;
      case 'task-queue':
        return capabilities.hasTaskQueue;
      case 'multi-agent':
        return capabilities.hasMultiAgent;
      case 'local-models':
        return capabilities.hasLocalModels;
      case 'code-agent':
        return capabilities.hasCodeAgent;
      default:
        return false;
    }
  }

  /// Get available modes based on current state.
  List<GatewayMode> getAvailableModes() {
    final modes = <GatewayMode>[];

    // Always can try local mode
    modes.add(GatewayMode.local);

    // Remote mode requires network
    modes.add(GatewayMode.remote);

    // Offline mode is always available
    modes.add(GatewayMode.offline);

    return modes;
  }

  /// Get available capabilities description.
  String get capabilitiesDescription {
    final caps = <String>[];
    if (capabilities.hasCloudMemory) caps.add('Cloud Memory');
    if (capabilities.hasTaskQueue) caps.add('Task Queue');
    if (capabilities.hasMultiAgent) caps.add('Multi-Agent');
    if (capabilities.hasLocalModels) caps.add('Local Models');
    if (capabilities.hasCodeAgent) caps.add('Code Agent');
    return caps.isEmpty ? 'None' : caps.join(', ');
  }

  /// Shutdown all runtimes.
  Future<void> shutdown() async {
    _state = CoordinatorState.disconnected;
    notifyListeners();

    await Future.wait([
      codex.stop(),
      gateway.disconnect(),
    ]);
  }

  Future<ModeSwitchResult> _switchMode(GatewayMode mode) {
    switch (mode) {
      case GatewayMode.local:
        return modeSwitcher.switchToLocal();
      case GatewayMode.remote:
        return modeSwitcher.switchToRemote();
      case GatewayMode.offline:
        return modeSwitcher.switchToOffline();
    }
  }

  Future<void> _ensureCodeAgentRuntime() async {
    if (_runtimeMode == CodeAgentRuntimeMode.builtIn) {
      // Built-in mode: runtime is assumed internal, no external process needed.
      return;
    }

    final resolvedCodexPath = _codexPath ?? await codex.findCodexBinary();
    if (resolvedCodexPath == null) {
      // Fall back to offline mode if external Codex CLI is unavailable.
      await modeSwitcher.switchToOffline();
      return;
    }

    try {
      await codex.startStdio(
        codexPath: resolvedCodexPath,
        cwd: _cwd,
      );
    } catch (_) {
      // Continue without external code agent in offline mode.
      await modeSwitcher.switchToOffline();
    }
  }

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }
}
