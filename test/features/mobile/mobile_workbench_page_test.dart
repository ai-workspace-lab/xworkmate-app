import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_shell_desktop.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  Future<AppController> pumpMobileWorkbench(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);
    controller.navigateTo(WorkspaceDestination.workbench);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
        home: AppShell(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('mobile workbench gives each work view a touch-first entry', (
    tester,
  ) async {
    final controller = await pumpMobileWorkbench(tester);

    expect(find.byKey(const Key('mobile-workbench-page')), findsOneWidget);
    expect(find.text('工作台'), findsOneWidget);
    expect(
      find.byKey(const Key('mobile-workbench-quick-record')),
      findsOneWidget,
    );
    expect(find.text('需要你处理'), findsOneWidget);
    expect(find.text('正在推进的专项'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mobile-workbench-tab-todo')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('mobile-workbench-tab-content-todo')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('mobile-workbench-tab-projects')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('mobile-workbench-tab-content-projects')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('mobile-workbench-tab-inbox')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('mobile-workbench-tab-content-inbox')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('mobile-workbench-quick-record')));
    await tester.pumpAndSettle();
    expect(controller.destination, WorkspaceDestination.assistant);
  });

  testWidgets('mobile workbench matches the iPhone visual baseline', (
    tester,
  ) async {
    await pumpMobileWorkbench(tester);

    expect(
      find.byKey(const Key('mobile-workbench-page')),
      matchesGoldenFile('goldens/mobile_workbench_home.png'),
    );
  });
}
