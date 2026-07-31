import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/conversation_workflow_dialog.dart';
import 'package:xworkmate/features/connectors/conversation_publish_connector.dart';
import 'package:xworkmate/features/plugins/conversation_plugin.dart';
import 'package:xworkmate/features/plugins/harness_delivery_target.dart';
import 'package:xworkmate/features/settings/local_git_repository_connection.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  const validTarget = HarnessTarget(
    id: 'target-1',
    org: 'ai-workspace-lab',
    project: 'xworkmate',
    repos: [
      HarnessRepoBinding(
        name: 'xworkmate-app',
        checkoutPath: '/srv/xworkmate-app',
        role: HarnessRepoRole.app,
        order: 1,
      ),
    ],
    environments: [
      HarnessEnvironment(
        name: 'uat',
        trigger: HarnessTriggerKind.mainPush,
        deploy: HarnessDeployKind.docoCdWebhook,
      ),
    ],
  );

  const connectedGitHub = GitHubRepositoryConnectorConfig(
    repository: 'haitaopanhq/knowledge',
    branch: 'main',
    publishPath: 'conversations',
    connected: true,
  );

  Future<ConversationWorkflowRequest?> pumpDialog(
    WidgetTester tester, {
    List<HarnessTarget> targets = const [validTarget],
    GitHubRepositoryConnectorConfig github = connectedGitHub,
  }) async {
    ConversationWorkflowRequest? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showConversationWorkflowDialog(
                  context: context,
                  availableTargets: targets,
                  github: github,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  ButtonStyleButton confirmButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(
        find.byKey(const Key('conversation-workflow-confirm')),
      );

  testWidgets('opens with both selections cleared and the action disabled', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.byKey(const Key('conversation-workflow-dialog')), findsOneWidget);
    expect(confirmButton(tester).onPressed, isNull);
  });

  testWidgets('publish-only enables the action without choosing a plugin', (
    tester,
  ) async {
    await pumpDialog(tester);

    await tester.tap(
      find.byKey(const Key('conversation-workflow-publish-github')),
    );
    await tester.pumpAndSettle();

    expect(confirmButton(tester).onPressed, isNotNull);
    expect(find.text('发布'), findsOneWidget);
  });

  testWidgets('plugin-only enables the action without choosing a connector', (
    tester,
  ) async {
    await pumpDialog(tester);

    await tester.tap(
      find.byKey(const Key('conversation-workflow-plugin-harness')),
    );
    await tester.pumpAndSettle();

    expect(confirmButton(tester).onPressed, isNotNull);
    expect(find.text('运行'), findsOneWidget);
  });

  testWidgets('choosing both shows the combined action label', (tester) async {
    await pumpDialog(tester);

    await tester.tap(
      find.byKey(const Key('conversation-workflow-plugin-harness')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('conversation-workflow-publish-github')),
    );
    await tester.pumpAndSettle();

    expect(find.text('运行并发布'), findsOneWidget);
    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('summary names the target and destination before confirming', (
    tester,
  ) async {
    await pumpDialog(tester);

    await tester.tap(
      find.byKey(const Key('conversation-workflow-plugin-harness')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('conversation-workflow-publish-github')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conversation-workflow-summary')), findsOneWidget);
    expect(find.textContaining('ai-workspace-lab/xworkmate'), findsWidgets);
    expect(find.textContaining('haitaopanhq/knowledge'), findsWidgets);
  });

  testWidgets('guides to plugin settings when no Harness target exists', (
    tester,
  ) async {
    await pumpDialog(tester, targets: const []);

    await tester.tap(
      find.byKey(const Key('conversation-workflow-plugin-harness')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('conversation-workflow-no-harness-target')),
      findsOneWidget,
    );
    expect(confirmButton(tester).onPressed, isNull);
  });

  testWidgets('guides to connector settings when GitHub is not connected', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      github: const GitHubRepositoryConnectorConfig(),
    );

    expect(
      find.byKey(const Key('conversation-workflow-github-unconfigured')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('conversation-workflow-publish-github')),
    );
    await tester.pumpAndSettle();

    expect(confirmButton(tester).onPressed, isNull);
  });

  testWidgets('cancel returns nothing', (tester) async {
    await pumpDialog(tester);

    await tester.tap(
      find.byKey(const Key('conversation-workflow-publish-github')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation-workflow-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conversation-workflow-dialog')), findsNothing);
  });

  testWidgets('confirm returns the chosen combination', (tester) async {
    ConversationWorkflowRequest? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured = await showConversationWorkflowDialog(
                  context: context,
                  availableTargets: const [validTarget],
                  github: connectedGitHub,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('conversation-workflow-plugin-harness')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('conversation-workflow-publish-github')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation-workflow-confirm')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.plugin.pluginId, ConversationPluginId.harnessWorkflow);
    expect(captured!.plugin.harnessTargetId, 'target-1');
    expect(
      captured!.publisher.connectorId,
      ConversationPublishConnectorId.githubApi,
    );
  });
}
