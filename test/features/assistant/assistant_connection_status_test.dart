import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  group('Assistant connection status surfaces', () {
    testWidgets('shows connection failed chip for generic bridge failures', (
      tester,
    ) async {
      final controller = AppController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('session-1');
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

      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(_buildAssistantPage(controller));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const Key('assistant-connection-chip')),
        findsOneWidget,
      );
      expect(find.text('连接失败 · openclaw.svc.plus:443'), findsOneWidget);
      expect(find.text('离线 · xworkmate-bridge 未连接'), findsNothing);
    });

    testWidgets('shows failure empty state for generic bridge errors', (
      tester,
    ) async {
      final controller = AppController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('session-1');
      controller.runtimeInternal.snapshotInternal = controller
          .runtimeInternal
          .snapshot
          .copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Connection failed',
            lastError: 'unsupported Ed25519 private key length: 0',
            lastErrorCode: 'DEVICE_IDENTITY_SIGN_FAILED',
            clearRemoteAddress: true,
          );

      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(_buildAssistantPage(controller));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const Key('assistant-empty-state-card')),
        findsOneWidget,
      );
      expect(find.text('Bridge 连接失败'), findsOneWidget);
      expect(
        find.text('unsupported Ed25519 private key length: 0'),
        findsOneWidget,
      );
      expect(find.text('先连接 Bridge'), findsNothing);
    });

    testWidgets('shows offline empty state only for true offline', (
      tester,
    ) async {
      final controller = AppController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('session-1');
      controller.runtimeInternal.snapshotInternal =
          GatewayConnectionSnapshot.initial(
            mode: controller.runtimeInternal.snapshot.mode,
          );

      await tester.binding.setSurfaceSize(const Size(1440, 960));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(_buildAssistantPage(controller));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const Key('assistant-empty-state-card')),
        findsOneWidget,
      );
      expect(find.text('先连接 Bridge'), findsOneWidget);
      expect(
        find.text('当前 xworkmate-bridge 尚未连接。请先恢复 bridge 连接，再继续当前任务。'),
        findsOneWidget,
      );
    });
  });
}

Widget _buildAssistantPage(AppController controller) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: AssistantPage(
      controller: controller,
      onOpenDetail: (DetailPanelData _) {},
    ),
  );
}
