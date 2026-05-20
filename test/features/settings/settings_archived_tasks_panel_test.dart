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
}

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
