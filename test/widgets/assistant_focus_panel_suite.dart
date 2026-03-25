@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/assistant_focus_panel.dart';

import '../test_support.dart';

void main() {
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
              destination: WorkspaceDestination.settings,
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
}
