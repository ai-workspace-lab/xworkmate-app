import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/tasks/tasks_page.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  testWidgets('TasksPage new task button routes back to assistant', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.navigateTo(WorkspaceDestination.tasks);

    await pumpPage(
      tester,
      child: TasksPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(find.text('新建任务'));
    await tester.pumpAndSettle();

    expect(controller.destination, WorkspaceDestination.assistant);
  });
}
