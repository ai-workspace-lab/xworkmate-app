import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';

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
}
