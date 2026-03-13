import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'gateway_runtime.dart';
import 'runtime_models.dart';
import 'codex_runtime.dart';
import 'codex_config_bridge.dart';
import 'mode_switcher.dart';

/// Coordination state for the runtime.
enum CoordinatorState {
  disconnected,
  connecting,
  connected,
  ready,
  error,
}

/// Unified runtime coordinator for managing Gateway and Codex.
/// 
/// This class coordinates:
/// - GatewayRuntime: Connection to OpenClaw Gateway
/// - CodexRuntime: Local Codex CLI process
/// - ModeSwitcher: Local/Remote/Offline mode switching
/// - Agent communication and message routing
class RuntimeCoordinator extends ChangeNotifier {
  final GatewayRuntime gateway;
  final CodexRuntime codex;
  final CodexConfigBridge configBridge;
  final ModeSwitcher modeSwitcher;

  CoordinatorState _state = CoordinatorState.disconnected;
  String? _lastError;
  String? _codexPath;
  String? _cwd;

  CoordinatorState get state => _state;
  String? get lastError => _lastError;
  bool get isReady => _state == CoordinatorState.ready;
  
  /// Current gateway mode.
  GatewayMode get currentMode => modeSwitcher.currentMode;
  
  /// Current capabilities based on mode.
  ModeCapabilities get capabilities => modeSwitcher.capabilities;
  
  /// Whether cloud memory is available.
  bool get hasCloudMemory => modeSwitcher.capabilities.hasCloudMemory;
  
  /// Whether task queue is available.
  bool get hasTaskQueue => modeSwitcher.capabilities.hasTaskQueue;

  RuntimeCoordinator({
    required this.gateway,
    required this.codex,
    CodexConfigBridge? configBridge,
    ModeSwitcher? modeSwitcher,
  }) : configBridge = configBridge ?? CodexConfigBridge(),
        modeSwitcher = modeSwitcher ?? ModeSwitcher(gateway);

  /// Initialize the coordinator with Gateway profile and Codex.
  Future<void> initialize({
    GatewayConnectionProfile? profile,
    String? codexPath,
    String? workingDirectory,
    GatewayMode preferredMode = GatewayMode.remote,
  }) async {
    _state = CoordinatorState.connecting;
    _codexPath = codexPath;
    _cwd = workingDirectory ?? Directory.current.path;
    _lastError = null;
    notifyListeners();

    try {
      // Step 1: Connect to Gateway based on preferred mode
      ModeSwitchResult result;
      
      switch (preferredMode) {
        case GatewayMode.local:
          result = await modeSwitcher.switchToLocal();
          break;
        case GatewayMode.remote:
          result = await modeSwitcher.switchToRemote();
          break;
        case GatewayMode.offline:
          result = await modeSwitcher.switchToOffline();
          break;
      }

      if (!result.success) {
        throw StateError('Failed to connect: ${result.error}');
      }

      // Step 2: Find and start Codex (if not in offline mode)
      if (preferredMode != GatewayMode.offline) {
        final resolvedCodexPath = codexPath ?? await codex.findCodexBinary();
        if (resolvedCodexPath == null) {
          // Fall back to offline mode if Codex not found
          await modeSwitcher.switchToOffline();
        } else {
          try {
            await codex.startStdio(
              codexPath: resolvedCodexPath,
              cwd: _cwd,
            );
          } catch (e) {
            // Continue without Codex in offline mode
            await modeSwitcher.switchToOffline();
          }
        }
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
  }) async {
    _state = CoordinatorState.connecting;
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

      // Start Codex if available
      if (result.mode != GatewayMode.offline) {
        final resolvedCodexPath = codexPath ?? await codex.findCodexBinary();
        if (resolvedCodexPath != null) {
          try {
            await codex.startStdio(
              codexPath: resolvedCodexPath,
              cwd: _cwd,
            );
          } catch (e) {
            // Continue in offline mode
            await modeSwitcher.switchToOffline();
          }
        }
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
    ModeSwitchResult result;

    switch (newMode) {
      case GatewayMode.local:
        result = await modeSwitcher.switchToLocal();
        break;
      case GatewayMode.remote:
        result = await modeSwitcher.switchToRemote();
        break;
      case GatewayMode.offline:
        result = await modeSwitcher.switchToOffline();
        break;
    }

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

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }
}
