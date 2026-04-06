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
import 'assistant_page_suite_core.dart';
import 'assistant_page_suite_support.dart';

void registerAssistantPageSuiteComposerTestsInternal() {
  Finder executionTargetMenuItemInternal(AssistantExecutionTarget target) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is PopupMenuItem<AssistantExecutionTarget> &&
          widget.value == target,
    );
  }

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

  testWidgets('AssistantPage keeps the default composer footprint compact', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    final composerShell = find.byKey(const Key('assistant-composer-shell'));

    expect(composerShell, findsOneWidget);
    expect(tester.getRect(composerShell).height, lessThan(210));
  });

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
      findsNothing,
    );
    expect(
      find.byKey(const Key('assistant-skill-picker-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-permission-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('assistant-thinking-button')), findsOneWidget);
    expect(find.byTooltip('模式'), findsNothing);

    await tester.tap(find.byKey(const Key('assistant-attachment-menu-button')));
    await pumpForUiSyncInternal(tester);

    expect(find.text('添加照片和文件'), findsOneWidget);
    expect(find.text('计划模式'), findsNothing);
    expect(find.text('连接网关'), findsNothing);
    expect(find.text('浏览器 / 编码 / 研究'), findsNothing);

    await tester.tapAt(const Offset(24, 24));
    await pumpForUiSyncInternal(tester);
  });

  testWidgets(
    'AssistantPage execution target menu shows only saved visible targets',
    (WidgetTester tester) async {
      late final AppController controller;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final store = createIsolatedTestStore(enableSecureStorage: false);
        final defaults = SettingsSnapshot.defaults();
        await store.saveSettingsSnapshot(
          defaults.copyWith(savedGatewayTargets: const <String>['remote']),
        );
        controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
        );
        final stopwatch = Stopwatch()..start();
        while (controller.initializing) {
          if (stopwatch.elapsed > const Duration(seconds: 10)) {
            fail('controller did not finish initializing before timeout');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      addTearDown(controller.dispose);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      );

      await tester.tap(
        find.byKey(const Key('assistant-execution-target-button')),
      );
      await pumpForUiSyncInternal(tester);

      expect(find.text('远程 OpenClaw Gateway'), findsWidgets);
      expect(find.text('本地 OpenClaw Gateway'), findsNothing);
      expect(
        executionTargetMenuItemInternal(AssistantExecutionTarget.auto),
        findsNothing,
      );
    },
  );

  testWidgets(
    'AssistantPage clears submitted composer text before send completes',
    (WidgetTester tester) async {
      late final PendingSendAppControllerInternal controller;
      final sendGate = Completer<void>();
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final store = createIsolatedTestStore(enableSecureStorage: false);
        controller = PendingSendAppControllerInternal(
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
    'AssistantPage submits from the selected task thread workspace after switching tasks',
    (WidgetTester tester) async {
      late final Directory tempDirectory;
      late final SecureConfigStore store;
      late final CaptureSendAppControllerInternal controller;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        tempDirectory = await Directory.systemTemp.createTemp(
          'xworkmate-assistant-page-thread-cwd-ui-',
        );
        store = SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async => '${tempDirectory.path}/settings.db',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
          defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
        );
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
            workspacePath: '${tempDirectory.path}/workspace-root',
          ),
        );
        await Directory(
          '${tempDirectory.path}/workspace-root',
        ).create(recursive: true);
        await Directory(
          '${tempDirectory.path}/thread-main',
        ).create(recursive: true);
        await Directory(
          '${tempDirectory.path}/thread-task',
        ).create(recursive: true);
        await store.saveTaskThreads(<TaskThread>[
          TaskThread(
            threadId: 'main',
            workspaceBinding: WorkspaceBinding(
              workspaceId: 'main',
              workspaceKind: WorkspaceKind.localFs,
              workspacePath: '${tempDirectory.path}/thread-main',
              displayPath: '${tempDirectory.path}/thread-main',
              writable: true,
            ),
            messages: const <GatewayChatMessage>[],
            updatedAtMs: 1,
            title: 'Main',
            archived: false,
            executionBinding: const ExecutionBinding(
              executionMode: ThreadExecutionMode.localAgent,
              executorId: 'auto',
              providerId: 'auto',
              endpointId: '',
            ),
            messageViewMode: AssistantMessageViewMode.rendered,
          ),
          TaskThread(
            threadId: 'draft:artifact-thread',
            workspaceBinding: WorkspaceBinding(
              workspaceId: 'draft:artifact-thread',
              workspaceKind: WorkspaceKind.localFs,
              workspacePath: '${tempDirectory.path}/thread-task',
              displayPath: '${tempDirectory.path}/thread-task',
              writable: true,
            ),
            messages: const <GatewayChatMessage>[],
            updatedAtMs: 2,
            title: 'Artifact Thread',
            archived: false,
            executionBinding: const ExecutionBinding(
              executionMode: ThreadExecutionMode.localAgent,
              executorId: 'auto',
              providerId: 'auto',
              endpointId: '',
            ),
            messageViewMode: AssistantMessageViewMode.rendered,
          ),
        ]);
        controller = CaptureSendAppControllerInternal(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
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
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      addTearDown(controller.dispose);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
        platform: TargetPlatform.macOS,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('assistant-task-group-singleAgent')),
      );
      await pumpForUiSyncInternal(tester);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('assistant-task-item-draft:artifact-thread'),
        ),
      );
      await pumpForUiSyncInternal(tester);

      expect(controller.currentSessionKey, 'draft:artifact-thread');

      final composerInput = find.descendant(
        of: find.byKey(const Key('assistant-composer-input-area')),
        matching: find.byType(TextField),
      );
      expect(composerInput, findsOneWidget);

      await tester.enterText(composerInput, '检查线程目录');
      await tester.tap(find.byKey(const Key('assistant-submit-button')));
      await pumpForUiSyncInternal(tester);

      expect(controller.sendCallCount, 1);
      expect(controller.lastSentMessage, contains('检查线程目录'));
      expect(controller.lastSessionKey, 'draft:artifact-thread');
      expect(controller.lastWorkspaceRef, '${tempDirectory.path}/thread-task');
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
        await writeSkillInternal(
          agentsRoot,
          'browser',
          skillName: 'Browser Automation',
          description: 'Browse websites',
        );
        await writeSkillInternal(
          customRootA,
          'ppt',
          skillName: 'PPT',
          description: 'Presentation skill',
        );
        await writeSkillInternal(
          customRootB,
          'wordx',
          skillName: 'WordX',
          description: 'Document skill',
        );

        controller = await createControllerWithThreadRecordsInternal(
          records: <TaskThread>[],
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
      await pumpForUiSyncInternal(tester);
      await tester.runAsync(() async {
        await waitForConditionInternal(
          () =>
              controller
                  .assistantImportedSkillsForSession(
                    controller.currentSessionKey,
                  )
                  .length ==
              3,
        );
      });
      await pumpForUiSyncInternal(tester);

      await tester.tap(find.byKey(const Key('assistant-skill-picker-button')));
      await pumpForUiSyncInternal(tester);

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
      await pumpForUiSyncInternal(tester);
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
      await pumpForUiSyncInternal(tester);
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
      await pumpForUiSyncInternal(tester);
      await tester.tap(
        find.byKey(ValueKey<String>('assistant-skill-option-${pptSkill.key}')),
      );
      await pumpForUiSyncInternal(tester);
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
      await pumpForUiSyncInternal(tester);
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
      await pumpForUiSyncInternal(tester);

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
      await pumpForUiSyncInternal(tester);
      await tester.tap(
        find.byKey(
          ValueKey<String>('assistant-skill-option-${wordxSkill.key}'),
        ),
      );
      await pumpForUiSyncInternal(tester);

      expect(
        find.byKey(
          ValueKey<String>('assistant-selected-skill-${wordxSkill.key}'),
        ),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await controller.switchSession('main');
      });
      await pumpForUiSyncInternal(tester);

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

  testWidgets(
    'AssistantPage hides Auto execution target even when the desktop feature flag is enabled',
    (WidgetTester tester) async {
      final manifest = UiFeatureManifest.fallback().copyWithFeature(
        platform: UiFeaturePlatform.desktop,
        module: 'assistant',
        feature: 'task_dialog_mode_auto',
        enabled: true,
        releaseTier: UiFeatureReleaseTier.stable,
      );
      late final AppController controller;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final store = createIsolatedTestStore(enableSecureStorage: false);
        final defaults = SettingsSnapshot.defaults();
        await store.saveSettingsSnapshot(
          defaults.copyWith(savedGatewayTargets: const <String>['remote']),
        );
        controller = AppController(
          store: store,
          runtimeCoordinator: RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          ),
          uiFeatureManifest: manifest,
        );
        final stopwatch = Stopwatch()..start();
        while (controller.initializing) {
          if (stopwatch.elapsed > const Duration(seconds: 10)) {
            fail('controller did not finish initializing before timeout');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      addTearDown(controller.dispose);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
        platform: TargetPlatform.macOS,
      );

      await tester.tap(
        find.byKey(const Key('assistant-execution-target-button')),
      );
      await pumpForUiSyncInternal(tester);

      expect(
        executionTargetMenuItemInternal(AssistantExecutionTarget.auto),
        findsNothing,
      );
      expect(find.text('远程 OpenClaw Gateway'), findsWidgets);
    },
  );

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
      final controller = await createControllerWithThreadRecordsInternal(
        records: <TaskThread>[],
        useFakeGatewayRuntime: true,
      );
      addTearDown(controller.dispose);

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

      await tester.tap(
        find.byKey(const ValueKey<String>('assistant-task-item-main')),
      );
      await pumpForUiSyncInternal(tester);

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
      await pumpForUiSyncInternal(tester);

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
      final controller = await createControllerWithThreadRecordsInternal(
        records: <TaskThread>[
          TaskThread(
            threadId: 'main',
            workspaceBinding: const WorkspaceBinding(
              workspaceId: 'main',
              workspaceKind: WorkspaceKind.localFs,
              workspacePath: '/tmp/main-thread',
              displayPath: '/tmp/main-thread',
              writable: true,
            ),
            title: '研发任务',
            archived: false,
            executionBinding: const ExecutionBinding(
              executionMode: ThreadExecutionMode.localAgent,
              executorId: 'auto',
              providerId: 'auto',
              endpointId: '',
            ),
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
        findsNothing,
      );
      expect(
        find.byKey(const Key('assistant-user-meta-context-toggle')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('assistant-user-meta-attachments-block')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('assistant-user-meta-context-block')),
        findsNothing,
      );

      final hoverGesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await hoverGesture.addPointer();
      await hoverGesture.moveTo(tester.getCenter(find.text('结合项目代码制作一份用户手册')));
      await pumpForUiSyncInternal(tester);

      expect(
        find.byKey(const Key('assistant-user-meta-attachments-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-user-meta-context-toggle')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('assistant-user-meta-attachments-toggle')),
      );
      await pumpForUiSyncInternal(tester);

      expect(
        find.byKey(const Key('assistant-user-meta-attachments-block')),
        findsOneWidget,
      );
      expect(find.text('Attached files:'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('assistant-user-meta-context-toggle')),
      );
      await pumpForUiSyncInternal(tester);

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
    final controller = await createControllerWithThreadRecordsInternal(
      records: <TaskThread>[
        TaskThread(
          threadId: 'main',
          workspaceBinding: const WorkspaceBinding(
            workspaceId: 'main',
            workspaceKind: WorkspaceKind.localFs,
            workspacePath: '/tmp/main-thread',
            displayPath: '/tmp/main-thread',
            writable: true,
          ),
          title: '研发任务',
          archived: false,
          executionBinding: const ExecutionBinding(
            executionMode: ThreadExecutionMode.localAgent,
            executorId: 'auto',
            providerId: 'auto',
            endpointId: '',
          ),
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
    await pumpForUiSyncInternal(tester);
    await tester.tap(find.text('RAW').last);
    await pumpForUiSyncInternal(tester);

    expect(
      controller.currentAssistantMessageViewMode,
      AssistantMessageViewMode.raw,
    );
    expect(find.byType(MarkdownBody), findsNothing);
  }, skip: true);
}

// Known flutter_tester host-exit hang in this widget scenario.
