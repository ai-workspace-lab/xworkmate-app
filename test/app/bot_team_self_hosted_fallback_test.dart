import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_controller_desktop_bot_team.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppControllerDesktopBotTeam Self-Hosted Fallback Tests', () {
    test('resolveTaskSessionAuthTokenInternal resolves environment token when account token is empty', () async {
      final controller = AppController(
        environmentOverride: {
          'XWORKMATE_MANAGED_BRIDGE_URL': 'http://127.0.0.1:8787/acp/rpc',
          'AI_WORKSPACE_AUTH_TOKEN': 'env-ai-workspace-token-123',
        },
      );

      final endpoint = Uri.parse('http://127.0.0.1:8787/acp/rpc');
      final resolvedToken = await controller.resolveTaskSessionAuthTokenInternal(endpoint);
      expect(resolvedToken, equals('env-ai-workspace-token-123'));

      final client = controller.createTaskSessionClient();
      expect(client, isNotNull);
    });

    test('createTaskSessionClient supports ACP_BRIDGE_SERVER_TOKEN fallback', () {
      final controller = AppController(
        environmentOverride: {
          'XWORKMATE_MANAGED_BRIDGE_URL': 'http://127.0.0.1:8787/acp/rpc',
          'ACP_BRIDGE_SERVER_TOKEN': 'bridge-server-secret-key',
        },
      );

      final client = controller.createTaskSessionClient();
      expect(client, isNotNull);
    });
  });
}
