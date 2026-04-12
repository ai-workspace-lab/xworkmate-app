import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'codex_config_bridge.dart';
import 'codex_runtime.dart';
import 'gateway_runtime.dart';
import 'mode_switcher.dart';
import 'runtime_dispatch_resolver.dart';
import 'runtime_external_code_agents.dart';
import 'runtime_models.dart';

export 'runtime_external_code_agents.dart';

/// Coordination state for the runtime.
enum CoordinatorState { disconnected, connecting, connected, ready, error }

/// Unified runtime coordinator for managing Gateway and Code Agent runtime.
///
/// This class coordinates:
/// - GatewayRuntime: Connection to OpenClaw Gateway
/// - CodexRuntime: Code agent runtime (external CLI or built-in runtime mode)
/// - ModeSwitcher: Remote/Offline mode switching
/// - Extensible external code-agent provider descriptors for future CLIs
class RuntimeCoordinator extends ChangeNotifier {
  final GatewayRuntime gateway;
  final CodexRuntime codex;
  final CodexConfigBridge configBridge;
  final ModeSwitcher modeSwitcher;

  final Map<String, ExternalCodeAgentProvider> _externalCodeAgents =
      <String, ExternalCodeAgentProvider>{};
  RuntimeDispatchResolver? _dispatchResolver;

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
  String? get codeAgentPath => _codexPath;

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
    RuntimeDispatchResolver? dispatchResolver,
  }) : configBridge = configBridge ?? CodexConfigBridge(),
       modeSwitcher = modeSwitcher ?? ModeSwitcher(gateway),
       _dispatchResolver = dispatchResolver;

  /// Register an external Code Agent CLI provider descriptor.
  ///
  /// This reserves integration slots for additional CLI-based agents while
  /// keeping invocation, capability discovery, and scheduling metadata unified.
  void registerExternalCodeAgent(ExternalCodeAgentProvider provider) {
    final normalizedId = provider.id.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(provider.id, 'provider.id', 'Cannot be empty');
    }
    final normalizedCommand = provider.command.trim();
    if (normalizedCommand.isEmpty) {
      throw ArgumentError.value(
        provider.command,
        'provider.command',
        'Cannot be empty',
      );
    }
    final normalizedCapabilities = _normalizeCapabilitySet(
      provider.capabilities,
    ).toList(growable: false)..sort();

    _externalCodeAgents[normalizedId] = ExternalCodeAgentProvider(
      id: normalizedId,
      name: provider.name,
      command: normalizedCommand,
      transport: provider.transport,
      endpoint: provider.endpoint.trim(),
      defaultArgs: provider.defaultArgs,
      capabilities: normalizedCapabilities,
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

  /// Discover providers that can satisfy required capabilities.
  ///
  /// This runtime-level surface is the extension point for future capability
  /// discovery and provider scheduling.
  List<ExternalCodeAgentProvider> discoverExternalCodeAgents({
    Iterable<String> requiredCapabilities = const <String>[],
  }) {
    final required = _normalizeCapabilitySet(requiredCapabilities);
    final providers =
        _externalCodeAgents.values
            .where((provider) => _providerSupports(provider, required))
            .toList(growable: false)
          ..sort((a, b) => a.id.compareTo(b.id));
    return providers;
  }

  /// Select one provider for dispatch based on preference and capabilities.
  ///
  /// Scheduling policy is intentionally simple for phase 1:
  /// - honor preferred provider when it satisfies capability requirements
  /// - otherwise pick the first discovered provider in deterministic id order
  Future<ExternalCodeAgentProvider?> selectExternalCodeAgent({
    String? preferredProviderId,
    Iterable<String> requiredCapabilities = const <String>[],
  }) async {
    final available = externalCodeAgents;
    final resolver = _dispatchResolver;
    if (resolver != null && available.isNotEmpty) {
      final selectedProviderId = await resolver.selectProviderId(
        providers: available,
        preferredProviderId: preferredProviderId?.trim() ?? '',
        requiredCapabilities: requiredCapabilities,
      );
      if (selectedProviderId != null) {
        final selected = _externalCodeAgents[selectedProviderId];
        if (selected != null) {
          return selected;
        }
      }
    }
    return _selectExternalCodeAgentLocally(
      preferredProviderId: preferredProviderId,
      requiredCapabilities: requiredCapabilities,
    );
  }

  RuntimeDispatchResolver? get dispatchResolver => _dispatchResolver;

  void attachDispatchResolver(RuntimeDispatchResolver resolver) {
    _dispatchResolver = resolver;
  }

  ExternalCodeAgentProvider? _selectExternalCodeAgentLocally({
    String? preferredProviderId,
    Iterable<String> requiredCapabilities = const <String>[],
  }) {
    final required = _normalizeCapabilitySet(requiredCapabilities);
    final preferredId = preferredProviderId?.trim() ?? '';
    if (preferredId.isNotEmpty) {
      final preferred = _externalCodeAgents[preferredId];
      if (preferred != null && _providerSupports(preferred, required)) {
        return preferred;
      }
    }

    final discovered = discoverExternalCodeAgents(
      requiredCapabilities: required,
    );
    if (discovered.isEmpty) {
      return null;
    }
    return discovered.first;
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
      final result = preferRemote
          ? await modeSwitcher.switchToRemote()
          : await modeSwitcher.switchToOffline();

      if (!result.success) {
        throw StateError('No available connection mode: ${result.error}');
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

  /// Resolve the external Codex CLI path from explicit settings or PATH lookup.
  Future<String?> resolveCodexPath({String? codexPath}) async {
    final overridePath = codexPath?.trim() ?? '';
    if (overridePath.isNotEmpty) {
      final file = File(overridePath);
      if (await file.exists()) {
        return overridePath;
      }
      return null;
    }
    return null;
  }

  /// Start the code-agent runtime without changing the Gateway connection state.
  Future<void> startCodeAgentRuntime({
    required CodeAgentRuntimeMode runtimeMode,
    String? codexPath,
    String? workingDirectory,
  }) async {
    _runtimeMode = runtimeMode;
    _codexPath = codexPath?.trim();
    _cwd = workingDirectory ?? _cwd ?? Directory.current.path;
    _lastError = null;
    _state = CoordinatorState.ready;
    notifyListeners();
  }

  Future<void> stopCodeAgentRuntime() async {
    _state = gateway.isConnected
        ? CoordinatorState.ready
        : CoordinatorState.disconnected;
    notifyListeners();
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

    await gateway.disconnect();
  }

  Future<ModeSwitchResult> _switchMode(GatewayMode mode) {
    switch (mode) {
      case GatewayMode.remote:
        return modeSwitcher.switchToRemote();
      case GatewayMode.offline:
        return modeSwitcher.switchToOffline();
    }
  }

  static Set<String> _normalizeCapabilitySet(Iterable<String> capabilities) {
    return capabilities
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  static bool _providerSupports(
    ExternalCodeAgentProvider provider,
    Set<String> requiredCapabilities,
  ) {
    if (requiredCapabilities.isEmpty) {
      return true;
    }
    final provided = _normalizeCapabilitySet(provider.capabilities);
    return requiredCapabilities.every(provided.contains);
  }

  @override
  void dispose() {
    final resolver = _dispatchResolver;
    _dispatchResolver = null;
    if (resolver != null) {
      unawaited(resolver.dispose());
    }
    shutdown();
    super.dispose();
  }
}
