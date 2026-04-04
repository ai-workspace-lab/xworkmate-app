// OpenClaw Gateway mode switching logic.
//
// Handles transitions between:
// - Local mode (127.0.0.1:18789): Full functionality, no cloud memory
// - Remote mode (wss://openclaw.svc.plus): Full functionality with cloud memory
// - Offline mode: Local Codex only, limited functionality

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gateway_runtime.dart';
import 'runtime_models.dart';

/// Gateway operating mode.
enum GatewayMode {
  /// Local mode: Gateway running locally at 127.0.0.1:18789
  local,

  /// Remote mode: Gateway connected to cloud at wss://openclaw.svc.plus
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

  /// Connected in local mode
  connectedLocal,

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

  /// Local mode capabilities.
  static const ModeCapabilities local = ModeCapabilities(
    hasCloudMemory: false,
    hasTaskQueue: false,
    hasMultiAgent: false,
    hasLocalModels: true,
    hasCodeAgent: true,
  );

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

/// Manages mode switching between local, remote, and offline modes.
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

  /// Switch to local mode.
  Future<ModeSwitchResult> switchToLocal({
    String host = '127.0.0.1',
    int port = 18789,
    String? token,
  }) async {
    if (_state == ModeSwitcherState.connectedLocal) {
      return ModeSwitchResult(success: true, mode: GatewayMode.local);
    }

    _state = ModeSwitcherState.connecting;
    _lastError = null;
    notifyListeners();

    try {
      final profile = GatewayConnectionProfile.defaultsLocal().copyWith(
        host: host,
        port: port,
        tls: false,
      );

      await _gateway.connectProfile(profile, authTokenOverride: token ?? '');

      // Wait for connection
      await _gateway.events
          .where(
            (e) => e.event == 'gateway/ready' || e.event == 'gateway/connected',
          )
          .first
          .timeout(const Duration(seconds: 30));

      _state = ModeSwitcherState.connectedLocal;
      _currentMode = GatewayMode.local;
      _capabilities = ModeCapabilities.local;
      _lastModeChange = DateTime.now();
      notifyListeners();

      return ModeSwitchResult(
        success: true,
        mode: GatewayMode.local,
        capabilities: _capabilities.toMap(),
      );
    } catch (e) {
      _state = ModeSwitcherState.error;
      _lastError = e.toString();
      notifyListeners();

      return ModeSwitchResult(
        success: false,
        mode: GatewayMode.local,
        error: e.toString(),
      );
    }
  }

  /// Switch to remote mode.
  Future<ModeSwitchResult> switchToRemote({
    String host = 'openclaw.svc.plus',
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
      final profile = GatewayConnectionProfile.defaultsRemote().copyWith(
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

  /// Auto-select best available mode.
  Future<ModeSwitchResult> autoSelect({
    String? localToken,
    String? remoteToken,
    bool preferRemote = true,
  }) async {
    // Try remote first if preferred
    if (preferRemote) {
      final remoteResult = await switchToRemote(token: remoteToken);
      if (remoteResult.success) {
        return remoteResult;
      }
    }

    // Try local
    final localResult = await switchToLocal(token: localToken);
    if (localResult.success) {
      return localResult;
    }

    // Fall back to offline
    return switchToOffline();
  }

  /// Get current state description.
  String get stateDescription {
    switch (_state) {
      case ModeSwitcherState.disconnected:
        return 'Disconnected';
      case ModeSwitcherState.connecting:
        return 'Connecting...';
      case ModeSwitcherState.connectedLocal:
        return 'Connected (Local)';
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
      case GatewayMode.local:
        return 'Local Mode (127.0.0.1:18789)';
      case GatewayMode.remote:
        return 'Remote Mode (wss://openclaw.svc.plus)';
      case GatewayMode.offline:
        return 'Offline Mode (Local Codex Only)';
    }
  }
}
