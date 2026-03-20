import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
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

  // Known flutter_tester host-exit hang in this widget scenario.
  testWidgets('AssistantPage groups task rows by execution target', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    await controller.saveSettings(
      controller.settings.copyWith(
        assistantExecutionTarget: AssistantExecutionTarget.aiGatewayOnly,
      ),
      refreshAfterSave: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const Key('assistant-new-task-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await controller.saveSettings(
      controller.settings.copyWith(
        assistantExecutionTarget: AssistantExecutionTarget.remote,
      ),
      refreshAfterSave: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const Key('assistant-new-task-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

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

  testWidgets('AssistantPage offline submit control opens gateway dialog', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(find.byTooltip('连接'));
    await tester.pumpAndSettle();

    expect(find.text('Gateway 访问'), findsOneWidget);
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
    await tester.pumpAndSettle();

    expect(find.text('添加照片和文件'), findsOneWidget);
    expect(find.text('计划模式'), findsNothing);
    expect(find.text('连接网关'), findsNothing);
    expect(find.text('浏览器 / 编码 / 研究'), findsNothing);

    await tester.tapAt(const Offset(24, 24));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('assistant-execution-target-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('仅 AI Gateway'), findsOneWidget);
    expect(find.text('本地 OpenClaw Gateway'), findsWidgets);
    expect(find.text('远程 OpenClaw Gateway'), findsOneWidget);

    await tester.tap(find.text('仅 AI Gateway').last);
    await tester.pumpAndSettle();

    expect(
      controller.assistantExecutionTarget,
      AssistantExecutionTarget.aiGatewayOnly,
    );

    await tester.tapAt(const Offset(24, 24));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('assistant-skill-picker-button')),
    );
    await tester.tap(find.byKey(const Key('assistant-skill-picker-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('assistant-skill-picker-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assistant-skill-picker-search')),
      findsOneWidget,
    );
    expect(find.text('1password'), findsOneWidget);
    expect(find.text('xlsx'), findsOneWidget);
    expect(find.text('网页处理'), findsOneWidget);
  });

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
