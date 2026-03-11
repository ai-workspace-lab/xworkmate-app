import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/sidebar_navigation.dart';

void main() {
  testWidgets('SidebarNavigation routes footer and section actions', (
    WidgetTester tester,
  ) async {
    var selected = WorkspaceDestination.assistant;
    var languageToggled = 0;
    var themeToggled = 0;
    var sidebarCycled = 0;
    var accountOpened = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SidebarNavigation(
            currentSection: selected,
            sidebarState: AppSidebarState.expanded,
            appLanguage: AppLanguage.zh,
            themeMode: ThemeMode.light,
            onSectionChanged: (value) => selected = value,
            onToggleLanguage: () => languageToggled++,
            onCycleSidebarState: () => sidebarCycled++,
            onExpandFromCollapsed: () {},
            onOpenAccount: () => accountOpened++,
            onOpenThemeToggle: () => themeToggled++,
            accountName: 'Tester',
            accountSubtitle: 'Workspace',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('任务'));
    await tester.pumpAndSettle();
    expect(selected, WorkspaceDestination.tasks);

    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    expect(languageToggled, 1);

    await tester.tap(find.text('切换深色'));
    await tester.pumpAndSettle();
    expect(themeToggled, 1);

    await tester.tap(find.text('折叠导航'));
    await tester.pumpAndSettle();
    expect(sidebarCycled, 1);

    await tester.tap(find.text('Tester'));
    await tester.pumpAndSettle();
    expect(accountOpened, 1);
  });
}
