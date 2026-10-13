import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/bot_team/bot_team_controller.dart';
import 'package:xworkmate/features/bot_team/bot_team_page.dart';
import 'package:xworkmate/i18n/app_language.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/sidebar_navigation.dart';

import 'fake_task_session_client.dart';

void main() {
  setUp(() => setActiveAppLanguage(AppLanguage.zh));

  Future<BotTeamController> pumpPage(WidgetTester tester, FakeTaskSessionClient? accounts) async {
    final controller = BotTeamController(
      clientFactory: () => accounts,
      pollInterval: const Duration(days: 1),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Material(
          child: BotTeamPage(clientFactory: () => accounts, controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('the page shows roles without vendor branding and sends a role task', (tester) async {
    final accounts = FakeTaskSessionClient();
    final controller = await pumpPage(tester, accounts);

    expect(find.byKey(const Key('bot-team-page')), findsOneWidget);
    expect(find.byKey(const Key('bot-team-role-engineer')), findsNothing);
    await tester.tap(find.byKey(const Key('bot-team-role-button')));
    await tester.pumpAndSettle();
    for (final role in ['auto', 'chat', 'worker', 'engineer', 'architect', 'researcher', 'specialist']) {
      expect(find.byKey(Key('bot-team-role-$role')), findsOneWidget);
    }
    expect(find.textContaining('DeepSeek'), findsNothing);
    expect(find.textContaining('DS Bot'), findsNothing);

    await tester.tap(find.byKey(const Key('bot-team-role-engineer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bot-team-role-chat')), findsNothing);
    expect(
      find.descendant(of: find.byKey(const Key('bot-team-role-button')), matching: find.text('Engineer')),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('bot-team-workspace-field')), 'repo');
    await tester.enterText(find.byKey(const Key('bot-team-composer')), '修复失败的测试');
    await tester.tap(find.byKey(const Key('bot-team-send-button')));
    await tester.pumpAndSettle();

    expect(accounts.appended.single['routing'], <String, Object?>{'roleMode': 'auto', 'role': 'engineer', 'workspace': 'repo'});
    expect(find.text('修复失败的测试'), findsWidgets);
    expect(find.text('排队中'), findsOneWidget);
    final composer = tester.widget<TextField>(find.byKey(const Key('bot-team-composer')));
    expect(composer.controller!.text, isEmpty);
    controller.dispose();
  });

  testWidgets('a running task can be cancelled and shows its answer when done', (tester) async {
    final accounts = FakeTaskSessionClient();
    final controller = await pumpPage(tester, accounts);
    await controller.send('长任务');
    await tester.pumpAndSettle();
    final runId = controller.tasks.single.runId;

    await tester.tap(find.byKey(Key('bot-team-cancel-$runId')));
    await tester.pumpAndSettle();
    expect(accounts.cancelled, <String>[runId]);
    expect(find.text('正在取消…'), findsOneWidget);
    expect(find.byKey(Key('bot-team-cancel-$runId')), findsNothing);

    accounts.addEvent(controller.selectedSessionId, 'assistant.message.created', {'taskRunId': runId, 'text': '部分结果'});
    accounts.addEvent(controller.selectedSessionId, 'run.cancelled', {'taskRunId': runId});
    await controller.selectSession('');
    await controller.selectSession(accounts.sessions.single.sessionId);
    await tester.pumpAndSettle();
    expect(find.text('已取消'), findsOneWidget);
    expect(find.byKey(Key('bot-team-answer-$runId')), findsOneWidget);
    controller.dispose();
  });

  testWidgets('without a connected bridge the page explains and disables sending', (tester) async {
    final controller = await pumpPage(tester, null);
    expect(find.byKey(const Key('bot-team-error')), findsOneWidget);
    final send = tester.widget<FilledButton>(find.byKey(const Key('bot-team-send-button')));
    expect(send.onPressed, isNull);
    controller.dispose();
  });

  testWidgets('the sidebar shows the Bot team entry only when it is available', (tester) async {
    var opened = 0;
    Future<void> pumpSidebar(VoidCallback? onOpenBotTeam) async {
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
                onOpenBotTeam: onOpenBotTeam,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpSidebar(null);
    expect(find.byKey(const Key('workspace-sidebar-bot-team-button')), findsNothing);
    await pumpSidebar(() => opened++);
    expect(find.byKey(const Key('workspace-sidebar-bot-team-button')), findsOneWidget);
    expect(find.text('Bot 团队'), findsOneWidget);
    await tester.tap(find.byKey(const Key('workspace-sidebar-bot-team-button')));
    expect(opened, 1);
  });
}
