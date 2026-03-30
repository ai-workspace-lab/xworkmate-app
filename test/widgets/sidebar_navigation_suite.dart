@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
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
            onOpenHome: () {},
            onOpenAccount: () {},
            onOpenThemeToggle: () {},
            accountName: 'Tester',
            accountSubtitle: 'Workspace',
            onToggleAccountWorkspaceFollowed: () async {},
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
            onOpenHome: () {},
            onOpenAccount: () => accountOpened++,
            onOpenThemeToggle: () => themeToggled++,
            accountName: 'Tester',
            accountSubtitle: 'Workspace',
            onToggleAccountWorkspaceFollowed: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('工具'), findsNothing);
    expect(find.text('工作区'), findsNothing);
    expect(find.text('自动化'), findsNothing);
    expect(find.text('MCP Hub'), findsNothing);
    expect(find.text('ClawHub'), findsNothing);
    expect(find.text('回到 APP首页'), findsNothing);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('账户'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-footer-settings')),
    );
    await tester.pumpAndSettle();
    expect(selected, WorkspaceDestination.settings);

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-footer-language')),
    );
    await tester.pumpAndSettle();
    expect(languageToggled, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-footer-theme')),
    );
    await tester.pumpAndSettle();
    expect(themeToggled, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-footer-account')),
    );
    await tester.pumpAndSettle();
    expect(accountOpened, 1);

    await tester.tap(find.byKey(const Key('workspace-sidebar-collapse-button')));
    await tester.pumpAndSettle();
    expect(sidebarCycled, 1);
  });

  testWidgets('SidebarNavigation no longer expands settings sub navigation in sidebar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SidebarNavigation(
            currentSection: WorkspaceDestination.settings,
            sidebarState: AppSidebarState.expanded,
            appLanguage: AppLanguage.zh,
            themeMode: ThemeMode.light,
            onSectionChanged: (_) {},
            onToggleLanguage: () {},
            onCycleSidebarState: () {},
            onExpandFromCollapsed: () {},
            onOpenHome: () {},
            onOpenAccount: () {},
            onOpenThemeToggle: () {},
            accountName: 'Tester',
            accountSubtitle: 'Workspace',
            onToggleAccountWorkspaceFollowed: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sidebar-settings-tab-general')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('sidebar-settings-tab-workspace')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('sidebar-settings-tab-gateway')),
      findsNothing,
    );
  });

  testWidgets('SidebarNavigation merges task controls into the global left bar', (
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
            onOpenHome: () {},
            onOpenAccount: () {},
            onOpenThemeToggle: () {},
            accountName: 'Tester',
            accountSubtitle: 'Workspace',
            onToggleAccountWorkspaceFollowed: () async {},
            assistantSkillCount: 3,
            taskItems: const <SidebarTaskItem>[
              SidebarTaskItem(
                sessionKey: 'draft:1',
                title: '新的任务',
                preview: '等待输入',
                updatedAtMs: 1710000000000,
                executionTarget: AssistantExecutionTarget.singleAgent,
                isCurrent: true,
                pending: false,
                draft: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('workspace-sidebar-task-search')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('workspace-sidebar-new-task-button')),
      findsOneWidget,
    );
    expect(find.text('任务列表'), findsOneWidget);
    expect(find.text('自动化'), findsNothing);
    expect(find.text('MCP Hub'), findsNothing);
    expect(find.text('新的任务'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('workspace-sidebar-task-group-singleAgent'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SidebarNavigation keeps footer pinned while task list scrolls', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final items = List<SidebarTaskItem>.generate(
      18,
      (index) => SidebarTaskItem(
        sessionKey: 'session-$index',
        title: '任务 $index',
        preview: '预览 $index',
        updatedAtMs: 1710000000000 + index.toDouble(),
        executionTarget: AssistantExecutionTarget.singleAgent,
        isCurrent: index == 0,
        pending: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 560,
              child: SidebarNavigation(
                currentSection: WorkspaceDestination.assistant,
                sidebarState: AppSidebarState.expanded,
                appLanguage: AppLanguage.zh,
                themeMode: ThemeMode.light,
                onSectionChanged: (_) {},
                onToggleLanguage: () {},
                onCycleSidebarState: () {},
                onExpandFromCollapsed: () {},
                onOpenHome: () {},
                onOpenAccount: () {},
                onOpenThemeToggle: () {},
                accountName: 'Tester',
                accountSubtitle: 'Workspace',
                onToggleAccountWorkspaceFollowed: () async {},
                taskItems: items,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final footerBefore = tester.getTopLeft(
      find.byKey(const ValueKey<String>('sidebar-footer-settings')),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();

    final footerAfter = tester.getTopLeft(
      find.byKey(const ValueKey<String>('sidebar-footer-settings')),
    );

    expect(footerAfter.dy, footerBefore.dy);
  });
}
