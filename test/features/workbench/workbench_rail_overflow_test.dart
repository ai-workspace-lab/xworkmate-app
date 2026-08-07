import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/workbench/workbench_page.dart';
import 'package:xworkmate/theme/app_theme.dart';

/// The insight rail carries three cards with fixed-height content (a 235px
/// chart among them). The rail used to shrink-wrap them inside a Row with
/// CrossAxisAlignment.start, so any window shorter than their sum painted the
/// yellow overflow banner instead of scrolling — reported at 16px on a real
/// window, and reproducible from ~790px down.
void main() {
  for (final height in <double>[560, 640, 720, 772, 800, 900]) {
    testWidgets('workbench does not overflow at 1440x${height.toInt()}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(1440, height);
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

      expect(
        tester.takeException(),
        isNull,
        reason: 'the rail must scroll, not overflow, at ${height.toInt()}px',
      );
    });
  }

  testWidgets('the insight rail scrolls when it does not fit', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 640);
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

    // The rail is scrollable, and its bottom card is reachable by dragging it.
    final rail = find.ancestor(
      of: find.text('工作洞察'),
      matching: find.byType(Scrollable),
    );
    expect(rail, findsWidgets, reason: 'the rail must be scrollable');

    await tester.drag(rail.first, const Offset(0, -400));
    await tester.pump();

    expect(find.text('AI 整理建议'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
