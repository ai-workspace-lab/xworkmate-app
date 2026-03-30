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
    var workspaceFollowToggled = 0;

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
            onToggleAccountWorkspaceFollowed: () async {
              workspaceFollowToggled++;
            },
            favoriteDestinations: const <AssistantFocusEntry>{
              AssistantFocusEntry.skills,
            },
            onToggleFavorite: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('工具'), findsOneWidget);
    expect(find.text('MCP Hub'), findsOneWidget);

    await tester.ensureVisible(find.text('自动化'));
    await tester.tap(find.text('自动化').hitTestable());
    await tester.pumpAndSettle();
    expect(selected, WorkspaceDestination.tasks);

    expect(
      find.byKey(const ValueKey<String>('sidebar-favorite-skills')),
      findsNothing,
    );

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

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-account-follow')),
    );
    await tester.pumpAndSettle();
    expect(workspaceFollowToggled, 1);
  });

  testWidgets('SidebarNavigation toggles footer quick action favorites', (
    WidgetTester tester,
  ) async {
    final toggled = <AssistantFocusEntry>[];

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
            favoriteDestinations: const <AssistantFocusEntry>{
              AssistantFocusEntry.language,
            },
            onToggleFavorite: (value) async => toggled.add(value),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-favorite-language')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-favorite-theme')),
    );
    await tester.pumpAndSettle();

    expect(toggled, const <AssistantFocusEntry>[
      AssistantFocusEntry.language,
      AssistantFocusEntry.theme,
    ]);
  });

  testWidgets(
    'SidebarNavigation shows app home shortcut copy on settings page',
    (WidgetTester tester) async {
      var selected = WorkspaceDestination.settings;
      var homeOpened = 0;

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
              onToggleLanguage: () {},
              onCycleSidebarState: () {},
              onExpandFromCollapsed: () {},
              onOpenHome: () => homeOpened++,
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

      expect(find.text('回到 APP首页'), findsOneWidget);
      expect(find.text('新对话'), findsWidgets);

      await tester.ensureVisible(find.text('回到 APP首页'));
      await tester.tap(find.text('回到 APP首页').hitTestable());
      await tester.pumpAndSettle();

      expect(homeOpened, 1);
      expect(selected, WorkspaceDestination.settings);
    },
  );

  testWidgets('SidebarNavigation exposes settings sub navigation in sidebar', (
    WidgetTester tester,
  ) async {
    final changedTabs = <SettingsTab>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SidebarNavigation(
            currentSection: WorkspaceDestination.settings,
            sidebarState: AppSidebarState.expanded,
            appLanguage: AppLanguage.zh,
            themeMode: ThemeMode.light,
            currentSettingsTab: SettingsTab.general,
            availableSettingsTabs: const <SettingsTab>[
              SettingsTab.general,
              SettingsTab.workspace,
              SettingsTab.gateway,
            ],
            onSettingsTabChanged: changedTabs.add,
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
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sidebar-settings-tab-workspace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('sidebar-settings-tab-gateway')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-settings-tab-gateway')),
    );
    await tester.pumpAndSettle();

    expect(changedTabs, <SettingsTab>[SettingsTab.gateway]);
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
    expect(find.text('自动化'), findsOneWidget);
    expect(find.text('新的任务'), findsOneWidget);
  });
}
