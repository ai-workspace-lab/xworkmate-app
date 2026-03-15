import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';

import '../test_support.dart';

void main() {
  testWidgets('AssistantPage desktop shows thread rail and creates draft thread', (
    WidgetTester tester,
  ) async {
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
  });

  testWidgets('AssistantPage narrow layout keeps existing single-pane flow', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await pumpPage(
      tester,
      size: const Size(1000, 900),
      child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
    );

    expect(find.byKey(const Key('assistant-task-rail')), findsNothing);
    expect(find.byKey(const Key('assistant-conversation-title')), findsOneWidget);
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
