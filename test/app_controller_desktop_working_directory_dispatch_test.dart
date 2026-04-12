import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/app/app_controller_desktop_runtime_helpers.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_actions.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_sessions.dart';
import 'package:xworkmate/app/app_controller_desktop_workspace_execution.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('thread workingDirectory dispatch', () {
    test(
      'single-agent requests reuse the unique thread workspace workingDirectory',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'xworkmate-thread-working-directory-',
        );
        final store = SecureConfigStore(
          enableSecureStorage: false,
          appDataRootPathResolver: () async => '${root.path}/settings.sqlite3',
          secretRootPathResolver: () async => root.path,
          supportRootPathResolver: () async => root.path,
        );
        await store.initialize();
        await store.saveSettingsSnapshot(
          SettingsSnapshot.defaults().copyWith(
            acpBridgeServerModeConfig: SettingsSnapshot.defaults()
                .acpBridgeServerModeConfig
                .copyWith(
                  cloudSynced: SettingsSnapshot.defaults()
                      .acpBridgeServerModeConfig
                      .cloudSynced
                      .copyWith(
                        remoteServerSummary:
                            const AcpBridgeServerRemoteServerSummary(
                              endpoint: 'https://bridge.customer.example',
                              hasAdvancedOverrides: false,
                            ),
                      ),
                ),
          ),
        );
        final client = _CapturingGoTaskServiceClient();
        final controller = AppController(
          store: store,
          goTaskServiceClient: client,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
          ],
        );
        addTearDown(() async {
          controller.dispose();
          store.dispose();
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });

        const sessionKey = 'draft:single-agent-working-directory';
        controller.initializeAssistantThreadContext(
          sessionKey,
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession(sessionKey);
        final expectedThreadWorkingDirectory = controller
            .requireTaskThreadForSessionInternal(sessionKey)
            .workspaceBinding
            .workspacePath;

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
          <String>[
            expectedThreadWorkingDirectory,
            expectedThreadWorkingDirectory,
          ],
        );
        expect(
          client.resolveExternalAcpRoutingCallCount,
          0,
          reason:
              'single-agent turns should go straight to session.start/session.message without app-side routing preflight',
        );
      },
    );

    test(
      'single-agent turns go through the canonical bridge entry without synced endpoint state',
      () async {
        final client = _CapturingGoTaskServiceClient();
        final controller = AppController(
          goTaskServiceClient: client,
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
          ],
        );
        addTearDown(controller.dispose);

        const sessionKey = 'draft:single-agent-missing-bridge-server';
        controller.initializeAssistantThreadContext(
          sessionKey,
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession(sessionKey);

        await controller.sendChatMessage('first turn');

        expect(client.requests, hasLength(1));
        expect(client.requests.single.sessionId, sessionKey);
        expect(client.requests.single.threadId, sessionKey);
      },
    );

    test('each task thread keeps an independent workingDirectory', () async {
      final controller = AppController(
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
      );
      addTearDown(controller.dispose);

      const sessionKey = 'draft:thread-working-directory-a';
      const otherSessionKey = 'draft:thread-working-directory-b';
      controller.initializeAssistantThreadContext(
        sessionKey,
        executionTarget: AssistantExecutionTarget.singleAgent,
      );
      controller.initializeAssistantThreadContext(
        otherSessionKey,
        executionTarget: AssistantExecutionTarget.singleAgent,
      );
      final recordA = controller.requireTaskThreadForSessionInternal(
        sessionKey,
      );
      final recordB = controller.requireTaskThreadForSessionInternal(
        otherSessionKey,
      );
      expect(
        controller.assistantWorkingDirectoryForSessionInternal(sessionKey),
        recordA.workspaceBinding.workspacePath,
      );
      expect(
        controller.assistantWorkingDirectoryForSessionInternal(otherSessionKey),
        recordB.workspaceBinding.workspacePath,
      );
      expect(
        recordA.workspaceBinding.workspacePath,
        isNot(recordB.workspaceBinding.workspacePath),
      );
    });

    test('new task threads do not inherit another thread provider choice', () {
      final controller = AppController(
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
          SingleAgentProvider.gemini,
        ],
      );
      addTearDown(controller.dispose);

      const firstSessionKey = 'draft:thread-provider-a';
      const secondSessionKey = 'draft:thread-provider-b';

      controller.initializeAssistantThreadContext(
        firstSessionKey,
        executionTarget: AssistantExecutionTarget.singleAgent,
        singleAgentProvider: SingleAgentProvider.gemini,
      );
      controller.initializeAssistantThreadContext(
        secondSessionKey,
        executionTarget: AssistantExecutionTarget.singleAgent,
      );

      expect(
        controller.singleAgentProviderForSession(firstSessionKey),
        SingleAgentProvider.gemini,
      );
      expect(
        controller.singleAgentProviderForSession(secondSessionKey),
        SingleAgentProvider.codex,
      );
    });
  });
}

class _CapturingGoTaskServiceClient implements GoTaskServiceClient {
  final List<GoTaskServiceRequest> requests = <GoTaskServiceRequest>[];
  int resolveExternalAcpRoutingCallCount = 0;

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
    resolveExternalAcpRoutingCallCount += 1;
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
