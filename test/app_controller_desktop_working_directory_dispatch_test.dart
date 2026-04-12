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
        );
        _seedBridgeProviders(controller, const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ]);
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
          2,
          reason:
              'single-agent turns should preflight through bridge routing.resolve once per turn before dispatch',
        );
      },
    );

    test(
      'single-agent turns stop before dispatch when BRIDGE_SERVER_URL is missing',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'xworkmate-missing-bridge-server-',
        );
        final store = SecureConfigStore(
          enableSecureStorage: false,
          appDataRootPathResolver: () async => '${root.path}/settings.sqlite3',
          secretRootPathResolver: () async => root.path,
          supportRootPathResolver: () async => root.path,
        );
        await store.initialize();
        final client = _CapturingGoTaskServiceClient(
          advertisedProviders: const <SingleAgentProvider>[],
        );
        final controller = AppController(
          store: store,
          goTaskServiceClient: client,
        );
        _seedBridgeProviders(controller, const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ]);
        addTearDown(() async {
          controller.dispose();
          store.dispose();
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });

        const sessionKey = 'draft:single-agent-missing-bridge-server';
        controller.initializeAssistantThreadContext(
          sessionKey,
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession(sessionKey);

        await controller.sendChatMessage('first turn');

        expect(client.requests, isEmpty);
        expect(
          client.resolveExternalAcpRoutingCallCount,
          0,
          reason:
              'single-agent turns should stop before routing.resolve when the bridge ACP entrypoint is missing',
        );
      },
    );

    test(
      'single-agent turns stop before routing when bridge has no advertised provider',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'xworkmate-missing-bridge-provider-',
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
        );
        addTearDown(() async {
          controller.dispose();
          store.dispose();
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });

        const sessionKey = 'draft:single-agent-missing-bridge-provider';
        controller.initializeAssistantThreadContext(
          sessionKey,
          executionTarget: AssistantExecutionTarget.singleAgent,
        );
        await controller.switchSession(sessionKey);
        _seedBridgeProviders(controller, const <SingleAgentProvider>[]);

        expect(controller.currentSingleAgentNeedsBridgeProvider, isTrue);

        await controller.sendChatMessage('first turn');

        expect(client.requests, isEmpty);
        expect(
          client.resolveExternalAcpRoutingCallCount,
          0,
          reason:
              'single-agent turns should not call routing.resolve when bridge provider state is already unavailable in app state',
        );
        expect(controller.chatMessages.last.text, 'Bridge 当前没有可用 Provider。');
      },
    );

    test('each task thread keeps an independent workingDirectory', () async {
      final controller = AppController();
      _seedBridgeProviders(controller, const <SingleAgentProvider>[
        SingleAgentProvider.codex,
      ]);
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
      final controller = AppController();
      _seedBridgeProviders(controller, const <SingleAgentProvider>[
        SingleAgentProvider.codex,
        SingleAgentProvider.gemini,
      ]);
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

void _seedBridgeProviders(
  AppController controller,
  List<SingleAgentProvider> providers,
) {
  controller.bridgeAdvertisedProvidersInternal = providers;
}

class _CapturingGoTaskServiceClient implements GoTaskServiceClient {
  _CapturingGoTaskServiceClient({
    this.advertisedProviders = const <SingleAgentProvider>[
      SingleAgentProvider.codex,
    ],
  });

  final List<SingleAgentProvider> advertisedProviders;
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
    return ExternalCodeAgentAcpCapabilities(
      singleAgent: true,
      multiAgent: true,
      providerCatalog: advertisedProviders,
      gatewayProviders: <Map<String, dynamic>>[],
      raw: <String, dynamic>{},
    );
  }

  @override
  Future<ExternalCodeAgentAcpRoutingResolution> resolveExternalAcpRouting({
    required String taskPrompt,
    required String workingDirectory,
    required ExternalCodeAgentAcpRoutingConfig routing,
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
