// Gateway mode switching logic for remote bridge mode and offline mode.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gateway_runtime.dart';
import 'runtime_models.dart';

/// Gateway operating mode.
enum GatewayMode {
  /// Remote mode: Gateway connected through the configured bridge endpoint
  remote,

  /// Offline mode: No gateway connection, local Codex only
  offline,
}

/// Mode switcher state.
enum ModeSwitcherState {
  /// No connection established
  disconnected,

  /// Attempting to connect
  connecting,

  /// Connected in remote mode
  connectedRemote,

  /// Operating in offline mode
  offline,

  /// Connection error
  error,
}

/// Mode switching result.
class ModeSwitchResult {
  final bool success;
  final GatewayMode mode;
  final String? error;
  final Map<String, dynamic>? capabilities;

  const ModeSwitchResult({
    required this.success,
    required this.mode,
    this.error,
    this.capabilities,
  });
}

/// Capabilities available in each mode.
class ModeCapabilities {
  final bool hasCloudMemory;
  final bool hasTaskQueue;
  final bool hasMultiAgent;
  final bool hasLocalModels;
  final bool hasCodeAgent;

  const ModeCapabilities({
    required this.hasCloudMemory,
    required this.hasTaskQueue,
    required this.hasMultiAgent,
    required this.hasLocalModels,
    required this.hasCodeAgent,
  });

  /// Remote mode capabilities.
  static const ModeCapabilities remote = ModeCapabilities(
    hasCloudMemory: true,
    hasTaskQueue: true,
    hasMultiAgent: true,
    hasLocalModels: true,
    hasCodeAgent: true,
  );

  /// Offline mode capabilities.
  static const ModeCapabilities offline = ModeCapabilities(
    hasCloudMemory: false,
    hasTaskQueue: false,
    hasMultiAgent: false,
    hasLocalModels: false,
    hasCodeAgent: true,
  );

  Map<String, bool> toMap() => {
    'hasCloudMemory': hasCloudMemory,
    'hasTaskQueue': hasTaskQueue,
    'hasMultiAgent': hasMultiAgent,
    'hasLocalModels': hasLocalModels,
    'hasCodeAgent': hasCodeAgent,
  };
}

/// Manages mode switching between remote and offline modes.
class ModeSwitcher extends ChangeNotifier {
  final GatewayRuntime _gateway;

  ModeSwitcherState _state = ModeSwitcherState.disconnected;
  GatewayMode _currentMode = GatewayMode.offline;
  String? _lastError;
  ModeCapabilities _capabilities = ModeCapabilities.offline;
  DateTime? _lastModeChange;

  ModeSwitcherState get state => _state;
  GatewayMode get currentMode => _currentMode;
  String? get lastError => _lastError;
  ModeCapabilities get capabilities => _capabilities;
  DateTime? get lastModeChange => _lastModeChange;

  ModeSwitcher(this._gateway);

  /// Switch to remote mode.
  Future<ModeSwitchResult> switchToRemote({
    String host = '',
    int port = 443,
    bool tls = true,
    String? token,
  }) async {
    if (_state == ModeSwitcherState.connectedRemote) {
      return ModeSwitchResult(success: true, mode: GatewayMode.remote);
    }

    _state = ModeSwitcherState.connecting;
    _lastError = null;
    notifyListeners();

    try {
      final profile = GatewayConnectionProfile.defaults().copyWith(
        mode: RuntimeConnectionMode.remote,
        host: host,
        port: port,
        tls: tls,
      );

      await _gateway.connectProfile(profile, authTokenOverride: token ?? '');

      // Wait for connection
      await _gateway.events
          .where(
            (e) => e.event == 'gateway/ready' || e.event == 'gateway/connected',
          )
          .first
          .timeout(const Duration(seconds: 30));

      _state = ModeSwitcherState.connectedRemote;
      _currentMode = GatewayMode.remote;
      _capabilities = ModeCapabilities.remote;
      _lastModeChange = DateTime.now();
      notifyListeners();

      return ModeSwitchResult(
        success: true,
        mode: GatewayMode.remote,
        capabilities: _capabilities.toMap(),
      );
    } catch (e) {
      _state = ModeSwitcherState.error;
      _lastError = e.toString();
      notifyListeners();

      return ModeSwitchResult(
        success: false,
        mode: GatewayMode.remote,
        error: e.toString(),
      );
    }
  }

  /// Switch to offline mode (local Codex only).
  Future<ModeSwitchResult> switchToOffline() async {
    if (_state == ModeSwitcherState.offline) {
      return ModeSwitchResult(success: true, mode: GatewayMode.offline);
    }

    try {
      // Disconnect gateway if connected
      if (_gateway.isConnected) {
        await _gateway.disconnect();
      }

      _state = ModeSwitcherState.offline;
      _currentMode = GatewayMode.offline;
      _capabilities = ModeCapabilities.offline;
      _lastModeChange = DateTime.now();
      notifyListeners();

      return ModeSwitchResult(
        success: true,
        mode: GatewayMode.offline,
        capabilities: _capabilities.toMap(),
      );
    } catch (e) {
      _state = ModeSwitcherState.error;
      _lastError = e.toString();
      notifyListeners();

      return ModeSwitchResult(
        success: false,
        mode: GatewayMode.offline,
        error: e.toString(),
      );
    }
  }

  /// Get current state description.
  String get stateDescription {
    switch (_state) {
      case ModeSwitcherState.disconnected:
        return 'Disconnected';
      case ModeSwitcherState.connecting:
        return 'Connecting...';
      case ModeSwitcherState.connectedRemote:
        return 'Connected (Remote)';
      case ModeSwitcherState.offline:
        return 'Offline';
      case ModeSwitcherState.error:
        return 'Error';
    }
  }

  /// Get current mode description.
  String get modeDescription {
    switch (_currentMode) {
      case GatewayMode.remote:
        return 'Remote Mode (Configured bridge endpoint)';
      case GatewayMode.offline:
        return 'Offline Mode (Local Codex Only)';
    }
  }
}
