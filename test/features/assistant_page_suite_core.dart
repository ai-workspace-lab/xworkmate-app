// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/multi_agent_orchestrator.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/pane_resize_handle.dart';
import '../test_support.dart';
import 'assistant_page_suite_composer.dart';
import 'assistant_page_suite_support.dart';

void registerAssistantPageSuiteCoreTestsInternal() {
  testWidgets(
    'AssistantPage desktop hides conversation header text and shows thread rail',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
        platform: TargetPlatform.macOS,
      );

      expect(find.byKey(const Key('assistant-task-rail')), findsOneWidget);
      expect(
        find.byKey(const Key('assistant-conversation-title')),
        findsNothing,
      );
      expect(controller.currentSessionKey, 'main');
    },
    skip: true,
  );

  testWidgets('AssistantPage keeps draft task visible until archived', (
    WidgetTester tester,
  ) async {
    final controller = await createControllerWithThreadRecordsInternal(
      tester: tester,
      records: const <TaskThread>[],
      useFakeGatewayRuntime: true,
    );
    addTearDown(controller.dispose);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      platform: TargetPlatform.macOS,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-task-group-local')),
    );
    await pumpForUiSyncInternal(tester);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'assistant-task-item-',
            ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('assistant-new-task-button')));
    await pumpForUiSyncInternal(tester);

    await controller.refreshSessions();
    await pumpForUiSyncInternal(tester);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'assistant-task-item-',
            ),
      ),
      findsNWidgets(2),
    );

    final archiveButton = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith(
            'assistant-task-archive-draft:',
          ),
    );
    expect(archiveButton, findsOneWidget);

    await tester.tap(archiveButton);
    await pumpForUiSyncInternal(tester);

    expect(
      controller.settings.assistantArchivedTaskKeys.any(
        (item) => item.startsWith('draft:'),
      ),
      isTrue,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'assistant-task-item-',
            ),
      ),
      findsOneWidget,
    );

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      platform: TargetPlatform.macOS,
    );

    expect(find.text('当前 0'), findsOneWidget);
  }, skip: true);

  testWidgets('AssistantPage lets users rename task titles', (
    WidgetTester tester,
  ) async {
    final controller = await createControllerWithThreadRecordsInternal(
      tester: tester,
      records: const <TaskThread>[],
      useFakeGatewayRuntime: true,
    );
    addTearDown(controller.dispose);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-task-group-local')),
    );
    await pumpForUiSyncInternal(tester);

    await tester.longPress(
      find.byKey(const ValueKey<String>('assistant-task-item-main')),
    );
    await pumpForUiSyncInternal(tester);

    expect(
      find.byKey(const Key('assistant-task-rename-input')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('assistant-task-rename-input')),
      '研发任务',
    );
    await tester.tap(find.text('保存'));
    await pumpForUiSyncInternal(tester);
    await waitForConditionInternal(
      () => controller.settings.assistantCustomTaskTitles['main'] == '研发任务',
    );
    await pumpForUiSyncInternal(tester);

    expect(find.text('研发任务'), findsWidgets);
    expect(controller.settings.assistantCustomTaskTitles['main'], '研发任务');

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    expect(find.text('研发任务'), findsWidgets);
  }, skip: true);

  testWidgets('AssistantPage groups task rows by execution target', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(find.byKey(const Key('assistant-new-task-button')));
    await pumpForUiSyncInternal(tester);

    await controller.setAssistantExecutionTarget(
      AssistantExecutionTarget.singleAgent,
    );
    await pumpForUiSyncInternal(tester);

    await tester.tap(find.byKey(const Key('assistant-new-task-button')));
    await pumpForUiSyncInternal(tester);

    await controller.setAssistantExecutionTarget(
      AssistantExecutionTarget.remote,
    );
    await pumpForUiSyncInternal(tester);

    await tester.tap(find.byKey(const Key('assistant-new-task-button')));
    await pumpForUiSyncInternal(tester);

    final aiGroup = find.byKey(
      const ValueKey<String>('assistant-task-group-singleAgent'),
    );
    final localGroup = find.byKey(
      const ValueKey<String>('assistant-task-group-local'),
    );
    final remoteGroup = find.byKey(
      const ValueKey<String>('assistant-task-group-remote'),
    );

    expect(aiGroup, findsOneWidget);
    expect(localGroup, findsOneWidget);
    expect(remoteGroup, findsOneWidget);

    expect(
      tester.getTopLeft(aiGroup).dy,
      lessThan(tester.getTopLeft(localGroup).dy),
    );
    expect(
      tester.getTopLeft(localGroup).dy,
      lessThan(tester.getTopLeft(remoteGroup).dy),
    );
  }, skip: true);

  testWidgets('AssistantPage keeps the artifact pane collapsed until opened', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      platform: TargetPlatform.macOS,
    );

    expect(find.byKey(const Key('assistant-artifact-pane')), findsNothing);
    expect(
      find.byKey(const Key('assistant-artifact-pane-toggle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('assistant-artifact-pane-toggle')));
    await pumpForUiSyncInternal(tester);

    expect(find.byKey(const Key('assistant-artifact-pane')), findsOneWidget);

    final beforeWidth = tester
        .getSize(find.byKey(const Key('assistant-artifact-pane')))
        .width;
    await tester.drag(
      find.byKey(const Key('assistant-artifact-pane-resize-handle')),
      const Offset(-120, 0),
    );
    await pumpForUiSyncInternal(tester);
    final afterWidth = tester
        .getSize(find.byKey(const Key('assistant-artifact-pane')))
        .width;
    expect(afterWidth, greaterThan(beforeWidth));

    await tester.tap(find.byKey(const Key('assistant-artifact-pane-collapse')));
    await pumpForUiSyncInternal(tester);

    expect(find.byKey(const Key('assistant-artifact-pane')), findsNothing);
  });

  testWidgets(
    'AssistantPage keeps the collapsed artifact toggle clear of top toolbar controls',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
        platform: TargetPlatform.macOS,
      );

      final toggle = find.byKey(const Key('assistant-artifact-pane-toggle'));
      final viewMode = find.byKey(
        const Key('assistant-message-view-mode-button'),
      );
      final connectionChip = find.byKey(const Key('assistant-connection-chip'));

      expect(toggle, findsOneWidget);
      expect(viewMode, findsOneWidget);
      expect(connectionChip, findsOneWidget);

      final toggleRect = tester.getRect(toggle);
      final viewModeRect = tester.getRect(viewMode);
      final connectionRect = tester.getRect(connectionChip);

      expect(toggleRect.overlaps(viewModeRect), isFalse);
      expect(toggleRect.overlaps(connectionRect), isFalse);
    },
  );

  testWidgets('AssistantPage uses a compact collapsed artifact toggle', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      platform: TargetPlatform.macOS,
    );

    final toggle = find.byKey(const Key('assistant-artifact-pane-toggle'));
    final decoratedBody = find.descendant(
      of: toggle,
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.decoration is BoxDecoration,
      ),
    );

    expect(toggle, findsOneWidget);
    expect(tester.getSize(toggle), const Size(32, 36));

    final body = tester.widget<Container>(decoratedBody);
    final decoration = body.decoration! as BoxDecoration;

    expect(decoration.borderRadius, BorderRadius.circular(8));
  });

  testWidgets(
    'AssistantPage shows Single Agent provider selector on the right',
    (WidgetTester tester) async {},
    skip: true,
  );

  testWidgets('AssistantPage shows three collapsed task groups by default', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    expect(
      find.byKey(const ValueKey<String>('assistant-task-group-singleAgent')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('assistant-task-group-local')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('assistant-task-group-remote')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('assistant-task-item-main')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-task-group-local')),
    );
    await pumpForUiSyncInternal(tester);

    expect(
      find.byKey(const ValueKey<String>('assistant-task-item-main')),
      findsOneWidget,
    );
  });

  testWidgets('AssistantPage can switch unified side pane tabs and collapse', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(
        controller: controller,
        onOpenDetail: (_) {},
        navigationPanelBuilder: (_) => const ColoredBox(
          key: Key('assistant-nav-panel-probe'),
          color: Colors.red,
        ),
        showStandaloneTaskRail: false,
      ),
    );

    expect(find.byKey(const Key('assistant-side-pane')), findsOneWidget);
    expect(find.byKey(const Key('assistant-task-rail')), findsOneWidget);
    expect(find.byKey(const Key('assistant-nav-panel-probe')), findsNothing);

    await tester.tap(
      find.byKey(const Key('assistant-side-pane-tab-navigation')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assistant-nav-panel-probe')), findsOneWidget);

    await tester.tap(find.byKey(const Key('assistant-side-pane-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assistant-nav-panel-probe')), findsNothing);
    expect(find.byKey(const Key('assistant-side-pane')), findsOneWidget);
  });

  testWidgets(
    'AssistantPage shows ARIS chip when multi-agent ARIS is enabled',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      final multiAgentConfig = controller.settings.multiAgent.copyWith(
        enabled: true,
        framework: MultiAgentFramework.aris,
        arisEnabled: true,
      );
      await controller.settingsController.saveSnapshot(
        controller.settings.copyWith(multiAgent: multiAgentConfig),
      );
      controller.multiAgentOrchestrator.updateConfig(multiAgentConfig);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: Scaffold(
            body: AssistantPage(controller: controller, onOpenDetail: (_) {}),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ARIS'), findsWidgets);
    },
    skip: true,
  );

  testWidgets('AssistantPage narrow layout keeps existing single-pane flow', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      size: const Size(820, 900),
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    expect(find.byKey(const Key('assistant-task-rail')), findsNothing);
    expect(
      find.byKey(const Key('assistant-conversation-shell')),
      findsOneWidget,
    );
  });

  testWidgets('AssistantPage offline edit action opens gateway settings', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(find.text('编辑连接'));
    await tester.pumpAndSettle();

    expect(controller.destination, WorkspaceDestination.settings);
    expect(controller.settingsDetail, SettingsDetailPage.gatewayConnection);
  });
}
