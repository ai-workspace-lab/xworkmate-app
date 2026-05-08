import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/assistant_task_progress_bar.dart';

void main() {
  testWidgets('shows running progress while a task is pending', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        assistantTaskProgressState(
          pending: true,
          lifecycleStatus: 'running',
          lastResultCode: 'running',
          artifactSyncStatus: '',
        ),
      ),
    );

    expect(
      find.byKey(const Key('assistant-task-progress-bar')),
      findsOneWidget,
    );
    expect(find.text('任务运行中...'), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('assistant-task-progress-indicator')),
    );
    expect(indicator.value, isNull);
  });

  testWidgets('shows artifact sync progress while files are syncing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        assistantTaskProgressState(
          pending: true,
          lifecycleStatus: 'running',
          lastResultCode: 'running',
          artifactSyncStatus: 'syncing',
        ),
      ),
    );

    expect(find.text('正在同步生成文件...'), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('assistant-task-progress-indicator')),
    );
    expect(indicator.value, 0.82);
  });

  testWidgets('shows interrupted state after ACP connection closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        assistantTaskProgressState(
          pending: false,
          lifecycleStatus: 'interrupted',
          lastResultCode: 'ACP_HTTP_CONNECTION_CLOSED',
          artifactSyncStatus: 'interrupted',
        ),
      ),
    );

    expect(find.text('Bridge 响应中断，等待下一次发送续写同一会话。'), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('assistant-task-progress-indicator')),
    );
    expect(indicator.value, 0.48);
  });

  testWidgets('hides idle progress state', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(const AssistantTaskProgressState.idle()),
    );

    expect(find.byKey(const Key('assistant-task-progress-bar')), findsNothing);
  });
}

Widget _buildTestApp(AssistantTaskProgressState state) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Material(
      child: SizedBox(
        width: 420,
        child: AssistantTaskProgressBar(state: state),
      ),
    ),
  );
}
