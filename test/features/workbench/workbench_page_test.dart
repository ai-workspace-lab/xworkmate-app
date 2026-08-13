import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/workbench/workbench_page.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets('workbench exposes the selected analytics structure', (
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

    expect(find.text('数据总览'), findsOneWidget);
    expect(find.text('模型分析'), findsOneWidget);
    expect(find.text('我的待办'), findsOneWidget);
    expect(find.text('项目 / 专项'), findsOneWidget);
    expect(find.text('收件箱'), findsOneWidget);
    expect(find.text('最近 TaskThreads'), findsOneWidget);
    expect(
      find.byKey(const Key('workbench-metric-TaskThreads')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('workbench-activity-heatmap')), findsOneWidget);
    expect(find.byKey(const Key('workbench-overview-table')), findsOneWidget);
    expect(find.byKey(const Key('workbench-insight-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('workbench-workload-trend')), findsOneWidget);
    expect(find.byKey(const Key('workbench-rhythm-progress')), findsOneWidget);
    expect(
      find.byKey(const Key('workbench-ai-recommendations')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('workbench-insights-collapse-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('workbench-insight-sidebar-collapsed')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('workbench-workload-trend')), findsNothing);

    await tester.tap(find.byKey(const Key('workbench-insights-expand-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workbench-insight-sidebar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('workbench-activity-window-1')));
    await tester.pump();
    expect(
      find.byKey(const Key('workbench-activity-window-1-selected')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('workbench-tab-1')));
    await tester.pump();
    expect(find.byKey(const Key('workbench-model-analysis')), findsOneWidget);
    expect(find.text('Tokens 使用趋势（按月）'), findsOneWidget);
    expect(find.text('模型使用份额'), findsOneWidget);

    await tester.tap(find.byKey(const Key('workbench-tab-2')));
    await tester.pump();
    expect(find.byKey(const Key('workbench-todo-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('workbench-tab-3')));
    await tester.pump();
    expect(find.byKey(const Key('workbench-projects-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('workbench-tab-4')));
    await tester.pump();
    expect(find.byKey(const Key('workbench-inbox-page')), findsOneWidget);
  });

  testWidgets('workbench overview matches the desktop visual baseline', (
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

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/workbench_overview.png'),
    );
  });
}
