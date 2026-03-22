@TestOn('vm')
library;

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
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'AssistantPage desktop shows thread rail and creates draft thread',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
        platform: TargetPlatform.macOS,
      );

      expect(find.byKey(const Key('assistant-task-rail')), findsOneWidget);

      final titleBefore = tester.widget<Text>(
        find.byKey(const Key('assistant-conversation-title')),
      );
      expect(titleBefore.data, '默认任务');

      await tester.tap(find.byKey(const Key('assistant-new-task-button')));
      await tester.pumpAndSettle();

      final titleAfter = tester.widget<Text>(
        find.byKey(const Key('assistant-conversation-title')),
      );
      expect(titleAfter.data, '新对话');
    },
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
  });

  testWidgets('AssistantPage lets users rename task titles', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

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
    expect(
      tester
          .widget<Text>(find.byKey(const Key('assistant-conversation-title')))
          .data,
      '研发任务',
    );
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
      AssistantExecutionTarget.aiGatewayOnly,
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
      const ValueKey<String>('assistant-task-group-aiGatewayOnly'),
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
      find.byKey(const Key('assistant-conversation-title')),
      findsOneWidget,
    );
  });

  testWidgets('AssistantPage offline submit control opens gateway settings', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(find.byTooltip('连接'));
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
    expect(find.textContaining('输入需求、补充上下文、继续追问'), findsOneWidget);
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

    expect(find.text('仅 AI Gateway'), findsOneWidget);
    expect(find.text('本地 OpenClaw Gateway'), findsWidgets);
    expect(find.text('远程 OpenClaw Gateway'), findsOneWidget);

    await tester.tap(find.text('仅 AI Gateway').last);
    await _pumpForUiSync(tester);

    expect(
      controller.assistantExecutionTarget,
      AssistantExecutionTarget.aiGatewayOnly,
    );
  });

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
        AssistantExecutionTarget.aiGatewayOnly,
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
          matching: find.text('仅 AI Gateway'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('仅 AI Gateway'), findsWidgets);
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
          executionTarget: AssistantExecutionTarget.aiGatewayOnly,
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
    'AssistantPage shows AI Gateway-only chip and keeps task rows minimal',
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
          assistantExecutionTarget: AssistantExecutionTarget.aiGatewayOnly,
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
        find.text('仅 AI Gateway · qwen2.5-coder:latest · 127.0.0.1:11434'),
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
  required List<AssistantThreadRecord> records,
  bool useFakeGatewayRuntime = false,
  List<String>? gatewayOnlySkillScanRoots,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final tempDirectory = await Directory.systemTemp.createTemp(
    'xworkmate-assistant-page-tests-',
  );
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '${tempDirectory.path}/settings.db',
    fallbackDirectoryPathResolver: () async => tempDirectory.path,
  );
  await store.saveSettingsSnapshot(
    SettingsSnapshot.defaults().copyWith(
      aiGateway: SettingsSnapshot.defaults().aiGateway.copyWith(
        baseUrl: 'http://127.0.0.1:11434/v1',
        availableModels: const <String>['qwen2.5-coder:latest'],
        selectedModels: const <String>['qwen2.5-coder:latest'],
      ),
      assistantExecutionTarget: AssistantExecutionTarget.aiGatewayOnly,
      defaultModel: 'qwen2.5-coder:latest',
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
    gatewayOnlySkillScanRoots: gatewayOnlySkillScanRoots,
  );
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (controller.initializing) {
    if (DateTime.now().isAfter(deadline)) {
      fail('controller did not finish initializing before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return controller;
}

Future<void> _pumpForUiSync(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
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
