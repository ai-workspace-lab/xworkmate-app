@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/desktop_platform_service.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

class _FakeDesktopPlatformService implements DesktopPlatformService {
  _FakeDesktopPlatformService()
    : _state = DesktopIntegrationState.fromJson(const <String, dynamic>{
        'isSupported': true,
        'environment': 'gnome',
        'mode': 'proxy',
        'trayAvailable': true,
        'trayEnabled': true,
        'autostartEnabled': false,
        'networkManagerAvailable': true,
        'systemProxy': {
          'enabled': true,
          'host': '127.0.0.1',
          'port': 7890,
          'backend': 'gsettings',
          'lastAppliedMode': 'proxy',
        },
        'tunnel': {
          'available': true,
          'connected': false,
          'connectionName': 'XWorkmate Tunnel',
          'backend': 'nmcli',
          'lastError': '',
        },
        'statusMessage': '',
      });

  DesktopIntegrationState _state;
  LinuxDesktopConfig config = LinuxDesktopConfig.defaults();
  bool autostartEnabled = false;

  @override
  DesktopIntegrationState get state =>
      _state.copyWith(autostartEnabled: autostartEnabled);

  @override
  bool get isSupported => state.isSupported;

  @override
  Future<void> initialize(LinuxDesktopConfig config) async {
    this.config = config;
  }

  @override
  Future<void> syncConfig(LinuxDesktopConfig config) async {
    this.config = config;
    _state = _state.copyWith(
      mode: config.preferredMode,
      trayEnabled: config.trayEnabled,
      tunnel: _state.tunnel.copyWith(connectionName: config.vpnConnectionName),
      systemProxy: _state.systemProxy.copyWith(
        host: config.proxyHost,
        port: config.proxyPort,
      ),
    );
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> setMode(VpnMode mode) async {
    _state = _state.copyWith(
      mode: mode,
      systemProxy: _state.systemProxy.copyWith(enabled: mode == VpnMode.proxy),
    );
  }

  @override
  Future<void> connectTunnel() async {
    _state = _state.copyWith(
      mode: VpnMode.tunnel,
      tunnel: _state.tunnel.copyWith(connected: true),
      systemProxy: _state.systemProxy.copyWith(enabled: false),
    );
  }

  @override
  Future<void> disconnectTunnel() async {
    _state = _state.copyWith(tunnel: _state.tunnel.copyWith(connected: false));
  }

  @override
  Future<void> setLaunchAtLogin(bool enabled) async {
    autostartEnabled = enabled;
  }

  @override
  void dispose() {}
}

void main() {
  test(
    'AppController syncs Linux desktop settings into platform service',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = _FakeDesktopPlatformService();
      final controller = AppController(desktopPlatformService: service);
      addTearDown(controller.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.supportsDesktopIntegration, isTrue);
      expect(
        controller.desktopIntegration.environment,
        DesktopEnvironment.gnome,
      );

      await controller.saveLinuxDesktopConfig(
        controller.settings.linuxDesktop.copyWith(
          vpnConnectionName: 'Corp Tunnel',
          proxyHost: '10.0.0.2',
          proxyPort: 8080,
        ),
      );

      expect(service.config.vpnConnectionName, 'Corp Tunnel');
      expect(service.config.proxyHost, '10.0.0.2');
      expect(service.config.proxyPort, 8080);

      await controller.setDesktopVpnMode(VpnMode.tunnel);
      expect(controller.desktopIntegration.mode, VpnMode.tunnel);

      await controller.connectDesktopTunnel();
      expect(controller.desktopIntegration.tunnel.connected, isTrue);

      await controller.setLaunchAtLogin(true);
      expect(service.autostartEnabled, isTrue);
    },
  );
}
