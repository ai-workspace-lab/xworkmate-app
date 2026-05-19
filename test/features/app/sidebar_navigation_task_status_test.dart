import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/sidebar_navigation.dart';

void main() {
  setUp(() {
    setActiveAppLanguage(AppLanguage.zh);
  });

  testWidgets('sidebar task list renders lifecycle status chips', (
    tester,
  ) async {
    await _pumpSidebar(
      tester,
      items: const <SidebarTaskItem>[
        SidebarTaskItem(
          sessionKey: 'running-task',
          title: '运行任务',
          preview: '正在执行',
          updatedAtMs: 1,
          executionTarget: AssistantExecutionTarget.gateway,
          isCurrent: false,
          pending: true,
          lifecycleStatus: 'running',
          lastResultCode: 'running',
        ),
        SidebarTaskItem(
          sessionKey: 'queued-task',
          title: '排队任务',
          preview: '等待执行',
          updatedAtMs: 1,
          executionTarget: AssistantExecutionTarget.gateway,
          isCurrent: false,
          pending: false,
          lifecycleStatus: 'queued',
          lastResultCode: 'queued',
        ),
        SidebarTaskItem(
          sessionKey: 'finished-task',
          title: '结束任务',
          preview: '已完成',
          updatedAtMs: 1,
          executionTarget: AssistantExecutionTarget.gateway,
          isCurrent: false,
          pending: false,
          lifecycleStatus: 'ready',
          lastResultCode: 'success',
        ),
      ],
    );

    expect(find.text('运行'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('结束'), findsOneWidget);
    expect(
      find.byKey(const Key('workspace-sidebar-task-archive-running-task')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('workspace-sidebar-task-archive-finished-task')),
      findsOneWidget,
    );
  });

  testWidgets('sidebar omits status chip for an idle draft task', (
    tester,
  ) async {
    await _pumpSidebar(
      tester,
      items: const <SidebarTaskItem>[
        SidebarTaskItem(
          sessionKey: 'draft:idle-task',
          title: '新对话',
          preview: '',
          updatedAtMs: 1,
          executionTarget: AssistantExecutionTarget.gateway,
          isCurrent: true,
          pending: false,
          draft: true,
        ),
      ],
    );

    expect(
      find.byKey(const Key('workspace-sidebar-task-status-chip')),
      findsNothing,
    );
  });
}

Future<void> _pumpSidebar(
  WidgetTester tester, {
  required List<SidebarTaskItem> items,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Material(
        child: SizedBox(
          width: 360,
          height: 720,
          child: SidebarNavigation(
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
            accountName: '本地操作员',
            accountSubtitle: '账号',
            taskItems: items,
            visibleExecutionTargets: const <AssistantExecutionTarget>[
              AssistantExecutionTarget.gateway,
            ],
            onArchiveTask: (_) async {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
