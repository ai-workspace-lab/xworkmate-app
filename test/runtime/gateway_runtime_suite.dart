@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test(
    'GatewayRuntime uses explicit shared token override for the initial connect handshake',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SecureConfigStore();
      final runtime = GatewayRuntime(
        store: store,
        identityStore: DeviceIdentityStore(store),
      );
      final server = await _FakeGatewayRuntimeServer.start();
      addTearDown(runtime.dispose);
      addTearDown(server.close);

      await runtime.connectProfile(
        GatewayConnectionProfile.defaults().copyWith(
          mode: RuntimeConnectionMode.local,
          host: '127.0.0.1',
          port: server.port,
          tls: false,
          useSetupCode: false,
        ),
        authTokenOverride: 'shared-token-from-form',
      );

      expect(server.connectAuth?['token'], 'shared-token-from-form');
      expect(server.connectAuth?['deviceToken'], isNull);
      expect(runtime.snapshot.status, RuntimeConnectionStatus.connected);
      expect(runtime.snapshot.connectAuthMode, 'shared-token');
      expect(runtime.snapshot.connectAuthFields, const <String>['token']);
      expect(runtime.snapshot.connectAuthSources, const <String>[
        'shared:form',
      ]);
      expect(
        runtime.logs.any(
          (entry) => entry.message.contains('shared-token-from-form'),
        ),
        isFalse,
      );
      expect(
        runtime.logs.any(
          (entry) => entry.message.contains('auth: shared-token'),
        ),
        isTrue,
      );
    },
  );

  test(
    'GatewayRuntime sends stored operator device token using auth.deviceToken',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SecureConfigStore();
      final identityStore = DeviceIdentityStore(store);
      final identity = await identityStore.loadOrCreate();
      await store.saveDeviceToken(
        deviceId: identity.deviceId,
        role: 'operator',
        token: 'stored-device-token',
      );
      final runtime = GatewayRuntime(
        store: store,
        identityStore: identityStore,
      );
      final server = await _FakeGatewayRuntimeServer.start();
      addTearDown(runtime.dispose);
      addTearDown(server.close);

      await runtime.connectProfile(
        GatewayConnectionProfile.defaults().copyWith(
          mode: RuntimeConnectionMode.local,
          host: '127.0.0.1',
          port: server.port,
          tls: false,
          useSetupCode: false,
        ),
      );

      expect(server.connectAuth?['token'], 'stored-device-token');
      expect(server.connectAuth?['deviceToken'], 'stored-device-token');
      expect(runtime.snapshot.hasDeviceToken, isTrue);
      expect(runtime.snapshot.deviceId, identity.deviceId);
      expect(runtime.snapshot.connectAuthMode, 'device-token');
      expect(runtime.snapshot.connectAuthFields, const <String>[
        'token',
        'deviceToken',
      ]);
      expect(runtime.snapshot.connectAuthSources, const <String>[
        'device:store',
      ]);
    },
  );

  test(
    'GatewayRuntime parses device pairing state and syncs rotated local role tokens',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SecureConfigStore();
      final identityStore = DeviceIdentityStore(store);
      final identity = await identityStore.loadOrCreate();
      final runtime = GatewayRuntime(
        store: store,
        identityStore: identityStore,
      );
      final server = await _FakeGatewayRuntimeServer.start(
        currentDeviceId: identity.deviceId,
      );
      addTearDown(runtime.dispose);
      addTearDown(server.close);

      await runtime.connectProfile(
        GatewayConnectionProfile.defaults().copyWith(
          mode: RuntimeConnectionMode.local,
          host: '127.0.0.1',
          port: server.port,
          tls: false,
          useSetupCode: false,
        ),
        authTokenOverride: 'shared-token-from-form',
      );

      final devices = await runtime.listDevicePairing();
      expect(devices.pending.single.requestId, 'req-1');
      expect(devices.paired.single.currentDevice, isTrue);
      expect(devices.paired.single.tokens.single.role, 'operator');

      final rotated = await runtime.rotateDeviceToken(
        deviceId: identity.deviceId,
        role: 'operator',
        scopes: const <String>['operator.admin', 'operator.pairing'],
      );
      expect(rotated, 'rotated-local-device-token');
      expect(
        await store.loadDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        ),
        'rotated-local-device-token',
      );

      await runtime.revokeDeviceToken(
        deviceId: identity.deviceId,
        role: 'operator',
      );
      expect(
        await store.loadDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        ),
        isNull,
      );
    },
  );

  test(
    'GatewayRuntime does not auto reconnect after non-retryable pairing errors',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SecureConfigStore();
      final runtime = GatewayRuntime(
        store: store,
        identityStore: DeviceIdentityStore(store),
      );
      final server = await _FakeGatewayRuntimeServer.start(
        connectErrorCode: 'INVALID_REQUEST',
        connectErrorDetailCode: 'PAIRING_REQUIRED',
        connectErrorMessage: 'pairing required',
        closeAfterConnectError: true,
      );
      addTearDown(runtime.dispose);
      addTearDown(server.close);

      await expectLater(
        () => runtime.connectProfile(
          GatewayConnectionProfile.defaults().copyWith(
            mode: RuntimeConnectionMode.local,
            host: '127.0.0.1',
            port: server.port,
            tls: false,
            useSetupCode: false,
          ),
          authTokenOverride: 'shared-token-from-form',
        ),
        throwsA(isA<GatewayRuntimeException>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 2400));

      expect(server.connectRequestCount, 1);
      expect(runtime.snapshot.pairingRequired, isTrue);
      expect(
        runtime.logs.any(
          (entry) =>
              entry.category == 'socket' &&
              entry.message.contains('auto reconnect suppressed'),
        ),
        isTrue,
      );
    },
  );
}

