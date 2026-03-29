@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/gateway_runtime_session_client.dart';
import 'package:xworkmate/runtime/runtime_controllers.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import '../test_support.dart';

void main() {
  test('GatewayRuntime formats connect auth summary consistently', () {
    expect(
      formatGatewayConnectAuthSummary(
        mode: 'shared-token',
        fields: const <String>['token', 'deviceToken'],
        sources: const <String>['shared:form', 'device:store'],
      ),
      'shared-token | fields: token, deviceToken | sources: shared:form · device:store',
    );
    expect(
      formatGatewayConnectAuthSummary(
        mode: 'none',
        fields: const <String>[],
        sources: const <String>[],
      ),
      'none | fields: none | sources: none',
    );
  });

  test(
    'GatewayRuntime uses explicit shared token override for the initial connect handshake',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = createIsolatedTestStore();
      final runtime = GatewayRuntime(
        store: store,
        identityStore: DeviceIdentityStore(store),
      );
      final server = await FakeGatewayRuntimeServerInternal.start();
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
      final store = createIsolatedTestStore();
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
      final server = await FakeGatewayRuntimeServerInternal.start();
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
    'GatewayRuntime persists returned device token and applies go-core session notifications',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = createIsolatedTestStore();
      final identityStore = DeviceIdentityStore(store);
      final fakeClient = _FakeGatewayRuntimeSessionClient(
        connectResult: GatewayRuntimeSessionConnectResult(
          snapshot:
              GatewayConnectionSnapshot.initial(
                mode: RuntimeConnectionMode.remote,
              ).copyWith(
                status: RuntimeConnectionStatus.connected,
                statusText: 'Connected',
                remoteAddress: '127.0.0.1:8787',
                deviceId: 'device-1',
                authRole: 'operator',
                authScopes: const <String>['operator.admin'],
                connectAuthMode: 'shared-token',
                connectAuthFields: const <String>['token'],
                connectAuthSources: const <String>['shared:form'],
                hasSharedAuth: true,
                hasDeviceToken: true,
              ),
          auth: const <String, dynamic>{'role': 'operator'},
          returnedDeviceToken: 'go-device-token',
          raw: const <String, dynamic>{},
        ),
      );
      final runtime = GatewayRuntime(
        store: store,
        identityStore: identityStore,
        sessionClient: fakeClient,
      );
      addTearDown(runtime.dispose);

      await runtime.initialize();
      await runtime.connectProfile(
        GatewayConnectionProfile.defaults().copyWith(
          mode: RuntimeConnectionMode.remote,
          host: '127.0.0.1',
          port: 8787,
          tls: false,
          useSetupCode: false,
        ),
        authTokenOverride: 'shared-token-from-form',
      );

      final identity = await identityStore.loadOrCreate();
      expect(
        await store.loadDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        ),
        'go-device-token',
      );
      expect(fakeClient.lastConnectRequest, isNotNull);
      expect(
        fakeClient.lastConnectRequest!.authToken,
        'shared-token-from-form',
      );
      expect(runtime.snapshot.status, RuntimeConnectionStatus.connected);

      final nextEvent = runtime.events.firstWhere(
        (event) => event.event == 'health',
      );
      fakeClient.emit(
        GatewayRuntimeSessionUpdate(
          runtimeId: fakeClient.lastConnectRequest!.runtimeId,
          type: GatewayRuntimeSessionUpdateType.log,
          log: const RuntimeLogEntry(
            timestampMs: 42,
            level: 'info',
            category: 'socket',
            message: 'reconnect firing',
          ),
        ),
      );
      fakeClient.emit(
        GatewayRuntimeSessionUpdate(
          runtimeId: fakeClient.lastConnectRequest!.runtimeId,
          type: GatewayRuntimeSessionUpdateType.push,
          push: const GatewayPushEvent(
            event: 'health',
            payload: <String, dynamic>{'ok': true},
            sequence: 7,
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(
        runtime.logs.any((entry) => entry.message == 'reconnect firing'),
        isTrue,
      );
      expect(await nextEvent, isA<GatewayPushEvent>());
    },
  );

  test(
    'GatewayChatController applies normalized chat.run updates from go-core',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = createIsolatedTestStore();
      final runtime = _FakeGatewayRuntimeForChatController(store: store);
      final controller = GatewayChatController(runtime);
      addTearDown(controller.dispose);

      await controller.loadSession('agent:main:main');
      await controller.sendMessage(
        sessionKey: 'agent:main:main',
        message: 'hello',
        thinking: 'low',
      );

      expect(controller.hasPendingRun, isTrue);
      runtime.addAssistantMessage('HELLO');
      controller.handleEvent(
        const GatewayPushEvent(
          event: 'chat.run',
          payload: <String, dynamic>{
            'runId': 'run-1',
            'sessionKey': 'agent:main:main',
            'state': 'delta',
            'assistantText': 'HELLO',
            'terminal': false,
          },
        ),
      );
      expect(controller.streamingAssistantText, 'HELLO');

      controller.handleEvent(
        const GatewayPushEvent(
          event: 'chat.run',
          payload: <String, dynamic>{
            'runId': 'run-1',
            'sessionKey': 'agent:main:main',
            'state': 'final',
            'assistantText': 'HELLO',
            'terminal': true,
          },
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(controller.hasPendingRun, isFalse);
      expect(
        controller.messages.any(
          (message) => message.role == 'assistant' && message.text == 'HELLO',
        ),
        isTrue,
      );
    },
  );

  test(
    'GatewayRuntime does not silently fall back to direct websocket when go-core bridge is unavailable',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = createIsolatedTestStore();
      final runtime = GatewayRuntime(
        store: store,
        identityStore: DeviceIdentityStore(store),
        sessionClient: _FakeGatewayRuntimeSessionClient(
          connectError: GatewayRuntimeException(
            'go bridge unavailable',
            code: 'GO_GATEWAY_RUNTIME_ENDPOINT_MISSING',
          ),
        ),
      );
      final server = await FakeGatewayRuntimeServerInternal.start();
      addTearDown(runtime.dispose);
      addTearDown(server.close);

      await runtime.initialize();
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

      expect(server.connectAuth, isNull);
      expect(runtime.snapshot.status, RuntimeConnectionStatus.error);
      expect(runtime.snapshot.lastErrorCode, 'GO_GATEWAY_RUNTIME_ENDPOINT_MISSING');
    },
  );

  test(
    'GatewayRuntime can explicitly fall back to direct websocket when enabled',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = createIsolatedTestStore();
      final runtime = GatewayRuntime(
        store: store,
        identityStore: DeviceIdentityStore(store),
        sessionClient: _FakeGatewayRuntimeSessionClient(
          connectError: GatewayRuntimeException(
            'go bridge unavailable',
            code: 'GO_GATEWAY_RUNTIME_ENDPOINT_MISSING',
          ),
        ),
        allowDirectSocketFallbackOnSessionClientFailure: true,
      );
      final server = await FakeGatewayRuntimeServerInternal.start();
      addTearDown(runtime.dispose);
      addTearDown(server.close);

      await runtime.initialize();
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
      expect(runtime.snapshot.status, RuntimeConnectionStatus.connected);
    },
  );

  test(
    'GatewayRuntime parses device pairing state and syncs rotated local role tokens',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = createIsolatedTestStore();
      final identityStore = DeviceIdentityStore(store);
      final identity = await identityStore.loadOrCreate();
      final runtime = GatewayRuntime(
        store: store,
        identityStore: identityStore,
      );
      final server = await FakeGatewayRuntimeServerInternal.start(
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
      final store = createIsolatedTestStore();
      final runtime = GatewayRuntime(
        store: store,
        identityStore: DeviceIdentityStore(store),
      );
      final server = await FakeGatewayRuntimeServerInternal.start(
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

  test(
    'GatewayRuntime clears a stale stored device token after NOT_PAIRED',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = createIsolatedTestStore();
      final identityStore = DeviceIdentityStore(store);
      final identity = await identityStore.loadOrCreate();
      await store.saveDeviceToken(
        deviceId: identity.deviceId,
        role: 'operator',
        token: 'stale-device-token',
      );
      final runtime = GatewayRuntime(
        store: store,
        identityStore: identityStore,
      );
      final server = await FakeGatewayRuntimeServerInternal.start(
        connectErrorCode: 'NOT_PAIRED',
        connectErrorDetailCode: 'PAIRING_REQUIRED',
        connectErrorMessage: 'pairing required',
        closeAfterConnectError: true,
      );
      addTearDown(runtime.dispose);
      addTearDown(server.close);

      await expectLater(
        () => runtime.connectProfile(
          GatewayConnectionProfile.defaults().copyWith(
            mode: RuntimeConnectionMode.remote,
            host: '127.0.0.1',
            port: server.port,
            tls: false,
            useSetupCode: false,
          ),
        ),
        throwsA(isA<GatewayRuntimeException>()),
      );

      expect(server.connectAuth?['token'], 'stale-device-token');
      expect(server.connectAuth?['deviceToken'], 'stale-device-token');
      expect(
        await store.loadDeviceToken(
          deviceId: identity.deviceId,
          role: 'operator',
        ),
        isNull,
      );
      expect(
        runtime.logs.any(
          (entry) =>
              entry.category == 'auth' &&
              entry.message.contains('cleared stale device token'),
        ),
        isTrue,
      );
    },
  );
}

class _FakeGatewayRuntimeSessionClient implements GatewayRuntimeSessionClient {
  _FakeGatewayRuntimeSessionClient({this.connectResult, this.connectError});

  final GatewayRuntimeSessionConnectResult? connectResult;
  final GatewayRuntimeException? connectError;
  final StreamController<GatewayRuntimeSessionUpdate> _updates =
      StreamController<GatewayRuntimeSessionUpdate>.broadcast();
  GatewayRuntimeSessionConnectRequest? lastConnectRequest;

  @override
  Stream<GatewayRuntimeSessionUpdate> get updates => _updates.stream;

  void emit(GatewayRuntimeSessionUpdate update) {
    _updates.add(update);
  }

  @override
  Future<GatewayRuntimeSessionConnectResult> connect(
    GatewayRuntimeSessionConnectRequest request,
  ) async {
    lastConnectRequest = request;
    if (connectError != null) {
      throw connectError!;
    }
    return connectResult ??
        GatewayRuntimeSessionConnectResult(
          snapshot: GatewayConnectionSnapshot.initial(mode: request.mode),
          auth: const <String, dynamic>{},
          returnedDeviceToken: '',
          raw: const <String, dynamic>{},
        );
  }

  @override
  Future<void> disconnect({required String runtimeId}) async {}

  @override
  Future<void> dispose() async {
    await _updates.close();
  }

  @override
  Future<dynamic> request({
    required String runtimeId,
    required String method,
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return const <String, dynamic>{};
  }
}

class _FakeGatewayRuntimeForChatController extends GatewayRuntime {
  _FakeGatewayRuntimeForChatController({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

  final List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];

  @override
  bool get isConnected => true;

  void addAssistantMessage(String text) {
    _history.add(<String, dynamic>{
      'role': 'assistant',
      'content': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': text},
      ],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    switch (method) {
      case 'chat.history':
        return <String, dynamic>{'messages': List<Object>.from(_history)};
      case 'chat.send':
        final text = params?['message']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          _history.add(<String, dynamic>{
            'role': 'user',
            'content': <Map<String, dynamic>>[
              <String, dynamic>{'type': 'text', 'text': text},
            ],
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
        return <String, dynamic>{'runId': 'run-1'};
      case 'chat.abort':
        return const <String, dynamic>{};
      default:
        return const <String, dynamic>{};
    }
  }
}

class FakeGatewayRuntimeServerInternal {
  FakeGatewayRuntimeServerInternal._(
    this.serverInternal, {
    required this.currentDeviceId,
    required this.connectErrorCode,
    required this.connectErrorDetailCode,
    required this.connectErrorMessage,
    required this.closeAfterConnectError,
  });

  final HttpServer serverInternal;
  final String? currentDeviceId;
  final String? connectErrorCode;
  final String? connectErrorDetailCode;
  final String? connectErrorMessage;
  final bool closeAfterConnectError;
  Map<String, dynamic>? connectAuth;
  int connectRequestCount = 0;

  int get port => serverInternal.port;

  static Future<FakeGatewayRuntimeServerInternal> start({
    String? currentDeviceId,
    String? connectErrorCode,
    String? connectErrorDetailCode,
    String? connectErrorMessage,
    bool closeAfterConnectError = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeGatewayRuntimeServerInternal._(
      server,
      currentDeviceId: currentDeviceId,
      connectErrorCode: connectErrorCode,
      connectErrorDetailCode: connectErrorDetailCode,
      connectErrorMessage: connectErrorMessage,
      closeAfterConnectError: closeAfterConnectError,
    );
    unawaited(fake.serveInternal());
    return fake;
  }

  Future<void> close() async {
    await serverInternal.close(force: true);
  }

  Future<void> serveInternal() async {
    await for (final request in serverInternal) {
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
