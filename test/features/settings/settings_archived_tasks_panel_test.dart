import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/settings/settings_archived_tasks_panel.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/surface_card.dart';

void main() {
  setUp(() {
    setActiveAppLanguage(AppLanguage.zh);
  });

  testWidgets('shows empty state when no archived tasks exist', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        child: SettingsArchivedTasksPanel(
          sessions: const <GatewaySessionSummary>[],
          onRestore: (_) async {},
          onDelete: (_) async {},
          onStop: null,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('settings-archived-tasks-empty')),
      findsOneWidget,
    );
    expect(find.text('暂无归档任务'), findsOneWidget);
  });

  testWidgets('restores and confirms deletion for archived task records', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _buildTestApp(
        child: SettingsArchivedTasksPanel(
          sessions: const <GatewaySessionSummary>[
            GatewaySessionSummary(
              key: 'draft:archived-task',
              kind: 'assistant',
              displayName: '导出 PDF',
              surface: 'Assistant',
              subject: null,
              room: null,
              space: null,
              updatedAtMs: 1779178980000,
              sessionId: 'draft:archived-task',
              systemSent: false,
              abortedLastRun: false,
              thinkingLevel: null,
              verboseLevel: null,
              inputTokens: null,
              outputTokens: null,
              totalTokens: null,
              model: null,
              contextTokens: null,
              derivedTitle: '导出 PDF',
              lastMessagePreview: '输出为PDF文件',
            ),
          ],
          onRestore: (sessionKey) async {
            calls.add('restore:$sessionKey');
          },
          onDelete: (sessionKey) async {
            calls.add('delete:$sessionKey');
          },
          onStop: (sessionKey) async {
            calls.add('stop:$sessionKey');
          },
        ),
      ),
    );

    expect(find.text('导出 PDF'), findsOneWidget);
    expect(find.text('输出为PDF文件'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('settings-archived-task-restore-draft:archived-task'),
      ),
    );
    await tester.pump();

    expect(calls, contains('restore:draft:archived-task'));

    await tester.tap(
      find.byKey(
        const ValueKey('settings-archived-task-stop-draft:archived-task'),
      ),
    );
    await tester.pump();
    expect(calls, contains('stop:draft:archived-task'));

    await tester.tap(
      find.byKey(
        const ValueKey('settings-archived-task-delete-draft:archived-task'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('彻底删除归档记录'), findsOneWidget);
    expect(find.text('彻底删除'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('settings-archived-task-confirm-delete')),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认彻底删除'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-archived-task-confirm-delete-yes')),
      findsOneWidget,
    );
    expect(calls, isNot(contains('delete:draft:archived-task')));

    await tester.enterText(
      find.byKey(const ValueKey('settings-archived-task-delete-yes-input')),
      'Yes',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-archived-task-confirm-delete-yes')),
    );
    await tester.pumpAndSettle();

    expect(calls, contains('delete:draft:archived-task'));
  });

  testWidgets('selects all archived tasks and restores selected records', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _buildTestApp(
        child: SettingsArchivedTasksPanel(
          sessions: const <GatewaySessionSummary>[
            _firstArchivedTask,
            _secondArchivedTask,
          ],
          onRestore: (sessionKey) async {
            calls.add('restore:$sessionKey');
          },
          onDelete: (sessionKey) async {
            calls.add('delete:$sessionKey');
          },
          onStop: (sessionKey) async {
            calls.add('stop:$sessionKey');
          },
        ),
      ),
    );

    expect(find.text('共 2 条归档任务'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('settings-archived-tasks-select-all')),
    );
    await tester.pumpAndSettle();

    expect(find.text('已选择 2 / 2 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('settings-archived-tasks-bulk-restore')),
    );
    await tester.pumpAndSettle();

    expect(calls, <String>[
      'restore:draft:archived-task',
      'restore:draft:second-archived-task',
    ]);
    expect(find.text('共 2 条归档任务'), findsOneWidget);
  });

  testWidgets('deletes selected archived tasks after bulk confirmation', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      _buildTestApp(
        child: SettingsArchivedTasksPanel(
          sessions: const <GatewaySessionSummary>[
            _firstArchivedTask,
            _secondArchivedTask,
          ],
          onRestore: (sessionKey) async {
            calls.add('restore:$sessionKey');
          },
          onDelete: (sessionKey) async {
            calls.add('delete:$sessionKey');
          },
          onStop: (sessionKey) async {
            calls.add('stop:$sessionKey');
          },
        ),
      ),
    );

    await tester.tap(
      find.byKey(
        const ValueKey(
          'settings-archived-task-select-draft:second-archived-task',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已选择 1 / 2 条'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('settings-archived-tasks-bulk-delete')),
    );
    await tester.pumpAndSettle();
    expect(find.text('批量彻底删除归档记录'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('settings-archived-task-confirm-bulk-delete')),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认彻底删除'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('settings-archived-task-delete-yes-input')),
      'Yes',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-archived-task-confirm-delete-yes')),
    );
    await tester.pumpAndSettle();

    expect(calls, <String>['delete:draft:second-archived-task']);
    expect(find.text('共 2 条归档任务'), findsOneWidget);
  });
}

const _firstArchivedTask = GatewaySessionSummary(
  key: 'draft:archived-task',
  kind: 'assistant',
  displayName: '导出 PDF',
  surface: 'Assistant',
  subject: null,
  room: null,
  space: null,
  updatedAtMs: 1779178980000,
  sessionId: 'draft:archived-task',
  systemSent: false,
  abortedLastRun: false,
  thinkingLevel: null,
  verboseLevel: null,
  inputTokens: null,
  outputTokens: null,
  totalTokens: null,
  model: null,
  contextTokens: null,
  derivedTitle: '导出 PDF',
  lastMessagePreview: '输出为PDF文件',
);

const _secondArchivedTask = GatewaySessionSummary(
  key: 'draft:second-archived-task',
  kind: 'assistant',
  displayName: '整理会议纪要',
  surface: 'Assistant',
  subject: null,
  room: null,
  space: null,
  updatedAtMs: 1779179000000,
  sessionId: 'draft:second-archived-task',
  systemSent: false,
  abortedLastRun: false,
  thinkingLevel: null,
  verboseLevel: null,
  inputTokens: null,
  outputTokens: null,
  totalTokens: null,
  model: null,
  contextTokens: null,
  derivedTitle: '整理会议纪要',
  lastMessagePreview: '会议纪要已保存',
);

Widget _buildTestApp({required Widget child}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 720, child: SurfaceCard(child: child)),
      ),
    ),
  );
}
