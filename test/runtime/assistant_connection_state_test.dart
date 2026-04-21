import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('Assistant connection state', () {
    test(
      'keeps signed-out sessions disconnected even when provider catalogs exist',
      () async {
        final controller = AppController(
          initialBridgeProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
          ],
          initialGatewayProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.openclaw,
          ],
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        final state = controller.currentAssistantConnectionState;
        expect(state.connected, isFalse);
        expect(state.status, RuntimeConnectionStatus.offline);
        expect(state.detailLabel, 'xworkmate-bridge 未连接');
      },
    );

    test('keeps signed-out generic runtime failures disconnected', () async {
      final controller = AppController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('session-1');
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.gateway,
      );

      controller.runtimeInternal.snapshotInternal = controller
          .runtimeInternal
          .snapshot
          .copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Connection failed',
            remoteAddress: 'openclaw.svc.plus:443',
            lastError: 'unsupported Ed25519 private key length: 0',
            lastErrorCode: 'DEVICE_IDENTITY_SIGN_FAILED',
            lastErrorDetailCode: null,
          );

      final state = controller.currentAssistantConnectionState;
      expect(state.status, RuntimeConnectionStatus.offline);
      expect(state.primaryLabel, '离线');
      expect(state.detailLabel, 'xworkmate-bridge 未连接');
    });

    test('keeps true offline state as bridge not connected', () async {
      final controller = AppController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('session-1');
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.gateway,
      );

      controller.runtimeInternal.snapshotInternal =
          GatewayConnectionSnapshot.initial(
            mode: controller.runtimeInternal.snapshot.mode,
          );

      final state = controller.currentAssistantConnectionState;
      expect(state.status, RuntimeConnectionStatus.offline);
      expect(state.primaryLabel, '离线');
      expect(state.detailLabel, 'xworkmate-bridge 未连接');
    });

    test(
      'keeps signed-out generic failures without address disconnected',
      () async {
        final controller = AppController();
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        controller.runtimeInternal.snapshotInternal = controller
            .runtimeInternal
            .snapshot
            .copyWith(
              status: RuntimeConnectionStatus.error,
              statusText: 'Connection failed',
              lastError: 'socket closed',
              lastErrorCode: 'SOCKET_CLOSED',
              lastErrorDetailCode: null,
              clearRemoteAddress: true,
            );

        final state = controller.currentAssistantConnectionState;
        expect(state.status, RuntimeConnectionStatus.offline);
        expect(state.primaryLabel, '离线');
        expect(state.detailLabel, 'xworkmate-bridge 未连接');
      },
    );

    test(
      'keeps gateway token missing as dedicated app-visible state',
      () async {
        final controller = AppController();
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        controller.runtimeInternal.snapshotInternal = controller
            .runtimeInternal
            .snapshot
            .copyWith(
              status: RuntimeConnectionStatus.error,
              statusText: 'Connection failed',
              lastError: 'gateway token missing',
              lastErrorCode: 'AUTH_FAILED',
              lastErrorDetailCode: 'AUTH_TOKEN_MISSING',
              clearRemoteAddress: true,
            );

        final state = controller.currentAssistantConnectionState;
        expect(state.status, RuntimeConnectionStatus.offline);
        expect(state.primaryLabel, '离线');
        expect(state.detailLabel, 'xworkmate-bridge 未连接');
      },
    );

    test(
      'treats missing endpoint as true offline instead of bridge failure',
      () async {
        final controller = AppController();
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        controller.runtimeInternal.snapshotInternal = controller
            .runtimeInternal
            .snapshot
            .copyWith(
              status: RuntimeConnectionStatus.error,
              statusText: 'Missing gateway endpoint',
              lastError: 'Configure setup code or manual host / port first.',
              lastErrorCode: 'MISSING_ENDPOINT',
              clearRemoteAddress: true,
            );

        final state = controller.currentAssistantConnectionState;
        expect(state.status, RuntimeConnectionStatus.offline);
        expect(state.primaryLabel, '离线');
        expect(state.detailLabel, 'xworkmate-bridge 未连接');
      },
    );

    test('desktop snapshot uses derived assistant connection labels', () async {
      final controller = AppController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('session-1');
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.gateway,
      );

      controller.runtimeInternal.snapshotInternal = controller
          .runtimeInternal
          .snapshot
          .copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Connection failed',
            remoteAddress: 'openclaw.svc.plus:443',
            lastError: 'unsupported Ed25519 private key length: 0',
            lastErrorCode: 'DEVICE_IDENTITY_SIGN_FAILED',
          );

      final snapshot = controller.desktopStatusSnapshot();
      expect(snapshot['connectionStatus'], 'disconnected');
      expect(snapshot['connectionLabel'], '离线');
    });
  });
}
