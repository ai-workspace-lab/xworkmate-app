import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_palette.dart';
import 'package:xworkmate/widgets/sidebar_navigation.dart';

void main() {
  testWidgets('Expanded sidebar renders scheduled tasks button with tooltip', (tester) async {
    var scheduledTasksOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: const <ThemeExtension<dynamic>>[AppPalette.light],
        ),
        home: Scaffold(
          body: SidebarNavigation(
            currentSection: WorkspaceDestination.workbench,
            sidebarState: AppSidebarState.expanded,
            appLanguage: AppLanguage.zh,
            themeMode: ThemeMode.light,
            accountName: 'Tester',
            accountSubtitle: 'Admin',
            onSectionChanged: (_) {},
            onToggleLanguage: () {},
            onCycleSidebarState: () {},
            onExpandFromCollapsed: () {},
            onOpenAccount: () {},
            onOpenThemeToggle: () {},
            onOpenScheduledTasks: () {
              scheduledTasksOpened = true;
            },
          ),
        ),
      ),
    );

    // Verify scheduled tasks row exists
    final buttonFinder = find.byKey(const Key('workspace-sidebar-scheduled-tasks-button'));
    expect(buttonFinder, findsOneWidget);
    expect(find.text('定时任务'), findsOneWidget);

    // Verify tooltip
    final tooltipFinder = find.descendant(
      of: buttonFinder,
      matching: find.byType(Tooltip),
    );
    expect(tooltipFinder, findsOneWidget);
    final tooltipWidget = tester.widget<Tooltip>(tooltipFinder);
    expect(tooltipWidget.message, '定时任务');

    // Tap button
    await tester.tap(buttonFinder);
    await tester.pump();
    expect(scheduledTasksOpened, isTrue);
  });

  testWidgets('Collapsed sidebar renders clock icon button with tooltip matching design', (tester) async {
    var scheduledTasksOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: const <ThemeExtension<dynamic>>[AppPalette.light],
        ),
        home: Scaffold(
          body: SidebarNavigation(
            currentSection: WorkspaceDestination.workbench,
            sidebarState: AppSidebarState.collapsed,
            appLanguage: AppLanguage.zh,
            themeMode: ThemeMode.light,
            accountName: 'Tester',
            accountSubtitle: 'Admin',
            onSectionChanged: (_) {},
            onToggleLanguage: () {},
            onCycleSidebarState: () {},
            onExpandFromCollapsed: () {},
            onOpenAccount: () {},
            onOpenThemeToggle: () {},
            onOpenScheduledTasks: () {
              scheduledTasksOpened = true;
            },
          ),
        ),
      ),
    );

    // Verify collapsed scheduled tasks button exists
    final buttonFinder = find.byKey(const Key('sidebar-collapsed-scheduled-tasks-button'));
    expect(buttonFinder, findsOneWidget);

    // Verify clock icon
    expect(
      find.descendant(of: buttonFinder, matching: find.byIcon(Icons.access_time_rounded)),
      findsOneWidget,
    );

    // Verify tooltip
    final tooltipFinder = find.descendant(
      of: buttonFinder,
      matching: find.byType(Tooltip),
    );
    expect(tooltipFinder, findsOneWidget);
    final tooltipWidget = tester.widget<Tooltip>(tooltipFinder);
    expect(tooltipWidget.message, '定时任务');

    // Tap button
    await tester.tap(buttonFinder);
    await tester.pump();
    expect(scheduledTasksOpened, isTrue);
  });
}
