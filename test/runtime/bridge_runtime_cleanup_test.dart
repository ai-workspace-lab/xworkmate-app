import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/mode_switcher.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('Bridge runtime cleanup', () {
    test('resolves the managed bridge endpoint without BRIDGE_SERVER_URL', () {
      final controller = AppController(
        environmentOverride: const <String, String>{
          'BRIDGE_SERVER_URL': 'https://stale.example.invalid',
        },
      );
      addTearDown(controller.dispose);

      expect(
        controller.resolveBridgeAcpEndpointInternal()?.toString(),
        kManagedBridgeServerUrl,
      );
      expect(
        controller
            .resolveExternalAcpEndpointForTargetInternal(
              AssistantExecutionTarget.gateway,
            )
            ?.toString(),
        kManagedBridgeServerUrl,
      );
    });

    test(
      'runtime coordinator only exposes remote and offline gateway modes',
      () {
        final controller = AppController();
        addTearDown(controller.dispose);

        expect(
          controller.runtimeCoordinatorInternal.getAvailableModes(),
          const <GatewayMode>[GatewayMode.remote, GatewayMode.offline],
        );
      },
    );
  });
}
