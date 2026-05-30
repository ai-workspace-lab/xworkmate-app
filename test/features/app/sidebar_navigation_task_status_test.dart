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
          pending: true,
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

  testWidgets('sidebar does not show pending for stale queued lifecycle', (
    tester,
  ) async {
    await _pumpSidebar(
      tester,
      items: const <SidebarTaskItem>[
        SidebarTaskItem(
          sessionKey: 'stale-queued-task',
          title: '已停止任务',
          preview: '不应继续 Pending',
          updatedAtMs: 1,
          executionTarget: AssistantExecutionTarget.gateway,
          isCurrent: false,
          pending: false,
          lifecycleStatus: 'queued',
          lastResultCode: 'queued',
        ),
      ],
    );

    expect(find.text('Pending'), findsNothing);
    expect(
      find.byKey(const Key('workspace-sidebar-task-status-chip')),
      findsNothing,
    );
  });

  testWidgets('sidebar keeps the supplied task order when selection changes', (
    tester,
  ) async {
    const firstTitle = '先显示任务';
    const selectedTitle = '当前选择任务';
    const lastTitle = '后显示任务';

    await _pumpSidebar(
      tester,
      items: const <SidebarTaskItem>[
        SidebarTaskItem(
          sessionKey: 'first-task',
          title: firstTitle,
          preview: '第一项',
          updatedAtMs: 1000,
          executionTarget: AssistantExecutionTarget.gateway,
          isCurrent: false,
          pending: false,
        ),
        SidebarTaskItem(
          sessionKey: 'selected-task',
          title: selectedTitle,
          preview: '被选中的第二项',
          updatedAtMs: 3000,
          executionTarget: AssistantExecutionTarget.gateway,
          isCurrent: true,
          pending: false,
        ),
        SidebarTaskItem(
          sessionKey: 'last-task',
          title: lastTitle,
          preview: '第三项',
          updatedAtMs: 2000,
          executionTarget: AssistantExecutionTarget.gateway,
          isCurrent: false,
          pending: false,
        ),
      ],
    );

    expect(
      _textTop(tester, firstTitle),
      lessThan(_textTop(tester, selectedTitle)),
    );
    expect(
      _textTop(tester, selectedTitle),
      lessThan(_textTop(tester, lastTitle)),
    );
  });

  testWidgets('sidebar keeps scroll position when task content refreshes', (
    tester,
  ) async {
    var items = _manySidebarItems(
      selectedSessionKey: 'task-10',
      previewSuffix: 'before refresh',
    );

    Future<void> pump() async {
      await _pumpSidebar(tester, items: items, height: 360);
    }

    await pump();
    await tester.drag(
      find.byKey(const PageStorageKey<String>('workspace-sidebar-task-list')),
      const Offset(0, -420),
    );
    await tester.pump();

    final anchorFinder = find.byKey(
      const ValueKey<String>('workspace-sidebar-task-item-task-10'),
    );
    final anchorTopBefore = tester.getTopLeft(anchorFinder).dy;

    items = _manySidebarItems(
      selectedSessionKey: 'task-10',
      previewSuffix: 'after refresh',
    );
    await pump();

    expect(tester.getTopLeft(anchorFinder).dy, closeTo(anchorTopBefore, 0.1));
    expect(_textTop(tester, '任务 09'), lessThan(_textTop(tester, '任务 10')));
    expect(_textTop(tester, '任务 10'), lessThan(_textTop(tester, '任务 11')));
  });
}

double _textTop(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

Future<void> _pumpSidebar(
  WidgetTester tester, {
  required List<SidebarTaskItem> items,
  double height = 720,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Material(
        child: SizedBox(
          width: 360,
          height: height,
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

List<SidebarTaskItem> _manySidebarItems({
  required String selectedSessionKey,
  required String previewSuffix,
}) {
  return List<SidebarTaskItem>.generate(18, (index) {
    final sessionKey = 'task-${index.toString().padLeft(2, '0')}';
    return SidebarTaskItem(
      sessionKey: sessionKey,
      title: '任务 ${index.toString().padLeft(2, '0')}',
      preview: '刷新内容 $previewSuffix',
      updatedAtMs: (1000 + index).toDouble(),
      executionTarget: AssistantExecutionTarget.gateway,
      isCurrent: sessionKey == selectedSessionKey,
      pending: false,
    );
  }, growable: false);
}
