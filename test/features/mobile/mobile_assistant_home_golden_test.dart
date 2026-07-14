import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_shell_desktop.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  testWidgets('mobile assistant home matches v1.1 redesign golden', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
        home: AppShell(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('mobile-assistant-page')),
      matchesGoldenFile('goldens/mobile_assistant_home.png'),
    );
  });
}
