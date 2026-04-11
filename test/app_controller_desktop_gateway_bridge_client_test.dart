import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/runtime/external_code_agent_acp_desktop_transport.dart';
import 'package:xworkmate/runtime/go_gateway_runtime_desktop_client.dart';
import 'package:xworkmate/runtime/go_task_service_desktop_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default desktop controller wires gateway runtime through bridge client', () {
    final controller = AppController();
    addTearDown(controller.dispose);

    expect(controller.runtime.usesSessionClient, isTrue);
  });

  test(
    'default desktop controller shares one ACP bridge between gateway runtime and task transport',
    () {
      final controller = AppController();
      addTearDown(controller.dispose);

      final sessionClient =
          controller.runtime.sessionClientForTest
              as GoGatewayRuntimeDesktopClient;
      final taskService =
          controller.goTaskServiceClientForTest as DesktopGoTaskService;
      final transport =
          taskService.acpTransportForTest as ExternalCodeAgentAcpDesktopTransport;

      expect(sessionClient.bridgeForTest, same(transport.bridgeForTest));
    },
  );
}
