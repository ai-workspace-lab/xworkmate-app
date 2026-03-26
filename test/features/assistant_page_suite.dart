@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

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

void main() {
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
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      platform: TargetPlatform.macOS,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-task-group-local')),
    );
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    await controller.refreshSessions();
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

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
    controller.dispose();
    await tester.pump();
  });

  testWidgets('AssistantPage lets users rename task titles', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-task-group-local')),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const ValueKey<String>('assistant-task-item-main')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('assistant-task-rename-input')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('assistant-task-rename-input')),
      '研发任务',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('研发任务'), findsWidgets);
    expect(controller.settings.assistantCustomTaskTitles['main'], '研发任务');

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    expect(find.text('研发任务'), findsWidgets);
  });

  testWidgets('AssistantPage groups task rows by execution target', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(find.byKey(const Key('assistant-new-task-button')));
    await _pumpForUiSync(tester);

    await controller.setAssistantExecutionTarget(
      AssistantExecutionTarget.singleAgent,
    );
    await _pumpForUiSync(tester);

    await tester.tap(find.byKey(const Key('assistant-new-task-button')));
    await _pumpForUiSync(tester);

    await controller.setAssistantExecutionTarget(
      AssistantExecutionTarget.remote,
    );
    await _pumpForUiSync(tester);

    await tester.tap(find.byKey(const Key('assistant-new-task-button')));
    await _pumpForUiSync(tester);

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
    await _pumpForUiSync(tester);

    expect(find.byKey(const Key('assistant-artifact-pane')), findsOneWidget);

    final beforeWidth = tester
        .getSize(find.byKey(const Key('assistant-artifact-pane')))
        .width;
    await tester.drag(
      find.byKey(const Key('assistant-artifact-pane-resize-handle')),
      const Offset(-120, 0),
    );
    await _pumpForUiSync(tester);
    final afterWidth = tester
        .getSize(find.byKey(const Key('assistant-artifact-pane')))
        .width;
    expect(afterWidth, greaterThan(beforeWidth));

    await tester.tap(find.byKey(const Key('assistant-artifact-pane-collapse')));
    await _pumpForUiSync(tester);

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
    await _pumpForUiSync(tester);

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

  testWidgets(
    'AssistantPage empty state stays above the composer instead of centering over the workspace',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      );

      final emptyState = find.byKey(const Key('assistant-empty-state-card'));
      final composerShell = find.byKey(const Key('assistant-composer-shell'));

      expect(emptyState, findsOneWidget);
      expect(composerShell, findsOneWidget);
      expect(
        tester.getRect(emptyState).bottom,
        lessThan(tester.getRect(composerShell).top),
      );
    },
  );

  testWidgets(
    'AssistantPage keeps composer controls above the safe bottom inset',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      const safeBottomInset = 36.0;

      await pumpPage(
        tester,
        child: Builder(
          builder: (context) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                padding: mediaQuery.padding.copyWith(bottom: safeBottomInset),
                viewPadding: mediaQuery.viewPadding.copyWith(
                  bottom: safeBottomInset,
                ),
              ),
              child: AssistantPage(
                controller: controller,
                onOpenDetail: (_) {},
              ),
            );
          },
        ),
      );

      final pageRect = tester.getRect(find.byType(AssistantPage));
      final composerShell = find.byKey(const Key('assistant-composer-shell'));
      final submitButton = find.byKey(const Key('assistant-submit-button'));

      expect(composerShell, findsOneWidget);
      expect(submitButton, findsOneWidget);
      expect(
        tester.getRect(composerShell).bottom,
        moreOrLessEquals(pageRect.bottom, epsilon: 1.01),
      );
      expect(
        tester.getRect(submitButton).bottom,
        lessThanOrEqualTo(
          tester.getRect(composerShell).bottom - safeBottomInset,
        ),
      );
    },
  );

  testWidgets('AssistantPage keeps a minimal composer action menu', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    expect(find.text('幻灯片'), findsNothing);
    expect(find.text('视频生成'), findsNothing);
    expect(find.text('深度研究'), findsNothing);
    expect(find.text('自动化'), findsNothing);
    expect(find.textContaining('输入需求、补充上下文'), findsOneWidget);
    expect(
      find.byKey(const Key('assistant-attachment-menu-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-execution-target-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-skill-picker-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-permission-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('assistant-model-button')), findsOneWidget);
    expect(find.byKey(const Key('assistant-thinking-button')), findsOneWidget);
    expect(find.byTooltip('模式'), findsNothing);

    await tester.tap(find.byKey(const Key('assistant-attachment-menu-button')));
    await _pumpForUiSync(tester);

    expect(find.text('添加照片和文件'), findsOneWidget);
    expect(find.text('计划模式'), findsNothing);
    expect(find.text('连接网关'), findsNothing);
    expect(find.text('浏览器 / 编码 / 研究'), findsNothing);

    await tester.tapAt(const Offset(24, 24));
    await _pumpForUiSync(tester);

    await tester.tap(
      find.byKey(const Key('assistant-execution-target-button')),
    );
    await _pumpForUiSync(tester);

    expect(find.text('单机智能体'), findsWidgets);
    expect(find.text('本地 OpenClaw Gateway'), findsWidgets);
    expect(find.text('远程 OpenClaw Gateway'), findsWidgets);
  });

  testWidgets(
    'AssistantPage clears submitted composer text before send completes',
    (WidgetTester tester) async {
      late final _PendingSendAppController controller;
      final sendGate = Completer<void>();
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final store = createIsolatedTestStore(enableSecureStorage: false);
        controller = _PendingSendAppController(
          store: store,
          sendGate: sendGate,
        );
        final stopwatch = Stopwatch()..start();
        while (controller.initializing) {
          if (stopwatch.elapsed > const Duration(seconds: 10)) {
            fail('controller did not finish initializing before timeout');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      addTearDown(() async {
        if (!sendGate.isCompleted) {
          sendGate.complete();
        }
      });
      addTearDown(controller.dispose);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
        platform: TargetPlatform.macOS,
      );

      final composerInput = find.descendant(
        of: find.byKey(const Key('assistant-composer-input-area')),
        matching: find.byType(TextField),
      );
      expect(composerInput, findsOneWidget);

      await tester.enterText(composerInput, '分析一下这个 bug');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(controller.sendCallCount, 1);
      expect(controller.lastSentMessage, isNotEmpty);
      expect(tester.widget<TextField>(composerInput).controller?.text, isEmpty);

      sendGate.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'AssistantPage shows a persistent skill popover in single-agent mode and keeps thread selections isolated',
    (WidgetTester tester) async {
      late final Directory tempDirectory;
      late final AppController controller;
      await tester.runAsync(() async {
        tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-assistant-skills-ui-',
        );
        final agentsRoot = Directory('${tempDirectory.path}/agents-skills');
        final customRootA = Directory('${tempDirectory.path}/custom-skills-a');
        final customRootB = Directory('${tempDirectory.path}/custom-skills-b');
        await _writeSkill(
          agentsRoot,
          'browser',
          skillName: 'Browser Automation',
          description: 'Browse websites',
        );
        await _writeSkill(
          customRootA,
          'ppt',
          skillName: 'PPT',
          description: 'Presentation skill',
        );
        await _writeSkill(
          customRootB,
          'wordx',
          skillName: 'WordX',
          description: 'Document skill',
        );

        controller = await _createControllerWithThreadRecords(
          records: const <AssistantThreadRecord>[],
          useFakeGatewayRuntime: true,
          singleAgentSharedSkillScanRootOverrides: <String>[
            agentsRoot.path,
            customRootA.path,
            customRootB.path,
          ],
        );
      });
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      addTearDown(controller.dispose);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
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
      await _pumpForUiSync(tester);
      await tester.runAsync(() async {
        await _waitForCondition(
          () =>
              controller
                  .assistantImportedSkillsForSession(
                    controller.currentSessionKey,
                  )
                  .length ==
              3,
        );
      });
      await _pumpForUiSync(tester);

      await tester.tap(find.byKey(const Key('assistant-skill-picker-button')));
      await _pumpForUiSync(tester);

      expect(
        find.byKey(const Key('assistant-skill-picker-popover')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-skill-picker-dialog')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const Key('assistant-skill-picker-search')),
        'browser',
      );
      await _pumpForUiSync(tester);
      expect(find.text('Browser Automation'), findsOneWidget);
      expect(find.text('PPT'), findsNothing);

      final browserSkill = controller
          .assistantImportedSkillsForSession(controller.currentSessionKey)
          .firstWhere((skill) => skill.label == 'Browser Automation');
      final pptSkill = controller
          .assistantImportedSkillsForSession(controller.currentSessionKey)
          .firstWhere((skill) => skill.label == 'PPT');
      final wordxSkill = controller
          .assistantImportedSkillsForSession(controller.currentSessionKey)
          .firstWhere((skill) => skill.label == 'WordX');

      await tester.tap(
        find.byKey(
          ValueKey<String>('assistant-skill-option-${browserSkill.key}'),
        ),
      );
      await _pumpForUiSync(tester);
      expect(
        find.byKey(const Key('assistant-skill-picker-popover')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey<String>('assistant-selected-skill-${browserSkill.key}'),
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('assistant-skill-picker-search')),
        '',
      );
      await _pumpForUiSync(tester);
      await tester.tap(
        find.byKey(ValueKey<String>('assistant-skill-option-${pptSkill.key}')),
      );
      await _pumpForUiSync(tester);
      expect(
        find.byKey(const Key('assistant-skill-picker-popover')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey<String>('assistant-selected-skill-${pptSkill.key}'),
        ),
        findsOneWidget,
      );

      await tester.tapAt(const Offset(24, 24));
      await _pumpForUiSync(tester);
      expect(
        find.byKey(const Key('assistant-skill-picker-popover')),
        findsNothing,
      );

      controller.initializeAssistantThreadContext(
        'draft:task-b',
        title: 'Task B',
        executionTarget: AssistantExecutionTarget.singleAgent,
        messageViewMode: AssistantMessageViewMode.rendered,
      );
      await tester.runAsync(() async {
        await controller.switchSession('draft:task-b');
      });
      await _pumpForUiSync(tester);

      expect(
        find.byKey(
          ValueKey<String>('assistant-selected-skill-${browserSkill.key}'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          ValueKey<String>('assistant-selected-skill-${pptSkill.key}'),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('assistant-skill-picker-button')));
      await _pumpForUiSync(tester);
      await tester.tap(
        find.byKey(
          ValueKey<String>('assistant-skill-option-${wordxSkill.key}'),
        ),
      );
      await _pumpForUiSync(tester);

      expect(
        find.byKey(
          ValueKey<String>('assistant-selected-skill-${wordxSkill.key}'),
        ),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await controller.switchSession('main');
      });
      await _pumpForUiSync(tester);

      expect(
        find.byKey(
          ValueKey<String>('assistant-selected-skill-${browserSkill.key}'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey<String>('assistant-selected-skill-${pptSkill.key}'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey<String>('assistant-selected-skill-${wordxSkill.key}'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('AssistantPage hides gated attachment and multi-agent actions', (
    WidgetTester tester,
  ) async {
    final manifest = UiFeatureManifest.fallback()
        .copyWithFeature(
          platform: UiFeaturePlatform.desktop,
          module: 'assistant',
          feature: 'file_attachments',
          enabled: false,
        )
        .copyWithFeature(
          platform: UiFeaturePlatform.desktop,
          module: 'assistant',
          feature: 'multi_agent',
          enabled: false,
        );
    final controller = await createTestController(
      tester,
      uiFeatureManifest: manifest,
    );

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      platform: TargetPlatform.macOS,
    );

    expect(
      find.byKey(const Key('assistant-attachment-menu-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('assistant-collaboration-toggle')),
      findsNothing,
    );
  });

  testWidgets('AssistantPage composer input area can be resized vertically', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    final inputArea = find.byKey(const Key('assistant-composer-input-area'));
    final resizeHandle = find.byKey(
      const Key('assistant-composer-resize-handle'),
    );
    final conversationShell = find.byKey(
      const Key('assistant-conversation-shell'),
    );
    final composerShell = find.byKey(const Key('assistant-composer-shell'));

    expect(inputArea, findsOneWidget);
    expect(resizeHandle, findsOneWidget);
    expect(conversationShell, findsOneWidget);
    expect(composerShell, findsOneWidget);

    final initialHeight = tester.getSize(inputArea).height;
    final initialComposerHeight = tester.getRect(composerShell).height;
    final initialConversationHeight = tester.getRect(conversationShell).height;

    await tester.drag(resizeHandle, const Offset(0, 40));
    await tester.pumpAndSettle();

    final expandedHeight = tester.getSize(inputArea).height;
    final expandedComposerHeight = tester.getRect(composerShell).height;
    final expandedConversationHeight = tester.getRect(conversationShell).height;

    expect(expandedHeight, greaterThan(initialHeight));
    expect(expandedComposerHeight, greaterThan(initialComposerHeight));
    expect(expandedConversationHeight, lessThan(initialConversationHeight));
  });

  testWidgets('AssistantPage workspace split can be resized vertically', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    final resizeHandle = find.byKey(
      const Key('assistant-workspace-resize-handle'),
    );
    final conversationShell = find.byKey(
      const Key('assistant-conversation-shell'),
    );
    final composerShell = find.byKey(const Key('assistant-composer-shell'));

    expect(resizeHandle, findsOneWidget);
    expect(conversationShell, findsOneWidget);
    expect(composerShell, findsOneWidget);

    final initialComposerHeight = tester.getRect(composerShell).height;
    final initialConversationHeight = tester.getRect(conversationShell).height;

    await tester.drag(resizeHandle, const Offset(0, 40));
    await tester.pumpAndSettle();

    final shrunkComposerHeight = tester.getRect(composerShell).height;
    final expandedConversationHeight = tester.getRect(conversationShell).height;

    expect(shrunkComposerHeight, lessThan(initialComposerHeight));
    expect(expandedConversationHeight, greaterThan(initialConversationHeight));
  });

  testWidgets(
    'AssistantPage keeps all three panes tightly packed after resize',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
        platform: TargetPlatform.macOS,
      );

      final pageRect = tester.getRect(find.byType(AssistantPage));
      final taskRail = find.byKey(const Key('assistant-task-rail'));
      final horizontalHandle = find.byType(PaneResizeHandle).first;
      final verticalHandle = find.byKey(
        const Key('assistant-workspace-resize-handle'),
      );
      final conversationShell = find.byKey(
        const Key('assistant-conversation-shell'),
      );
      final composerShell = find.byKey(const Key('assistant-composer-shell'));

      await tester.drag(horizontalHandle, const Offset(360, 0));
      await tester.pumpAndSettle();
      await tester.drag(verticalHandle, const Offset(0, 260));
      await tester.pumpAndSettle();

      final taskRailRect = tester.getRect(taskRail);
      final horizontalHandleRect = tester.getRect(horizontalHandle);
      final conversationRect = tester.getRect(conversationShell);
      final verticalHandleRect = tester.getRect(verticalHandle);
      final composerRect = tester.getRect(composerShell);

      expect(taskRailRect.left, moreOrLessEquals(pageRect.left, epsilon: 0.01));
      expect(
        taskRailRect.right,
        moreOrLessEquals(horizontalHandleRect.left, epsilon: 0.01),
      );
      expect(
        horizontalHandleRect.right,
        moreOrLessEquals(conversationRect.left, epsilon: 4.01),
      );
      expect(
        conversationRect.top,
        moreOrLessEquals(pageRect.top, epsilon: 1.01),
      );
      expect(
        conversationRect.bottom,
        moreOrLessEquals(verticalHandleRect.top, epsilon: 0.01),
      );
      expect(
        verticalHandleRect.bottom,
        moreOrLessEquals(composerRect.top, epsilon: 0.01),
      );
      expect(
        composerRect.bottom,
        moreOrLessEquals(pageRect.bottom, epsilon: 1.01),
      );
      expect(
        composerRect.right,
        moreOrLessEquals(pageRect.right, epsilon: 1.01),
      );
      expect(conversationRect.width, greaterThan(620));
      expect(conversationRect.height, greaterThanOrEqualTo(180));
      expect(composerRect.height, greaterThanOrEqualTo(124));
    },
  );

  // Known flutter_tester host-exit hang in this widget scenario.
  testWidgets(
    'AssistantPage syncs task selection with execution target menu and connection chip',
    (WidgetTester tester) async {
      final controller = await _createControllerWithThreadRecords(
        records: const <AssistantThreadRecord>[],
        useFakeGatewayRuntime: true,
      );
      addTearDown(controller.dispose);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      );

      await tester.tap(find.byKey(const Key('assistant-new-task-button')));
      await _pumpForUiSync(tester);

      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await _pumpForUiSync(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('assistant-task-item-main')),
      );
      await _pumpForUiSync(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('assistant-execution-target-button')),
          matching: find.text('本地 OpenClaw Gateway'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('离线 · 未连接目标'), findsOneWidget);

      final aiThreadItem = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'assistant-task-item-draft:',
            ),
      );
      expect(aiThreadItem, findsOneWidget);

      await tester.tap(aiThreadItem);
      await _pumpForUiSync(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('assistant-execution-target-button')),
          matching: find.text('单机智能体'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('单机智能体'), findsWidgets);
    },
    skip: true,
  );

  testWidgets('AssistantPage shows thread-level message view chip', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    expect(
      find.byKey(const Key('assistant-message-view-mode-button')),
      findsOneWidget,
    );
    expect(find.text('渲染'), findsOneWidget);
  });

  testWidgets(
    'AssistantPage keeps attached files and execution context collapsed by default',
    (WidgetTester tester) async {
      final controller = await _createControllerWithThreadRecords(
        records: const <AssistantThreadRecord>[
          AssistantThreadRecord(
            sessionKey: 'main',
            title: '研发任务',
            archived: false,
            executionTarget: AssistantExecutionTarget.singleAgent,
            messageViewMode: AssistantMessageViewMode.raw,
            updatedAtMs: 1700000000000,
            messages: <GatewayChatMessage>[
              GatewayChatMessage(
                id: 'user-1',
                role: 'user',
                text:
                    'Attached files:\n'
                    '- clipboard-image-1.png\n\n'
                    'Preferred skills:\n'
                    '- xiaohongshu\n'
                    '- code-quality-gate\n\n'
                    'Execution context:\n'
                    '- target: single-agent\n'
                    '- provider: codex\n'
                    '- workspace_root: /opt/data/workspace\n'
                    '- permission: full-access\n\n'
                    '结合项目代码制作一份用户手册',
                timestampMs: 1700000000000,
                toolCallId: null,
                toolName: null,
                stopReason: null,
                pending: false,
                error: false,
              ),
            ],
          ),
        ],
        useFakeGatewayRuntime: true,
      );
      addTearDown(controller.dispose);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      );

      expect(find.text('结合项目代码制作一份用户手册'), findsOneWidget);
      expect(find.text('Preferred skills:'), findsNothing);
      expect(find.text('xiaohongshu'), findsNothing);
      expect(find.text('code-quality-gate'), findsNothing);
      expect(
        find.byKey(const Key('assistant-user-meta-attachments-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-user-meta-context-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-user-meta-attachments-block')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('assistant-user-meta-context-block')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('assistant-user-meta-attachments-toggle')),
      );
      await _pumpForUiSync(tester);

      expect(
        find.byKey(const Key('assistant-user-meta-attachments-block')),
        findsOneWidget,
      );
      expect(find.text('Attached files:'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('assistant-user-meta-context-toggle')),
      );
      await _pumpForUiSync(tester);

      expect(
        find.byKey(const Key('assistant-user-meta-context-block')),
        findsOneWidget,
      );
      expect(find.text('Preferred skills:'), findsOneWidget);
      expect(find.text('xiaohongshu'), findsOneWidget);
      expect(find.text('code-quality-gate'), findsOneWidget);
      expect(find.text('Execution context:'), findsOneWidget);
    },
    // Known flutter_tester host-exit hang in this widget scenario.
    skip: true,
  );

  // Known flutter_tester host-exit hang in this widget scenario.
  testWidgets('AssistantPage toggles Markdown Rendered and RAW per thread', (
    WidgetTester tester,
  ) async {
    final controller = await _createControllerWithThreadRecords(
      records: const <AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'main',
          title: '研发任务',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          updatedAtMs: 1700000000000,
          messages: <GatewayChatMessage>[
            GatewayChatMessage(
              id: 'user-1',
              role: 'user',
              text: '请看这个清单',
              timestampMs: 1700000000000,
              toolCallId: null,
              toolName: null,
              stopReason: null,
              pending: false,
              error: false,
            ),
            GatewayChatMessage(
              id: 'assistant-1',
              role: 'assistant',
              text: '## 标题\\n\\n- 第一项\\n- 第二项',
              timestampMs: 1700000001000,
              toolCallId: null,
              toolName: null,
              stopReason: null,
              pending: false,
              error: false,
            ),
          ],
        ),
      ],
      useFakeGatewayRuntime: true,
    );
    addTearDown(controller.dispose);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    expect(find.byType(MarkdownBody), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('assistant-message-view-mode-button')),
    );
    await _pumpForUiSync(tester);
    await tester.tap(find.text('RAW').last);
    await _pumpForUiSync(tester);

    expect(
      controller.currentAssistantMessageViewMode,
      AssistantMessageViewMode.raw,
    );
    expect(find.byType(MarkdownBody), findsNothing);
  }, skip: true);

  // Known flutter_tester host-exit hang in this widget scenario.
  testWidgets(
    'AssistantPage shows Single Agent chip and keeps task rows minimal',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      await controller.settingsController.saveAiGatewayApiKey('live-key');
      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: 'http://127.0.0.1:11434/v1',
            availableModels: const <String>['qwen2.5-coder:latest'],
            selectedModels: const <String>['qwen2.5-coder:latest'],
          ),
          defaultModel: 'qwen2.5-coder:latest',
          assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
        ),
        refreshAfterSave: false,
      );

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      );

      expect(
        find.byKey(const Key('assistant-connection-chip')),
        findsOneWidget,
      );
      expect(
        find.text('Auto · qwen2.5-coder:latest · 127.0.0.1:11434'),
        findsOneWidget,
      );
      expect(find.text('等待描述这个任务的第一条消息'), findsNothing);

      await tester.tap(find.byKey(const Key('assistant-new-task-button')));
      await tester.pumpAndSettle();

      expect(find.text('等待描述这个任务的第一条消息'), findsNothing);
    },
    skip: true,
  );
}

