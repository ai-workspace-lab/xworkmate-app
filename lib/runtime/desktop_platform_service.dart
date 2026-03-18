import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'runtime_models.dart';

abstract class DesktopPlatformService {
  DesktopIntegrationState get state;

  bool get isSupported => state.isSupported;

  Future<void> initialize(LinuxDesktopConfig config);

  Future<void> syncConfig(LinuxDesktopConfig config);

  Future<void> refresh();

  Future<void> setMode(VpnMode mode);

  Future<void> connectTunnel();

  Future<void> disconnectTunnel();

  Future<void> setLaunchAtLogin(bool enabled);

  void dispose() {}
}

DesktopPlatformService createDesktopPlatformService() {
  if (Platform.isLinux) {
    return MethodChannelDesktopPlatformService();
  }
  return UnsupportedDesktopPlatformService();
}

class UnsupportedDesktopPlatformService implements DesktopPlatformService {
  DesktopIntegrationState _state = DesktopIntegrationState.unsupported();

  @override
  DesktopIntegrationState get state => _state;

  @override
  bool get isSupported => state.isSupported;

  @override
  Future<void> initialize(LinuxDesktopConfig config) async {
    _state = DesktopIntegrationState.unsupported();
  }

  @override
  Future<void> syncConfig(LinuxDesktopConfig config) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> setMode(VpnMode mode) async {}

  @override
  Future<void> connectTunnel() async {}

  @override
  Future<void> disconnectTunnel() async {}

  @override
  Future<void> setLaunchAtLogin(bool enabled) async {}

  @override
  void dispose() {}
}

class MethodChannelDesktopPlatformService implements DesktopPlatformService {
  static const MethodChannel _channel = MethodChannel(
    'plus.svc.xworkmate/desktop_platform',
  );

  DesktopIntegrationState _state = DesktopIntegrationState.loading();
  LinuxDesktopConfig _config = LinuxDesktopConfig.defaults();

  @override
  DesktopIntegrationState get state => _state;

  @override
  bool get isSupported => state.isSupported;

  @override
  Future<void> initialize(LinuxDesktopConfig config) async {
    _config = config;
    await _invokeVoid('configure', _encodeConfig(config));
    await refresh();
  }

  @override
  Future<void> syncConfig(LinuxDesktopConfig config) async {
    _config = config;
    await _invokeVoid('configure', _encodeConfig(config));
    await refresh();
  }

  @override
  Future<void> refresh() async {
    final payload = await _channel.invokeMethod<String>('getState');
    _state = DesktopIntegrationState.fromJson(
      _decodeJsonMap(payload),
      fallbackConfig: _config,
    );
  }

  @override
  Future<void> setMode(VpnMode mode) async {
    await _invokeVoid('setMode', mode.name);
    await refresh();
  }

  @override
  Future<void> connectTunnel() async {
    await _invokeVoid('connectTunnel');
    await refresh();
  }

  @override
  Future<void> disconnectTunnel() async {
    await _invokeVoid('disconnectTunnel');
    await refresh();
  }

  @override
  Future<void> setLaunchAtLogin(bool enabled) async {
    await _invokeVoid('setAutostart', enabled);
    await refresh();
  }

  @override
  void dispose() {}

  Future<void> _invokeVoid(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      _state = DesktopIntegrationState.unsupported(
        config: _config,
        message: 'Desktop integration channel unavailable',
      );
    } on PlatformException catch (error) {
      _state = _state.copyWith(statusMessage: error.message ?? error.code);
      rethrow;
    }
  }

  String _encodeConfig(LinuxDesktopConfig config) {
    return jsonEncode(config.toJson());
  }

  Map<String, dynamic> _decodeJsonMap(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }
}
