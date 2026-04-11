import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_actions.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_sessions.dart';
import 'package:xworkmate/app/app_controller_desktop_workspace_execution.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('thread workingDirectory dispatch', () {
    test(
      'single-agent requests reuse the thread selected workingDirectory',
      () async {
        final client = _CapturingGoTaskServiceClient();
        final projectDir = Directory.systemTemp.createTempSync(
          'xworkmate-project-alpha-',
        );
        final controller = AppController(
          goTaskServiceClient: client,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
          ],
        );
        addTearDown(() async {
          controller.dispose();
          if (projectDir.existsSync()) {
            await projectDir.delete(recursive: true);
          }
        });

        const sessionKey = 'draft:single-agent-working-directory';
        controller.initializeAssistantThreadContext(
          sessionKey,
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession(sessionKey);
        await controller.saveAssistantSelectedWorkingDirectoryForSession(
          sessionKey,
          projectDir.path,
        );

        await controller.sendChatMessage('first turn');
        await controller.sendChatMessage('second turn');

        expect(client.requests, hasLength(2));
        expect(client.requests.map((item) => item.sessionId).toList(), <String>[
          sessionKey,
          sessionKey,
        ]);
        expect(client.requests.map((item) => item.threadId).toList(), <String>[
          sessionKey,
          sessionKey,
        ]);
        expect(
          client.requests.map((item) => item.workingDirectory).toList(),
          <String>[projectDir.path, projectDir.path],
        );
      },
    );

    test(
      'gateway threads persist their selected workingDirectory separately from workspace binding',
      () async {
        final projectDir = Directory.systemTemp.createTempSync(
          'xworkmate-project-beta-',
        );
        final controller = AppController(
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
          ],
        );
        addTearDown(() async {
          controller.dispose();
          if (projectDir.existsSync()) {
            await projectDir.delete(recursive: true);
          }
        });

        controller.appUiStateInternal = controller.appUiState.copyWith(
          savedGatewayTargets: const <String>['gateway'],
        );
        controller.lastObservedSettingsSnapshotInternal =
            controller.settingsController.snapshotInternal;

        const sessionKey = 'draft:gateway-working-directory';
        controller.initializeAssistantThreadContext(
          sessionKey,
          executionTarget: AssistantExecutionTarget.gateway,
        );
        await controller.switchSession(sessionKey);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );
        await controller.saveAssistantSelectedWorkingDirectoryForSession(
          sessionKey,
          projectDir.path,
        );

        final record = controller.requireTaskThreadForSessionInternal(
          sessionKey,
        );
        expect(
          controller.assistantExecutionTargetForSession(sessionKey),
          AssistantExecutionTarget.gateway,
        );
        expect(record.selectedWorkingDirectory, projectDir.path);
        expect(record.workspaceBinding.workspacePath, isNot(projectDir.path));
      },
    );
  });
}

class _CapturingGoTaskServiceClient implements GoTaskServiceClient {
  final List<GoTaskServiceRequest> requests = <GoTaskServiceRequest>[];

  @override
  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {}

  @override
  Future<void> closeTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    requests.add(request);
    return GoTaskServiceResult(
      success: true,
      message: 'ok',
      turnId: 'turn-${requests.length}',
      raw: <String, dynamic>{
        'resolvedExecutionTarget':
            request.target == AssistantExecutionTarget.gateway
            ? 'gateway'
            : 'single-agent',
        'resolvedEndpointTarget':
            request.target == AssistantExecutionTarget.gateway
            ? 'local'
            : 'singleAgent',
        'resolvedProviderId': request.provider.providerId,
        'resolvedWorkingDirectory': request.workingDirectory,
      },
      errorMessage: '',
      resolvedModel: request.model,
      route: request.route,
    );
  }

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    return const ExternalCodeAgentAcpCapabilities(
      singleAgent: true,
      multiAgent: true,
      providerCatalog: <SingleAgentProvider>[SingleAgentProvider.codex],
      gatewayProviders: <Map<String, dynamic>>[],
      raw: <String, dynamic>{},
    );
  }

  @override
  Future<ExternalCodeAgentAcpRoutingResolution> resolveExternalAcpRouting({
    required String taskPrompt,
    required String workingDirectory,
    required ExternalCodeAgentAcpRoutingConfig routing,
    String aiGatewayBaseUrl = '',
    String aiGatewayApiKey = '',
  }) async {
    return const ExternalCodeAgentAcpRoutingResolution(
      raw: <String, dynamic>{
        'resolvedExecutionTarget': 'single-agent',
        'resolvedEndpointTarget': 'singleAgent',
        'resolvedProviderId': 'codex',
        'resolvedGatewayProviderId': 'local',
        'resolvedModel': 'codex',
        'resolvedSkills': <String>[],
        'unavailable': false,
      },
    );
  }

  @override
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) async {}
}
