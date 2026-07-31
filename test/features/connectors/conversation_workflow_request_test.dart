import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/connectors/conversation_publish_connector.dart';
import 'package:xworkmate/features/plugins/conversation_plugin.dart';
import 'package:xworkmate/features/plugins/harness_delivery_target.dart';
import 'package:xworkmate/features/settings/local_git_repository_connection.dart';

void main() {
  final validTarget = HarnessTarget(
    id: 'target-1',
    org: 'ai-workspace-lab',
    project: 'xworkmate',
    repos: const [
      HarnessRepoBinding(
        name: 'xworkmate-app',
        checkoutPath: '/srv/xworkmate-app',
        role: HarnessRepoRole.app,
        order: 1,
      ),
    ],
    environments: const [
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
  const disconnectedGitHub = GitHubRepositoryConnectorConfig();

  group('ConversationWorkflowRequest validation', () {
    test('rejects a request that selects neither a plugin nor a connector', () {
      const request = ConversationWorkflowRequest();

      expect(request.isEmpty, isTrue);
      expect(
        request.validationIssues(
          availableTargets: [validTarget],
          github: connectedGitHub,
        ),
        isNotEmpty,
      );
    });

    test('accepts publish-only without touching the plugin selection', () {
      const request = ConversationWorkflowRequest(
        publisher: ConversationPublishSelection(
          connectorId: ConversationPublishConnectorId.githubApi,
        ),
      );

      expect(request.plugin.runsPlugin, isFalse);
      expect(
        request.validationIssues(
          availableTargets: const [],
          github: connectedGitHub,
        ),
        isEmpty,
      );
    });

    test('accepts plugin-only without requiring a GitHub connection', () {
      final request = ConversationWorkflowRequest(
        plugin: const ConversationPluginSelection(
          pluginId: ConversationPluginId.harnessWorkflow,
          harnessTargetId: 'target-1',
        ),
      );

      expect(request.publisher.publishes, isFalse);
      expect(
        request.validationIssues(
          availableTargets: [validTarget],
          github: disconnectedGitHub,
        ),
        isEmpty,
      );
    });

    test('rejects Harness without a selected target', () {
      const request = ConversationWorkflowRequest(
        plugin: ConversationPluginSelection(
          pluginId: ConversationPluginId.harnessWorkflow,
        ),
      );

      expect(
        request.validationIssues(
          availableTargets: [validTarget],
          github: connectedGitHub,
        ),
        isNotEmpty,
      );
    });

    test('rejects Harness when the selected target id is unknown', () {
      final request = ConversationWorkflowRequest(
        plugin: const ConversationPluginSelection(
          pluginId: ConversationPluginId.harnessWorkflow,
          harnessTargetId: 'missing',
        ),
      );

      expect(
        request.plugin.resolveHarnessTarget([validTarget]),
        isNull,
      );
      expect(
        request.validationIssues(
          availableTargets: [validTarget],
          github: connectedGitHub,
        ),
        isNotEmpty,
      );
    });

    test('surfaces the target’s own validation issues', () {
      const invalidTarget = HarnessTarget(id: 'target-2', org: '', project: '');
      const request = ConversationWorkflowRequest(
        plugin: ConversationPluginSelection(
          pluginId: ConversationPluginId.harnessWorkflow,
          harnessTargetId: 'target-2',
        ),
      );

      expect(
        request.validationIssues(
          availableTargets: const [invalidTarget],
          github: connectedGitHub,
        ),
        isNotEmpty,
      );
    });

    test('rejects GitHub publish when the connector is not connected', () {
      const request = ConversationWorkflowRequest(
        publisher: ConversationPublishSelection(
          connectorId: ConversationPublishConnectorId.githubApi,
        ),
      );

      expect(
        request.validationIssues(
          availableTargets: const [],
          github: disconnectedGitHub,
        ),
        isNotEmpty,
      );
    });
  });

  group('ConversationWorkflowRequest presentation', () {
    test('labels each of the four combinations', () {
      const noop = ConversationWorkflowRequest();
      const publishOnly = ConversationWorkflowRequest(
        publisher: ConversationPublishSelection(
          connectorId: ConversationPublishConnectorId.githubApi,
        ),
      );
      const pluginOnly = ConversationWorkflowRequest(
        plugin: ConversationPluginSelection(
          pluginId: ConversationPluginId.harnessWorkflow,
          harnessTargetId: 'target-1',
        ),
      );
      const both = ConversationWorkflowRequest(
        plugin: ConversationPluginSelection(
          pluginId: ConversationPluginId.harnessWorkflow,
          harnessTargetId: 'target-1',
        ),
        publisher: ConversationPublishSelection(
          connectorId: ConversationPublishConnectorId.githubApi,
        ),
      );

      expect(publishOnly.primaryActionLabel, isNot(pluginOnly.primaryActionLabel));
      expect(both.primaryActionLabel, isNot(pluginOnly.primaryActionLabel));
      expect(both.primaryActionLabel, isNot(publishOnly.primaryActionLabel));
      expect(noop.isEmpty, isTrue);
    });

    test('summary names the delivery target and the publish destination', () {
      const request = ConversationWorkflowRequest(
        plugin: ConversationPluginSelection(
          pluginId: ConversationPluginId.harnessWorkflow,
          harnessTargetId: 'target-1',
        ),
        publisher: ConversationPublishSelection(
          connectorId: ConversationPublishConnectorId.githubApi,
        ),
      );

      final summary = request.describe(
        availableTargets: [validTarget],
        github: connectedGitHub,
      );

      expect(summary, contains('ai-workspace-lab/xworkmate'));
      expect(summary, contains('haitaopanhq/knowledge'));
      expect(summary, contains('main'));
      expect(summary, isNot(contains('Bearer')));
    });

    test('summary never contains the token reference value', () {
      const request = ConversationWorkflowRequest(
        publisher: ConversationPublishSelection(
          connectorId: ConversationPublishConnectorId.githubApi,
        ),
      );

      final summary = request.describe(
        availableTargets: const [],
        github: connectedGitHub,
      );

      expect(summary, isNot(contains(connectedGitHub.tokenRef)));
    });
  });
}
