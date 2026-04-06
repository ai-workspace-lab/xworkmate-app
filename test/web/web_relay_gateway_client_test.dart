@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/web/web_relay_gateway_client.dart';
import 'package:xworkmate/web/web_store.dart';

class _FakeWebRelayGatewayClient extends WebRelayGatewayClient {
  _FakeWebRelayGatewayClient() : super(WebStore());

  String? lastMethod;
  Map<String, dynamic>? lastParams;

  @override
  bool get isConnected => true;

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    lastMethod = method;
    lastParams = params == null ? null : Map<String, dynamic>.from(params);
    return const <String, dynamic>{'runId': 'relay-run'};
  }
}

void main() {
  test('WebRelayGatewayClient omits metadata from chat.send payloads', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final client = _FakeWebRelayGatewayClient();

    final runId = await client.sendChat(
      sessionKey: 'thread-1',
      message: 'hello',
      thinking: 'medium',
      metadata: const <String, dynamic>{'threadMode': 'test'},
      attachments: const <GatewayChatAttachmentPayload>[],
    );

    expect(runId, 'relay-run');
    expect(client.lastMethod, 'chat.send');
    expect(client.lastParams, isNotNull);
    expect(client.lastParams, isNot(contains('metadata')));
  });
}
