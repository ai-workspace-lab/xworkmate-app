import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

import 'package:xworkmate/app/app.dart';

void main() {
  group('Golden UI Tests', () {
    setUp(() async {
      await loadAppFonts();
    });

    testGoldens('home page should match golden', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidgetBuilder(
        const XWorkmateApp(),
        surfaceSize: const Size(1600, 1000),
      );
      await tester.pumpAndSettle();

      await screenMatchesGolden(tester, 'home_page');
    });

    testGoldens('settings page should match golden', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidgetBuilder(
        const XWorkmateApp(),
        surfaceSize: const Size(1600, 1000),
      );
      await tester.pumpAndSettle();

      // Navigate to settings if key exists
      final settingsTab = find.byKey(const Key('assistant-side-pane-tab-settings'));
      if (settingsTab.evaluate().isNotEmpty) {
        await tester.tap(settingsTab);
        await tester.pumpAndSettle();
      }

      await screenMatchesGolden(tester, 'settings_page');
    });

    testGoldens('assistant page should match golden', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidgetBuilder(
        const XWorkmateApp(),
        surfaceSize: const Size(1600, 1000),
      );
      await tester.pumpAndSettle();

      await screenMatchesGolden(tester, 'assistant_page');
    });
  });
}
