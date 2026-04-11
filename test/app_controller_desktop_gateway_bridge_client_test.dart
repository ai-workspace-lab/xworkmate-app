import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/runtime/external_code_agent_acp_desktop_transport.dart';
import 'package:xworkmate/runtime/go_task_service_desktop_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default desktop controller no longer depends on local go-core session client', () {
    final controller = AppController();
    addTearDown(controller.dispose);

    expect(controller.runtime.usesSessionClient, isFalse);
  });

  test(
    'default desktop controller shares one ACP client between app wiring and task transport',
    () {
      final controller = AppController();
      addTearDown(controller.dispose);

      final taskService =
          controller.goTaskServiceClientForTest as DesktopGoTaskService;
      final transport =
          taskService.acpTransportForTest as ExternalCodeAgentAcpDesktopTransport;

      expect(controller.gatewayAcpClientForTest, same(transport.clientForTest));
    },
  );
}
