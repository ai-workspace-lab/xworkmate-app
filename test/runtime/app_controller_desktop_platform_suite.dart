@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/desktop_platform_service.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

import '../test_support.dart';

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

class _ThrowingSecureConfigStore extends SecureConfigStore {
  _ThrowingSecureConfigStore(
    String rootPath, {
    this.identity,
    this.operatorDeviceToken,
  }) : super(
         enableSecureStorage: false,
         databasePathResolver: () async => '$rootPath/settings.sqlite3',
         fallbackDirectoryPathResolver: () async => rootPath,
         defaultSupportDirectoryPathResolver: () async => rootPath,
       );

  LocalDeviceIdentity? identity;
  String? operatorDeviceToken;

  @override
  Future<String?> loadGatewayToken({int? profileIndex}) async {
    throw StateError('main store gateway token should not be used');
  }

  @override
  Future<String?> loadGatewayPassword({int? profileIndex}) async {
    throw StateError('main store gateway password should not be used');
  }

  @override
  Future<LocalDeviceIdentity?> loadDeviceIdentity() async {
    return identity;
  }

  @override
  Future<void> saveDeviceIdentity(LocalDeviceIdentity identity) async {
    this.identity = identity;
  }

  @override
  Future<String?> loadDeviceToken({
    required String deviceId,
    required String role,
  }) async {
    if (identity?.deviceId == deviceId && role == 'operator') {
      return operatorDeviceToken;
    }
    return null;
  }

  @override
  Future<void> saveDeviceToken({
    required String deviceId,
    required String role,
    required String token,
  }) async {
    if (identity?.deviceId == deviceId && role == 'operator') {
      operatorDeviceToken = token;
    }
  }
}

class _FakeGatewayTestServer {
  _FakeGatewayTestServer._(this._server);

  final HttpServer _server;
  String? lastConnectDeviceId;
  String? lastAuthDeviceToken;

  int get port => _server.port;

  static Future<_FakeGatewayTestServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeGatewayTestServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(
        jsonEncode(<String, dynamic>{
          'type': 'event',
          'event': 'connect.challenge',
          'payload': <String, dynamic>{'nonce': 'nonce-1'},
        }),
      );
      await for (final raw in socket) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        if (frame['type'] != 'req') {
          continue;
        }
        final id = frame['id'] as String? ?? 'req-id';
        final method = frame['method'] as String? ?? '';
        switch (method) {
          case 'connect':
            final payload =
                frame['params'] as Map<String, dynamic>? ?? const {};
            final device =
                payload['device'] as Map<String, dynamic>? ?? const {};
            final auth = payload['auth'] as Map<String, dynamic>? ?? const {};
            lastConnectDeviceId = device['id']?.toString();
            lastAuthDeviceToken = auth['deviceToken']?.toString();
            socket.add(
              jsonEncode(<String, dynamic>{
                'type': 'res',
                'id': id,
                'ok': true,
                'payload': <String, dynamic>{
                  'server': <String, dynamic>{'host': '127.0.0.1'},
                  'snapshot': <String, dynamic>{
                    'sessionDefaults': <String, dynamic>{
                      'mainSessionKey': 'main',
                    },
                  },
                  'auth': <String, dynamic>{
                    'role': 'operator',
                    'scopes': const <String>['operator.admin'],
                  },
                },
              }),
            );
            break;
          case 'health':
            socket.add(
              jsonEncode(<String, dynamic>{
                'type': 'res',
                'id': id,
                'ok': true,
                'payload': <String, dynamic>{'status': 'ok'},
              }),
            );
            break;
          default:
            socket.add(
              jsonEncode(<String, dynamic>{
                'type': 'res',
                'id': id,
                'ok': true,
                'payload': const <String, dynamic>{},
              }),
            );
        }
      }
    }
  }
}

void main() {
  test(
    'AppController syncs Linux desktop settings into platform service',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = _FakeDesktopPlatformService();
      final controller = AppController(
        store: createIsolatedTestStore(enableSecureStorage: false),
        desktopPlatformService: service,
      );
      addTearDown(controller.dispose);

      await _waitFor(() => !controller.initializing);

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

  test(
    'AppController tests gateway connectivity with the persisted device identity',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final server = await _FakeGatewayTestServer.start();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-desktop-platform-tests-',
      );
      final identitySeedStore = createIsolatedTestStore(
        enableSecureStorage: false,
      );
      final identity = await DeviceIdentityStore(
        identitySeedStore,
      ).loadOrCreate();
      final controller = AppController(
        store: _ThrowingSecureConfigStore(
          tempDirectory.path,
          identity: identity,
          operatorDeviceToken: 'paired-device-token',
        ),
      );
      addTearDown(server.close);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      await _waitFor(() => !controller.initializing);

      final result = await controller.testGatewayConnectionDraft(
        profile: GatewayConnectionProfile.defaults().copyWith(
          mode: RuntimeConnectionMode.local,
          host: '127.0.0.1',
          port: server.port,
          tls: false,
          useSetupCode: false,
        ),
        executionTarget: AssistantExecutionTarget.local,
      );

      expect(result.state, 'success');
      expect(result.endpoint, '127.0.0.1:${server.port}');
      expect(result.message, isNot(contains('main store')));
      expect(server.lastConnectDeviceId, identity.deviceId);
      expect(server.lastAuthDeviceToken, 'paired-device-token');
    },
  );
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('Condition not met within ${timeout.inMilliseconds}ms');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
