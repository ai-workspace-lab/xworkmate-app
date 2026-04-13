import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('Assistant connection state', () {
    test('maps generic bridge runtime failures to connection failed', () async {
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
      expect(state.status, RuntimeConnectionStatus.error);
      expect(state.primaryLabel, '连接失败');
      expect(state.detailLabel, 'openclaw.svc.plus:443');
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
      'maps generic failures without address to bridge connection failed',
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
        expect(state.status, RuntimeConnectionStatus.error);
        expect(state.primaryLabel, '连接失败');
        expect(state.detailLabel, 'xworkmate-bridge 连接失败');
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
        expect(state.status, RuntimeConnectionStatus.error);
        expect(state.primaryLabel, '缺少令牌');
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
      expect(snapshot['connectionStatus'], 'error');
      expect(snapshot['connectionLabel'], '连接失败');
    });
  });
}
