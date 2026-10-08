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
        find.text(
          controller.currentAssistantConnectionState.connected
              ? 'AI Workspace 已连接'
              : '先配置集成连接',
        ),
        findsOneWidget,
      );
      expect(find.text('你想先用哪个内置插件？'), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-plugin-scene-carousel')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('mobile-plugin-scene-carousel')),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      final firstCard = find.byKey(
        const Key('mobile-plugin-shortcut-builtin.document'),
      );
      final startingOffset = tester.getTopLeft(firstCard).dx;
      await tester.drag(
        find.byKey(const Key('mobile-plugin-scene-carousel')),
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(firstCard).dx, lessThan(startingOffset));
      final carouselRect = tester.getRect(
        find.byKey(const Key('mobile-plugin-scene-carousel')),
      );
      final input = tester.widget<TextField>(
        find.byKey(const Key('mobile-assistant-input')),
      );
      final inputRect = tester.getRect(
        find.byKey(const Key('mobile-assistant-input')),
      );
      expect(input.maxLines, 1);
      expect(inputRect.top - carouselRect.bottom, lessThan(48));
      expect(
        find.descendant(
          of: find.byKey(const Key('mobile-assistant-composer-add-button')),
          matching: find.byIcon(Icons.add),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-plugin-shortcut-builtin.document')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-plugin-shortcut-builtin.spreadsheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-plugin-shortcut-builtin.presentation')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-plugin-shortcut-builtin.image')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-plugin-shortcut-builtin.video')),
        findsOneWidget,
      );
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

      expect(find.text('你想先用哪个内置插件？'), findsOneWidget);
    });

    testWidgets('mobile plugins tab shows the built-in plugin panel', (
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
      await tester.tap(find.text('插件'));
      await tester.pumpAndSettle();

      expect(find.text('内置插件'), findsOneWidget);
      expect(find.text('文档'), findsWidgets);
      expect(find.text('电子表格'), findsWidgets);
      expect(find.text('PPT 演示'), findsWidgets);
      expect(find.text('图片'), findsWidgets);
      expect(find.text('视频'), findsWidgets);
    });

    testWidgets('home plugin shortcuts reuse the session plugin selection', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      selectedBuiltinPluginIdsBySessionInternal.clear();
      addTearDown(selectedBuiltinPluginIdsBySessionInternal.clear);

      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildTestApp(controller: controller));
      await tester.pumpAndSettle();

      final shortcut = find.byKey(
        const Key('mobile-plugin-shortcut-builtin.document'),
      );
      final shortcutChip = find.descendant(
        of: shortcut,
        matching: find.byType(FilterChip),
      );
      expect(shortcut, findsOneWidget);
      expect(tester.widget<FilterChip>(shortcutChip).selected, isFalse);

      await tester.tap(shortcut);
      await tester.pumpAndSettle();

      expect(tester.widget<FilterChip>(shortcutChip).selected, isTrue);
      expect(
        find.byKey(
          const Key('mobile-assistant-selected-plugin-builtin.document'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('mobile-assistant-input')))
            .controller
            ?.text,
        isEmpty,
      );

      await tester.tap(shortcut);
      await tester.pumpAndSettle();

      expect(tester.widget<FilterChip>(shortcutChip).selected, isFalse);
      expect(
        find.byKey(
          const Key('mobile-assistant-selected-plugin-builtin.document'),
        ),
        findsNothing,
      );
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

    testWidgets('mobile task header exposes task workspace and copy action', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_buildTestApp(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('查看任务ID'));
      await tester.pumpAndSettle();

      final workspaceReference = tester.widget<Text>(
        find.byKey(const Key('mobile-assistant-task-workspace-ref')),
      );
      expect(
        workspaceReference.data,
        matches(RegExp(r'^/.+/\.xworkmate/threads/draft-[A-Za-z0-9._-]+$')),
      );
      expect(
        find.byKey(const Key('mobile-assistant-copy-task-workspace-ref')),
        findsOneWidget,
      );
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

      expect(find.byKey(const Key('mobile-assistant-tab-0')), findsOneWidget);
      expect(find.byKey(const Key('mobile-assistant-tab-1')), findsOneWidget);
      expect(find.byKey(const Key('mobile-assistant-tab-2')), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-assistant-tab-attach')),
        findsOneWidget,
      );

      // Switch to Plugins tab (Tab 1)
      await tester.tap(find.byKey(const Key('mobile-assistant-tab-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('mobile-assistant-plugin-chip-builtin.document')),
        findsOneWidget,
      );

      // Switch to Skills tab (Tab 2)
      await tester.tap(find.byKey(const Key('mobile-assistant-tab-2')));
      await tester.pumpAndSettle();
      expect(find.text('当前没有已加载技能。'), findsOneWidget);

      // Go back to Plugins tab and select plugin
      await tester.tap(find.byKey(const Key('mobile-assistant-tab-1')));
      await tester.pumpAndSettle();
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

    for (final withCatalog in [false, true]) {
      testWidgets(
        'mobile mode configuration removes provider routing (catalog=$withCatalog)',
        (tester) async {
          final controller = AppController(
            environmentOverride: const <String, String>{},
            initialBridgeProviderCatalog: withCatalog
                ? const [SingleAgentProvider.codex]
                : const [],
            initialGatewayProviderCatalog: withCatalog
                ? const [SingleAgentProvider.openclaw]
                : const [],
          );
          final input = TextEditingController();
          final focus = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(input.dispose);
          addTearDown(focus.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(platform: TargetPlatform.iOS),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: MobileAssistantComposer(
                    controller: controller,
                    inputController: input,
                    focusNode: focus,
                    thinking: 'off',
                    bottomPadding: 0,
                    attachments: const [],
                    onPickAttachments: () {},
                    onRemoveAttachment: (_) {},
                    onThinkingChanged: (_) {},
                    onComposerStateChanged: () {},
                    onSend: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('mobile-assistant-composer-add-button')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('mobile-assistant-provider-button')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('mobile-assistant-provider-empty-state')),
            findsNothing,
          );
          await tester.tap(
            find.byKey(const Key('mobile-assistant-product-mode-button')),
          );
          await tester.pumpAndSettle();
          for (final mode in ['chat', 'work', 'coding', 'autoBot']) {
            expect(
              find.byKey(Key('mobile-assistant-product-mode-$mode')),
              findsOneWidget,
            );
          }
          expect(
            find.byKey(const Key('mobile-assistant-target-item-gateway')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('mobile-assistant-target-item-agent')),
            findsNothing,
          );
        },
      );
    }

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

    testWidgets('generated artifact card exposes the file action', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: MobileGeneratedArtifactCardInternal(
              key: const Key('mobile-generated-artifact-test-card'),
              title: 'poster.png',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('mobile-generated-artifact-test-card')),
        findsOneWidget,
      );
      expect(find.text('poster.png'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('mobile-generated-artifact-test-card')),
      );
      expect(tapped, isTrue);
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
