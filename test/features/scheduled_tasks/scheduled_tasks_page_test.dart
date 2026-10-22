import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/scheduled_tasks/scheduled_tasks_page.dart';
import 'package:xworkmate/theme/app_palette.dart';

void main() {
  testWidgets('ScheduledTasksController creates and activates aggregated sessions in assistant', (tester) async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    final scheduledTasks = controller.scheduledTasksController;
    expect(scheduledTasks.tasks.length, 4);

    // Initial check
    final initialSessionCount = controller.assistantSessions.length;

    // Trigger Codex audit
    await scheduledTasks.runTaskNow('codex-audit', selectSession: false);

    // Verify session was generated and added to assistantSessions
    final updatedSessions = controller.assistantSessions;
    expect(updatedSessions.length, greaterThan(initialSessionCount));

    final codexSession = updatedSessions.firstWhere(
      (s) => s.key == 'scheduled:codex-audit',
    );
    expect(codexSession.displayName, contains('Codex 巡检'));

    // Trigger Gemini analysis
    await scheduledTasks.runTaskNow('gemini-analysis', selectSession: false);
    final geminiSession = controller.assistantSessions.firstWhere(
      (s) => s.key == 'scheduled:gemini-review',
    );
    expect(geminiSession.displayName, contains('Gemini 分析'));

    // Trigger Grok build verification
    await scheduledTasks.runTaskNow('grok-build', selectSession: false);
    final grokSession = controller.assistantSessions.firstWhere(
      (s) => s.key == 'scheduled:grok-build',
    );
    expect(grokSession.displayName, contains('Grok 构建'));

    // Verify message briefings exist for the created sessions
    final codexMessages = controller.localSessionMessagesInternal['scheduled:codex-audit'];
    expect(codexMessages, isNotNull);
    expect(codexMessages!.length, 2);
    expect(codexMessages.last.text, contains('Codex 代码健康度巡检简报'));

    controller.dispose();
  });

  testWidgets('ScheduledTasksPage renders cards, switches, intervals, and responds to actions', (tester) async {
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: const <ThemeExtension<dynamic>>[AppPalette.light],
        ),
        home: ScheduledTasksPage(controller: controller),
      ),
    );

    await tester.pumpAndSettle();

    // Verify header and badges
    expect(find.text('定时任务'), findsWidgets);
    expect(find.text('AI Gateway :4000'), findsOneWidget);
    expect(find.text('QMD :8181'), findsOneWidget);
    expect(find.text('DSH :3000'), findsOneWidget);

    // Verify 4 cards
    expect(find.byKey(const Key('scheduled-task-card-qmd-sync')), findsOneWidget);
    expect(find.byKey(const Key('scheduled-task-card-codex-audit')), findsOneWidget);
    expect(find.byKey(const Key('scheduled-task-card-gemini-analysis')), findsOneWidget);
    expect(find.byKey(const Key('scheduled-task-card-grok-build')), findsOneWidget);

    // Verify interval change
    final intervalDropdown = find.byKey(const Key('scheduled-task-interval-qmd-sync'));
    expect(intervalDropdown, findsOneWidget);

    // Toggle switch
    final switchFinder = find.byKey(const Key('scheduled-task-switch-codex-audit'));
    expect(switchFinder, findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(controller.scheduledTasksController.tasks.firstWhere((t) => t.id == 'codex-audit').enabled, isFalse);

    // Re-enable
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(controller.scheduledTasksController.tasks.firstWhere((t) => t.id == 'codex-audit').enabled, isTrue);

    // Run action
    final runOpenButton = find.byKey(const Key('scheduled-task-run-open-grok-build'));
    expect(runOpenButton, findsOneWidget);
    await tester.tap(runOpenButton);
    await tester.pumpAndSettle();

    expect(controller.assistantSessions.any((s) => s.key == 'scheduled:grok-build'), isTrue);

    controller.dispose();
  });
}
