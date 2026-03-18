import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/tasks/tasks_page.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  testWidgets('TasksPage continue button routes back to assistant', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.navigateTo(WorkspaceDestination.tasks);

    await pumpPage(
      tester,
      child: TasksPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(find.text('继续对话'));
    await tester.pumpAndSettle();

    expect(controller.destination, WorkspaceDestination.assistant);
  });

  testWidgets('TasksPage scheduled tab is read-only', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.navigateTo(WorkspaceDestination.tasks);

    await pumpPage(
      tester,
      child: TasksPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(find.text('计划中').first);
    await tester.pumpAndSettle();

    expect(find.text('计划任务只读'), findsOneWidget);
    expect(find.text('当前没有计划任务。'), findsOneWidget);
  });

  testWidgets('TasksPage keeps list/detail workspace structure', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.navigateTo(WorkspaceDestination.tasks);

    await pumpPage(
      tester,
      child: TasksPage(controller: controller, onOpenDetail: (_) {}),
    );

    expect(find.text('任务列表'), findsOneWidget);
    expect(find.text('选择左侧任务查看详情。'), findsOneWidget);
  });
}
