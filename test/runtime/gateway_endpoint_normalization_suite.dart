@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test('GatewayConnectionProfile normalizes a remote wss host value', () {
    final profile = GatewayConnectionProfile.fromJson(<String, dynamic>{
      'mode': 'remote',
      'host': 'wss://openclaw.svc.plus',
      'port': 443,
      'tls': true,
    });

    expect(profile.host, 'openclaw.svc.plus');
    expect(profile.port, 443);
    expect(profile.tls, isTrue);
  });

  test('GatewayConnectionProfile normalizes a local ws host value', () {
    final profile = GatewayConnectionProfile.defaults().copyWith(
      mode: RuntimeConnectionMode.local,
      host: 'ws://127.0.0.1',
      port: 18789,
      tls: false,
    );

    expect(profile.host, '127.0.0.1');
    expect(profile.port, 18789);
    expect(profile.tls, isFalse);
  });

  test('parseGatewayEndpoint resolves default ports from ws and wss URLs', () {
    expect(parseGatewayEndpoint('wss://openclaw.svc.plus'), (
      'openclaw.svc.plus',
      443,
      true,
    ));
    expect(parseGatewayEndpoint('ws://127.0.0.1'), ('127.0.0.1', 18789, false));
  });
}
