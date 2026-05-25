import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_shell_desktop.dart';
import 'package:xworkmate/app/workspace_page_registry.dart';
import 'package:xworkmate/features/mobile/mobile_assistant_page.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  group('MobileAssistantPage', () {
    testWidgets('mobile shell renders the mobile assistant surface', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: AppShell(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mobile-assistant-page')), findsOneWidget);
      expect(
        find.byKey(const Key('assistant-conversation-shell')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('assistant-workspace-resize-handle')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('assistant-composer-resize-handle')),
        findsNothing,
      );
    });

    testWidgets('disconnected state shows a mobile Bridge connect CTA', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildTestApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('先连接 Bridge'), findsWidgets);
      expect(
        find.byKey(const Key('mobile-assistant-connect-bridge-button')),
        findsOneWidget,
      );
    });

    testWidgets('provider sheet fails closed when capabilities are empty', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildTestApp(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('mobile-assistant-provider-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('mobile-assistant-provider-empty-state')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-assistant-provider-item-codex')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('mobile-assistant-provider-item-openclaw')),
        findsNothing,
      );
    });

    testWidgets('provider sheet follows execution target capabilities', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
        initialBridgeProviderCatalog: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        initialGatewayProviderCatalog: <SingleAgentProvider>[
          SingleAgentProvider.openclaw.copyWith(
            supportedTargets: const <AssistantExecutionTarget>[
              AssistantExecutionTarget.gateway,
            ],
          ),
        ],
        initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
          AssistantExecutionTarget.agent,
          AssistantExecutionTarget.gateway,
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildTestApp(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('mobile-assistant-provider-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('mobile-assistant-provider-item-codex')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-assistant-provider-item-openclaw')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('mobile-assistant-sheet-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobile-assistant-target-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('mobile-assistant-target-item-gateway')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('mobile-assistant-provider-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('mobile-assistant-provider-item-openclaw')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-assistant-provider-item-codex')),
        findsNothing,
      );
    });

    testWidgets('composer and submit stay visible with iPhone keyboard inset', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _buildTestApp(
          controller: controller,
          viewInsets: const EdgeInsets.only(bottom: 312),
        ),
      );
      await tester.pumpAndSettle();

      final inputRect = tester.getRect(
        find.byKey(const Key('mobile-assistant-input')),
      );
      final sendRect = tester.getRect(
        find.byKey(const Key('mobile-assistant-send-button')),
      );

      expect(inputRect.bottom, lessThanOrEqualTo(844));
      expect(sendRect.bottom, lessThanOrEqualTo(844));
      expect(sendRect.width, greaterThanOrEqualTo(32));
      expect(sendRect.height, greaterThanOrEqualTo(32));
    });
  });
}

Widget _buildTestApp({
  required AppController controller,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  final child = MobileAssistantDetailPage(
    controller: controller,
    onOpenDetail: (_) {},
    onBack: () {},
    mobileActions: const MobileWorkspaceActions(),
  );

  return MaterialApp(
    theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
    home: MediaQuery(
      data: MediaQueryData(size: const Size(430, 932), viewInsets: viewInsets),
      child: Scaffold(body: child),
    ),
  );
}
