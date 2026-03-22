@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/sidebar_navigation.dart';

void main() {
  testWidgets('SidebarNavigation uses the compact zh default width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SidebarNavigation(
            currentSection: WorkspaceDestination.assistant,
            sidebarState: AppSidebarState.expanded,
            appLanguage: AppLanguage.zh,
            themeMode: ThemeMode.light,
            onSectionChanged: (_) {},
            onToggleLanguage: () {},
            onCycleSidebarState: () {},
            onExpandFromCollapsed: () {},
            onOpenAccount: () {},
            onOpenThemeToggle: () {},
            accountName: 'Tester',
            accountSubtitle: 'Workspace',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(SidebarNavigation)).width,
      AppSizes.sidebarExpandedWidthZh + 8,
    );
  });

  testWidgets('SidebarNavigation routes footer and section actions', (
    WidgetTester tester,
  ) async {
    var selected = WorkspaceDestination.assistant;
    var languageToggled = 0;
    var themeToggled = 0;
    var sidebarCycled = 0;
    var accountOpened = 0;
    var favoriteToggled = 0;

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
            favoriteDestinations: const <WorkspaceDestination>{
              WorkspaceDestination.skills,
            },
            onToggleFavorite: (value) async {
              if (value == WorkspaceDestination.skills) {
                favoriteToggled++;
              }
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('工具'), findsOneWidget);
    expect(find.text('MCP Hub'), findsOneWidget);

    await tester.tap(find.text('自动化'));
    await tester.pumpAndSettle();
    expect(selected, WorkspaceDestination.tasks);

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-favorite-skills')),
    );
    await tester.pumpAndSettle();
    expect(favoriteToggled, 1);

    await tester.tap(find.byTooltip('切换语言'));
    await tester.pumpAndSettle();
    expect(languageToggled, 1);

    await tester.tap(find.byTooltip('切换深色'));
    await tester.pumpAndSettle();
    expect(themeToggled, 1);

    await tester.tap(find.byTooltip('收起侧边栏'));
    await tester.pumpAndSettle();
    expect(sidebarCycled, 1);

    await tester.tap(find.text('Tester'));
    await tester.pumpAndSettle();
    expect(accountOpened, 1);
  });
}
