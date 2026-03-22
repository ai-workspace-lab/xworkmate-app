@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/skills/skills_page.dart';
import 'package:xworkmate/models/app_models.dart';

import '../test_support.dart';

void main() {
  testWidgets('SkillsPage routes back to assistant from toolbar', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.navigateTo(WorkspaceDestination.skills);

    await pumpPage(
      tester,
      child: SkillsPage(controller: controller, onOpenDetail: (_) {}),
    );

    await tester.tap(find.text('回到对话使用'));
    await tester.pumpAndSettle();

    expect(controller.destination, WorkspaceDestination.assistant);
  });

  testWidgets('SkillsPage keeps workspace split layout', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);
    controller.navigateTo(WorkspaceDestination.skills);

    await pumpPage(
      tester,
      child: SkillsPage(controller: controller, onOpenDetail: (_) {}),
    );

    expect(find.text('技能列表'), findsOneWidget);
    expect(find.text('选择左侧技能查看详情。'), findsOneWidget);
  });
}
