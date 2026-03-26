@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/modules/modules_page.dart';
import 'package:xworkmate/features/settings/settings_page.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

import '../test_support.dart';

void main() {
  testWidgets(
    'Modules gateway shortcut routes to Settings center and modules page excludes the old gateway tab',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      controller.openModules(tab: ModulesTab.gateway);

      expect(controller.destination, WorkspaceDestination.settings);
      expect(controller.settingsTab, SettingsTab.gateway);

      await pumpPage(
        tester,
        child: SettingsPage(
          controller: controller,
          initialTab: controller.settingsTab,
          initialDetail: controller.settingsDetail,
          navigationContext: controller.settingsNavigationContext,
        ),
      );

      expect(find.text('OpenClaw Gateway'), findsWidgets);

      controller.navigateTo(WorkspaceDestination.nodes);
      await pumpPage(
        tester,
        child: ModulesPage(controller: controller, onOpenDetail: (_) {}),
      );

      expect(find.text('ClawHub'), findsNothing);
      expect(find.text('连接器'), findsNothing);

      await tester.tap(find.text('打开设置中心'));
      await tester.pumpAndSettle();
      expect(controller.destination, WorkspaceDestination.settings);
      expect(controller.settingsTab, SettingsTab.gateway);
      expect(controller.settingsDetail, isNull);
    },
  );

  testWidgets('ModulesPage skill tab shows three execution mode cards', (
    WidgetTester tester,
  ) async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'xworkmate-modules-page-skills-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    await _writeSkill(
      Directory('${tempDirectory.path}/custom-skills'),
      'browser-automation',
      skillName: 'Browser Automation',
      description: 'Automate browser tasks',
    );

    final controller = await createTestController(
      tester,
      singleAgentSharedSkillScanRootOverrides: <String>[
        '${tempDirectory.path}/custom-skills',
      ],
    );
    await controller.setAssistantExecutionTarget(
      AssistantExecutionTarget.singleAgent,
    );
    await tester.pumpAndSettle();

    controller.openModules(tab: ModulesTab.skills);
    await pumpPage(
      tester,
      child: ModulesPage(
        controller: controller,
        onOpenDetail: (_) {},
        initialTab: ModulesTab.skills,
      ),
    );

    expect(find.text('技能模式'), findsOneWidget);
    expect(find.text('单机智能体'), findsOneWidget);
    expect(find.text('本地 Gateway'), findsOneWidget);
    expect(find.text('远程 Gateway'), findsOneWidget);
    expect(find.text('Browser Automation'), findsWidgets);
  });
}

Future<void> _writeSkill(
  Directory root,
  String name, {
  required String skillName,
  required String description,
}) async {
  final directory = Directory('${root.path}/$name');
  await directory.create(recursive: true);
  await File('${directory.path}/SKILL.md').writeAsString('''
---
name: $skillName
description: $description
---
''');
}