class _FakeGatewayRuntimeServer {
  _FakeGatewayRuntimeServer._(
    this._server, {
    required this.currentDeviceId,
    required this.connectErrorCode,
    required this.connectErrorDetailCode,
    required this.connectErrorMessage,
    required this.closeAfterConnectError,
  });

  final HttpServer _server;
  final String? currentDeviceId;
  final String? connectErrorCode;
  final String? connectErrorDetailCode;
  final String? connectErrorMessage;
  final bool closeAfterConnectError;
  Map<String, dynamic>? connectAuth;
  int connectRequestCount = 0;

  int get port => _server.port;

  static Future<_FakeGatewayRuntimeServer> start({
    String? currentDeviceId,
    String? connectErrorCode,
    String? connectErrorDetailCode,
    String? connectErrorMessage,
    bool closeAfterConnectError = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeGatewayRuntimeServer._(
      server,
      currentDeviceId: currentDeviceId,
      connectErrorCode: connectErrorCode,
      connectErrorDetailCode: connectErrorDetailCode,
      connectErrorMessage: connectErrorMessage,
      closeAfterConnectError: closeAfterConnectError,
    );
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
        final method = frame['method'] as String? ?? '';
        final id = frame['id'] as String? ?? 'req-id';
        final params =
            (frame['params'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        switch (method) {
          case 'connect':
            connectRequestCount += 1;
            connectAuth =
                (params['auth'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            if (connectErrorCode != null) {
              socket.add(
                jsonEncode(<String, dynamic>{
                  'type': 'res',
                  'id': id,
                  'ok': false,
                  'error': <String, dynamic>{
                    'code': connectErrorCode,
                    'message': connectErrorMessage ?? 'connect failed',
                    'details': <String, dynamic>{
                      if (connectErrorDetailCode != null)
                        'code': connectErrorDetailCode,
                    },
                  },
                }),
              );
              if (closeAfterConnectError) {
                await socket.close(
                  WebSocketStatus.policyViolation,
                  'connect failed',
                );
              }
              break;
            }
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
                    'scopes': const <String>[
                      'operator.admin',
                      'operator.pairing',
                    ],
                  },
                },
              }),
            );
            break;
          case 'device.pair.list':
            socket.add(
              jsonEncode(<String, dynamic>{
                'type': 'res',
                'id': id,
                'ok': true,
                'payload': <String, dynamic>{
                  'pending': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'requestId': 'req-1',
                      'deviceId': 'device-pending',
                      'displayName': 'Pending Device',
                      'role': 'operator',
                      'scopes': const <String>['operator.read'],
                      'remoteIp': '10.0.0.8',
                      'ts': 1700000000000,
                    },
                  ],
                  'paired': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'deviceId': currentDeviceId ?? 'device-current',
                      'displayName': 'Current Device',
                      'roles': const <String>['operator'],
                      'scopes': const <String>[
                        'operator.admin',
                        'operator.pairing',
                      ],
                      'tokens': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'role': 'operator',
                          'scopes': const <String>[
                            'operator.admin',
                            'operator.pairing',
                          ],
                          'createdAtMs': 1700000001000,
                        },
                      ],
                    },
                  ],
                },
              }),
            );
            break;
          case 'device.token.rotate':
            socket.add(
              jsonEncode(<String, dynamic>{
                'type': 'res',
                'id': id,
                'ok': true,
                'payload': <String, dynamic>{
                  'deviceId': params['deviceId'],
                  'role': params['role'],
                  'token': 'rotated-local-device-token',
                  'scopes': params['scopes'] ?? const <String>[],
                },
              }),
            );
            break;
          case 'device.token.revoke':
            socket.add(
              jsonEncode(<String, dynamic>{
                'type': 'res',
                'id': id,
                'ok': true,
                'payload': <String, dynamic>{
                  'deviceId': params['deviceId'],
                  'role': params['role'],
                },
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
            break;
        }
      }
    }
  }
}
