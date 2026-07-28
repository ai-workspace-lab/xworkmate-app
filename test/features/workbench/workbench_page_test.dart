import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/workbench/workbench_page.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets('workbench exposes the reviewed Issue 213 structure', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 960);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light().copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(body: WorkbenchPage(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.text('工作台'), findsOneWidget);
    expect(find.text('总览'), findsOneWidget);
    expect(find.text('我的待办'), findsOneWidget);
    expect(find.text('项目 / 专项'), findsOneWidget);
    expect(find.text('收件箱'), findsOneWidget);
    expect(find.text('需要你处理'), findsOneWidget);
    expect(find.text('正在推进的专项'), findsOneWidget);
    expect(find.text('工作洞察'), findsOneWidget);
    expect(find.text('本周节奏'), findsOneWidget);
    expect(find.text('AI 整理建议'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('workbench-right-rail-collapse-button')),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('workbench-right-rail-expand-button')),
      findsOneWidget,
    );
    expect(find.text('工作洞察'), findsNothing);

    await tester.tap(
      find.byKey(const Key('workbench-right-rail-expand-button')),
    );
    await tester.pump();
    expect(find.text('工作洞察'), findsOneWidget);

    tester.view.physicalSize = const Size(900, 960);
    await tester.pump();
    expect(find.text('工作洞察'), findsOneWidget);
    expect(find.text('本周节奏'), findsOneWidget);
    expect(find.text('AI 整理建议'), findsOneWidget);

    await tester.tap(find.byKey(const Key('workbench-tab-1')));
    await tester.pump();
    expect(find.byKey(const Key('workbench-todo-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('workbench-tab-2')));
    await tester.pump();
    expect(find.byKey(const Key('workbench-projects-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('workbench-tab-3')));
    await tester.pump();
    expect(find.byKey(const Key('workbench-inbox-page')), findsOneWidget);
  });
}