Future<AppController> _createControllerWithThreadRecords({
  WidgetTester? tester,
  required List<AssistantThreadRecord> records,
  bool useFakeGatewayRuntime = false,
  List<String>? singleAgentSharedSkillScanRootOverrides,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final tempDirectory = await Directory.systemTemp.createTemp(
    'xworkmate-assistant-page-tests-',
  );
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '${tempDirectory.path}/settings.db',
    fallbackDirectoryPathResolver: () async => tempDirectory.path,
    defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
  );
  addTearDown(() async {
    if (await tempDirectory.exists()) {
      try {
        await tempDirectory.delete(recursive: true);
      } catch (_) {}
    }
  });
  final defaults = SettingsSnapshot.defaults();
  await store.saveSettingsSnapshot(
    defaults.copyWith(
      gatewayProfiles: replaceGatewayProfileAt(
        replaceGatewayProfileAt(
          defaults.gatewayProfiles,
          kGatewayLocalProfileIndex,
          defaults.primaryLocalGatewayProfile.copyWith(
            host: '127.0.0.1',
            port: 9,
            tls: false,
          ),
        ),
        kGatewayRemoteProfileIndex,
        defaults.primaryRemoteGatewayProfile.copyWith(
          host: '127.0.0.1',
          port: 9,
          tls: false,
        ),
      ),
      aiGateway: defaults.aiGateway.copyWith(
        baseUrl: 'http://127.0.0.1:11434/v1',
        availableModels: const <String>['qwen2.5-coder:latest'],
        selectedModels: const <String>['qwen2.5-coder:latest'],
      ),
      assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
      defaultModel: 'qwen2.5-coder:latest',
      workspacePath: tempDirectory.path,
    ),
  );
  await store.saveAssistantThreadRecords(records);
  final controller = AppController(
    store: store,
    runtimeCoordinator: useFakeGatewayRuntime
        ? RuntimeCoordinator(
            gateway: _FakeGatewayRuntime(store: store),
            codex: _FakeCodexRuntime(),
          )
        : null,
    singleAgentSharedSkillScanRootOverrides:
        singleAgentSharedSkillScanRootOverrides,
  );
  final stopwatch = Stopwatch()..start();
  while (controller.initializing) {
    if (stopwatch.elapsed > const Duration(seconds: 10)) {
      fail('controller did not finish initializing before timeout');
    }
    if (tester != null) {
      await tester.pump(const Duration(milliseconds: 20));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
  return controller;
}

Future<void> _writeSkill(
  Directory root,
  String folderName, {
  required String skillName,
  required String description,
}) async {
  final directory = Directory('${root.path}/$folderName');
  await directory.create(recursive: true);
  await File(
    '${directory.path}/SKILL.md',
  ).writeAsString('---\nname: $skillName\ndescription: $description\n---\n');
}

Future<void> _pumpForUiSync(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _waitForCondition(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _PendingSendAppController extends AppController {
  _PendingSendAppController({
    required SecureConfigStore store,
    required this.sendGate,
  }) : super(
         store: store,
         runtimeCoordinator: RuntimeCoordinator(
           gateway: _FakeGatewayRuntime(store: store),
           codex: _FakeCodexRuntime(),
         ),
       );

  final Completer<void> sendGate;
  int sendCallCount = 0;
  String lastSentMessage = '';

  @override
  Future<void> sendChatMessage(
    String message, {
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<CollaborationAttachment> localAttachments =
        const <CollaborationAttachment>[],
    List<String> selectedSkillLabels = const <String>[],
  }) async {
    sendCallCount += 1;
    lastSentMessage = message;
    await sendGate.future;
  }
}

class _FakeGatewayRuntime extends GatewayRuntime {
  _FakeGatewayRuntime({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();

  @override
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Stream<GatewayPushEvent> get events => const Stream<GatewayPushEvent>.empty();

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connected,
      statusText: 'Connected',
      remoteAddress: '${profile.host}:${profile.port}',
      connectAuthMode: 'none',
    );
    notifyListeners();
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    _snapshot = _snapshot.copyWith(
      status: RuntimeConnectionStatus.offline,
      statusText: 'Offline',
      remoteAddress: null,
      clearLastError: true,
      clearLastErrorCode: true,
      clearLastErrorDetailCode: true,
    );
    notifyListeners();
  }

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    switch (method) {
      case 'health':
      case 'status':
        return <String, dynamic>{'ok': true};
      case 'agents.list':
        return <String, dynamic>{'agents': const <Object>[], 'mainKey': 'main'};
      case 'sessions.list':
        return <String, dynamic>{'sessions': const <Object>[]};
      case 'chat.history':
        return <String, dynamic>{'messages': const <Object>[]};
      case 'skills.status':
        return <String, dynamic>{'skills': const <Object>[]};
      case 'channels.status':
        return <String, dynamic>{
          'channelMeta': const <Object>[],
          'channelLabels': const <String, dynamic>{},
          'channelDetailLabels': const <String, dynamic>{},
          'channelAccounts': const <String, dynamic>{},
          'channelOrder': const <Object>[],
        };
      case 'models.list':
        return <String, dynamic>{'models': const <Object>[]};
      case 'cron.list':
        return <String, dynamic>{'jobs': const <Object>[]};
      case 'device.pair.list':
        return <String, dynamic>{
          'pending': const <Object>[],
          'paired': const <Object>[],
        };
      case 'system-presence':
        return const <Object>[];
      default:
        return <String, dynamic>{};
    }
  }
}

class _FakeCodexRuntime extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}
