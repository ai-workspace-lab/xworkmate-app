import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

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
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'assistant-task-item-',
            ),
      ),
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
}
