@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xworkmate/app/app_controller_web.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/web/web_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('web controller persists direct and relay configuration', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final controller = AppController(store: WebStore());
    await _waitForReady(controller);

    await controller.saveAiGatewayConfiguration(
      name: 'Direct AI',
      baseUrl: 'https://api.example.com/v1',
      provider: 'openai-compatible',
      apiKey: 'sk-test-web',
      defaultModel: '',
    );
    await controller.saveRelayConfiguration(
      host: 'relay.example.com',
      port: 443,
      tls: true,
      token: 'relay-token',
      password: 'relay-password',
    );
    await controller.setAssistantExecutionTarget(
      AssistantExecutionTarget.remote,
    );
    await controller.createConversation(
      target: AssistantExecutionTarget.aiGatewayOnly,
    );

    final reloaded = AppController(store: WebStore());
    await _waitForReady(reloaded);

    expect(reloaded.settings.aiGateway.baseUrl, 'https://api.example.com/v1');
    expect(reloaded.settings.defaultProvider, 'openai-compatible');
    expect(reloaded.settings.gateway.host, 'relay.example.com');
    expect(reloaded.settings.gateway.port, 443);
    expect(
      reloaded.settings.assistantExecutionTarget,
      AssistantExecutionTarget.remote,
    );
    expect(reloaded.storedAiGatewayApiKeyMask, isNotNull);
    expect(reloaded.storedRelayTokenMask, isNotNull);
    expect(reloaded.conversations, isNotEmpty);

    controller.dispose();
    reloaded.dispose();
  });
}

Future<void> _waitForReady(
  AppController controller, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (controller.initializing) {
    if (DateTime.now().isAfter(deadline)) {
      fail('controller did not initialize before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
