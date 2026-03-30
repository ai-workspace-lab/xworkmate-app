@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/assistant_focus_panel.dart';

import '../test_support.dart';

void main() {
  test('assistant focus panel core files stay within 800 lines', () {
    const targets = <String>[
      'lib/widgets/assistant_focus_panel_core.dart',
      'lib/widgets/assistant_focus_panel_previews.dart',
      'lib/widgets/assistant_focus_panel_support.dart',
    ];

    for (final path in targets) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'missing file: $path');
      expect(
        file.readAsLinesSync().length,
        lessThanOrEqualTo(800),
        reason: '$path should be split into smaller parts',
      );
    }
  });

  test('legacy web focus panel duplicates stay removed', () {
    const removedTargets = <String>[
      'lib/web/web_focus_panel.dart',
      'lib/web/web_focus_panel_core.dart',
      'lib/web/web_focus_panel_previews.dart',
      'lib/web/web_focus_panel_support.dart',
    ];

    for (final path in removedTargets) {
      expect(
        File(path).existsSync(),
        isFalse,
        reason: 'legacy file should stay removed: $path',
      );
    }
  });

  testWidgets(
    'Settings focused preview reuses language and theme quick actions',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          theme: AppTheme.light(platform: TargetPlatform.macOS),
          darkTheme: AppTheme.dark(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: AssistantFocusDestinationCard(
              controller: controller,
              destination: AssistantFocusEntry.settings,
              onOpenPage: () {},
              onRemoveFavorite: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assistant-focus-settings-language-toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-focus-settings-theme-toggle')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('assistant-focus-settings-language-toggle')),
      );
      await tester.pumpAndSettle();
      expect(controller.appLanguage, AppLanguage.en);

      await tester.tap(
        find.byKey(const Key('assistant-focus-settings-theme-toggle')),
      );
      await tester.pumpAndSettle();
      expect(controller.themeMode, ThemeMode.dark);
    },
  );

  testWidgets('Language and theme focus entries run directly', (
    WidgetTester tester,
  ) async {
    final controller = await createTestController(tester);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: AppTheme.light(platform: TargetPlatform.macOS),
        darkTheme: AppTheme.dark(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: AssistantFocusDestinationCard(
                  controller: controller,
                  destination: AssistantFocusEntry.language,
                  onOpenPage: () {},
                  onRemoveFavorite: () async {},
                ),
              ),
              Expanded(
                child: AssistantFocusDestinationCard(
                  controller: controller,
                  destination: AssistantFocusEntry.theme,
                  onOpenPage: () {},
                  onRemoveFavorite: () async {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('assistant-focus-language-toggle')));
    await tester.pumpAndSettle();
    expect(controller.appLanguage, AppLanguage.en);

    await tester.tap(find.byKey(const Key('assistant-focus-theme-toggle')));
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.dark);
  });
}
