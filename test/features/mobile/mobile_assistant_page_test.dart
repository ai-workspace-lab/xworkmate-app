import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_shell_desktop.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
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
      expect(find.text('你想让我帮你做什么？'), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-assistant-open-menu-button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('mobile-assistant-input')), findsOneWidget);
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

    testWidgets('mobile menu opens task navigation with home breadcrumb', (
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

      await tester.tap(
        find.byKey(const Key('mobile-assistant-open-menu-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('返回对话主页'), findsOneWidget);
      expect(find.text('XWorkmate'), findsOneWidget);
      expect(find.text('集成配置'), findsOneWidget);
      expect(find.text('工作区'), findsNothing);
      expect(find.text('AI 工作空间'), findsNothing);
      expect(
        find.byKey(const Key('mobile-assistant-fab-create')),
        findsOneWidget,
      );

      await tester.tap(find.text('返回对话主页'));
      await tester.pumpAndSettle();

      expect(find.text('你想让我帮你做什么？'), findsOneWidget);
    });

    testWidgets('mobile history opens quick task switcher', (tester) async {
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

      await tester.tap(
        find.byKey(const Key('mobile-assistant-open-history-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('切换任务会话'), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-session-switcher-new-task')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-session-switcher-full-list')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('mobile-session-switcher-full-list')),
      );
      await tester.pumpAndSettle();

      expect(find.text('返回对话主页'), findsOneWidget);
      expect(find.text('XWorkmate'), findsOneWidget);
    });

    testWidgets('disconnected state guides to integration settings', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildTestApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('先配置集成连接'), findsWidgets);
      expect(find.text('去配置集成'), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-assistant-connect-bridge-button')),
        findsOneWidget,
      );
    });

    testWidgets('composer add sheet keeps plugins and skills compact', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildTestApp(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('mobile-assistant-composer-add-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('会话配置'), findsOneWidget);
      expect(find.text('内置插件'), findsOneWidget);
      expect(find.text('技能选择'), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-assistant-plugin-chip-builtin.document')),
        findsOneWidget,
      );
      expect(find.text('当前没有已加载技能。'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('mobile-assistant-plugin-chip-builtin.document')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobile-assistant-sheet-close')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key('mobile-assistant-selected-plugin-builtin.document'),
        ),
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
        find.byKey(const Key('mobile-assistant-composer-add-button')),
      );
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
        uiFeatureManifest: _defaultDesktopManifest(),
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

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    key: const Key('show-agent-provider-sheet'),
                    onPressed: () {
                      showMobileAssistantProviderSheet(
                        context,
                        controller: controller,
                        target: AssistantExecutionTarget.agent,
                        selectedProvider: SingleAgentProvider.codex,
                        onSelected: (_) async {},
                      );
                    },
                    child: const Text('Agent providers'),
                  ),
                  TextButton(
                    key: const Key('show-gateway-provider-sheet'),
                    onPressed: () {
                      showMobileAssistantProviderSheet(
                        context,
                        controller: controller,
                        target: AssistantExecutionTarget.gateway,
                        selectedProvider: SingleAgentProvider.openclaw,
                        onSelected: (_) async {},
                      );
                    },
                    child: const Text('Gateway providers'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('show-agent-provider-sheet')));
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

      await tester.tap(find.byKey(const Key('show-gateway-provider-sheet')));
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

UiFeatureManifest _defaultDesktopManifest() {
  return UiFeatureManifest.fromYamlString(
    File(UiFeatureManifest.assetPath).readAsStringSync(),
  );
}
