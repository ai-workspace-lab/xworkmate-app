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
    'GatewayRuntime uses explicit auth override for the initial connect handshake',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SecureConfigStore();
      final runtime = GatewayRuntime(
        store: store,
        identityStore: DeviceIdentityStore(store),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final handshakeSeen = Completer<void>();
      Map<String, dynamic>? receivedAuth;

      unawaited(() async {
        await for (final request in server) {
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
            if (frame['type'] != 'req' || frame['method'] != 'connect') {
              continue;
            }
            receivedAuth =
                (frame['params'] as Map<String, dynamic>)['auth']
                    as Map<String, dynamic>?;
            socket.add(
              jsonEncode(<String, dynamic>{
                'type': 'res',
                'id': frame['id'],
                'ok': true,
                'payload': <String, dynamic>{
                  'server': <String, dynamic>{'host': '127.0.0.1'},
                  'snapshot': <String, dynamic>{
                    'sessionDefaults': <String, dynamic>{
                      'mainSessionKey': 'main',
                    },
                  },
                },
              }),
            );
            if (!handshakeSeen.isCompleted) {
              handshakeSeen.complete();
            }
            break;
          }
        }
      }());

      final profile = GatewayConnectionProfile.defaults().copyWith(
        mode: RuntimeConnectionMode.local,
        host: '127.0.0.1',
        port: server.port,
        tls: false,
        useSetupCode: false,
      );

      await runtime.connectProfile(
        profile,
        authTokenOverride: 'shared-token-from-form',
      );
      await handshakeSeen.future.timeout(const Duration(seconds: 2));

      expect(receivedAuth?['token'], 'shared-token-from-form');
      expect(runtime.snapshot.status, RuntimeConnectionStatus.connected);

      await runtime.disconnect();
      runtime.dispose();
      await server.close(force: true);
    },
  );
}
