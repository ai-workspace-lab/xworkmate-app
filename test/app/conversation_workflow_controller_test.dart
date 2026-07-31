import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/connectors/conversation_publish_connector.dart';
import 'package:xworkmate/features/plugins/conversation_plugin.dart';
import 'package:xworkmate/features/plugins/harness_delivery_target.dart';
import 'package:xworkmate/features/settings/local_git_repository_connection.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

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

  Future<AppController> buildController({
    GitHubRepositoryConnectorConfig github = connectedGitHub,
    List<HarnessTarget> targets = const [validTarget],
    String token = '',
  }) async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    await controller.sessionsController.switchSession('workflow-session');
    controller.localSessionMessagesInternal['workflow-session'] =
        const <GatewayChatMessage>[
          GatewayChatMessage(
            id: 'm-1',
            role: 'user',
            text: 'publish this please',
            timestampMs: 1,
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
        ];
    if (token.isNotEmpty) {
      await controller.settingsController.saveSecretValueByRef(
        github.tokenRef,
        token,
        provider: 'GitHub',
        module: 'github_repository',
      );
    }
    controller.settingsController.snapshotInternal = controller.settings
        .copyWith(githubRepository: github, harnessTargets: targets);
    return controller;
  }

  test('a request with no publish connector issues no GitHub request', () async {
    final controller = await buildController();
    addTearDown(controller.dispose);

    var putCount = 0;
    await controller.runConversationWorkflow(
      const ConversationWorkflowRequest(
        plugin: ConversationPluginSelection(
          pluginId: ConversationPluginId.harnessWorkflow,
          harnessTargetId: 'target-1',
        ),
      ),
      put: (url, {required headers, required body}) async {
        putCount += 1;
        return http.Response('{}', 201);
      },
    );

    expect(putCount, 0);
  });

  test('a plugin that fails to start does not publish', () async {
    final controller = await buildController();
    addTearDown(controller.dispose);

    var putCount = 0;
    // No workspace is connected here, so the Harness run cannot start.
    final outcome = await controller.runConversationWorkflow(
      const ConversationWorkflowRequest(
        plugin: ConversationPluginSelection(
          pluginId: ConversationPluginId.harnessWorkflow,
          harnessTargetId: 'target-1',
        ),
        publisher: ConversationPublishSelection(
          connectorId: ConversationPublishConnectorId.githubApi,
        ),
      ),
      put: (url, {required headers, required body}) async {
        putCount += 1;
        return http.Response('{}', 201);
      },
    );

    expect(outcome.success, isFalse);
    expect(outcome.publishPending, isFalse);
    expect(putCount, 0);
  });

  test('an unconnected GitHub connector is rejected before any request', () async {
    final controller = await buildController(
      github: const GitHubRepositoryConnectorConfig(),
    );
    addTearDown(controller.dispose);

    var putCount = 0;
    final outcome = await controller.runConversationWorkflow(
      const ConversationWorkflowRequest(
        publisher: ConversationPublishSelection(
          connectorId: ConversationPublishConnectorId.githubApi,
        ),
      ),
      put: (url, {required headers, required body}) async {
        putCount += 1;
        return http.Response('{}', 201);
      },
    );

    expect(outcome.success, isFalse);
    expect(putCount, 0);
  });

  test('a request selecting nothing is rejected before any request', () async {
    final controller = await buildController();
    addTearDown(controller.dispose);

    var putCount = 0;
    final outcome = await controller.runConversationWorkflow(
      const ConversationWorkflowRequest(),
      put: (url, {required headers, required body}) async {
        putCount += 1;
        return http.Response('{}', 201);
      },
    );

    expect(outcome.success, isFalse);
    expect(putCount, 0);
  });

  test('publish-only issues exactly one Contents API request', () async {
    final controller = await buildController(token: 'test-token');
    addTearDown(controller.dispose);

    var putCount = 0;
    Uri? requestedUrl;
    final outcome = await controller.runConversationWorkflow(
      const ConversationWorkflowRequest(
        publisher: ConversationPublishSelection(
          connectorId: ConversationPublishConnectorId.githubApi,
        ),
      ),
      put: (url, {required headers, required body}) async {
        putCount += 1;
        requestedUrl = url;
        return http.Response('{}', 201);
      },
    );

    expect(outcome.success, isTrue);
    expect(putCount, 1);
    expect(requestedUrl!.host, 'api.github.com');
    expect(
      requestedUrl!.path,
      startsWith('/repos/haitaopanhq/knowledge/contents/conversations/'),
    );
  });
}
