import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/app/app_controller_desktop_skill_permissions.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_sessions.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_storage.dart';
import 'package:xworkmate/app/app_controller_desktop_workspace_execution.dart';
import 'package:xworkmate/runtime/desktop_platform_service.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/skill_directory_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app-side runtime cleanup removes direct provider ACP side-channels', () {
    final workspaceExecution = File(
      'lib/app/app_controller_desktop_workspace_execution.dart',
    ).readAsStringSync();
    expect(
      workspaceExecution.contains("'skills.status'"),
      isFalse,
      reason:
          'single-agent skill refresh should not query provider ACP skills.status directly',
    );
    expect(
      workspaceExecution.contains('gatewayAcpClientInternal.request('),
      isFalse,
      reason: 'workspace execution should not issue direct provider ACP RPCs',
    );

    final runtimeCoordination = File(
      'lib/app/app_controller_desktop_runtime_coordination_impl.dart',
    );
    if (runtimeCoordination.existsSync()) {
      final source = runtimeCoordination.readAsStringSync();
      expect(
        source.contains('resolveSingleAgentEndpointRuntimeInternal'),
        isFalse,
        reason:
            'single-agent endpoint probing should not remain in app-side runtime coordination',
      );
      expect(
        source.contains('authorizationOverride'),
        isFalse,
        reason:
            'app-side runtime coordination should not own provider auth side-channels',
      );
      expect(
        source.contains('configuredCodexCliPath'),
        isFalse,
        reason:
            'runtime coordination should not pass configured Codex CLI paths into runtime flows',
      );
      expect(
        source.contains('resolvedCodexCliPath'),
        isFalse,
        reason:
            'runtime coordination should not retain detected Codex CLI paths',
      );
    }

    final settingsSnapshot = File(
      'lib/runtime/runtime_models_settings_snapshot.dart',
    ).readAsStringSync();
    expect(
      settingsSnapshot.contains('providerSyncDefinitions'),
      isFalse,
      reason:
          'settings snapshots should not persist provider catalog mirror data',
    );
    expect(
      settingsSnapshot.contains('codexCliPath'),
      isFalse,
      reason: 'settings snapshots should not persist app-side Codex CLI paths',
    );

    final accountModels = File(
      'lib/runtime/runtime_models_account.dart',
    ).readAsStringSync();
    expect(
      accountModels.contains('acpBridgeServerProfiles'),
      isFalse,
      reason:
          'account advanced overrides should not mirror bridge provider catalogs',
    );

    final orchestrator = File(
      'lib/runtime/code_agent_node_orchestrator.dart',
    ).readAsStringSync();
    expect(
      orchestrator.contains('configuredCodexCliPath'),
      isFalse,
      reason:
          'node metadata should not expose configured Codex CLI paths anymore',
    );
    expect(
      orchestrator.contains('resolvedCodexCliPath'),
      isFalse,
      reason:
          'node metadata should not expose detected Codex CLI paths anymore',
    );
    expect(
      orchestrator.contains('binaryConfigured'),
      isFalse,
      reason:
          'node metadata should not derive binaryConfigured from local CLI detection',
    );
  });

  test(
    'single-agent skill refresh stays bridge-owned and does not query provider endpoints directly',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'xworkmate-runtime-cleanup-test-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requestCount = 0;
      server.listen((request) async {
        requestCount += 1;
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        final method = payload['method']?.toString().trim() ?? '';
        final response = switch (method) {
          'acp.capabilities' => <String, dynamic>{
            'jsonrpc': '2.0',
            'id': payload['id'],
            'result': <String, dynamic>{
              'singleAgent': true,
              'multiAgent': false,
              'providerCatalog': <Map<String, dynamic>>[
                <String, dynamic>{'providerId': 'codex', 'label': 'Codex'},
              ],
            },
          },
          'skills.status' => <String, dynamic>{
            'jsonrpc': '2.0',
            'id': payload['id'],
            'result': <String, dynamic>{
              'skills': <Map<String, dynamic>>[
                <String, dynamic>{
                  'skillKey': 'remote-skill',
                  'name': 'Remote Skill',
                  'description': 'stale remote side-channel',
                },
              ],
            },
          },
          _ => <String, dynamic>{
            'jsonrpc': '2.0',
            'id': payload['id'],
            'result': <String, dynamic>{},
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });

      final store = SecureConfigStore(
        enableSecureStorage: false,
        appDataRootPathResolver: () async => root.path,
        secretRootPathResolver: () async => root.path,
        supportRootPathResolver: () async => root.path,
      );
      final controller = AppController(
        store: store,
        desktopPlatformService: UnsupportedDesktopPlatformService(),
        skillDirectoryAccessService: _FakeSkillDirectoryAccessService(
          root.path,
        ),
        goTaskServiceClient: const _FakeGoTaskServiceClient(),
        singleAgentSharedSkillScanRootOverrides: const <String>[],
      );
      _seedBridgeProviders(controller, const <SingleAgentProvider>[
        SingleAgentProvider.codex,
      ]);
      addTearDown(() async {
        controller.dispose();
        await server.close(force: true);
        if (root.existsSync()) {
          try {
            await root.delete(recursive: true);
          } catch (_) {}
        }
      });

      controller.settingsController.snapshotInternal = controller.settings;
      controller.lastObservedSettingsSnapshotInternal = controller.settings;

      const sessionKey = 'draft:runtime-cleanup';
      controller.initializeAssistantThreadContext(
        sessionKey,
        executionTarget: AssistantExecutionTarget.singleAgent,
        singleAgentProvider: SingleAgentProvider.codex,
      );
      controller.upsertTaskThreadInternal(
        sessionKey,
        executionTarget: AssistantExecutionTarget.singleAgent,
        singleAgentProvider: SingleAgentProvider.codex,
        executionTargetSource: ThreadSelectionSource.explicit,
        singleAgentProviderSource: ThreadSelectionSource.explicit,
      );

      expect(
        controller.assistantExecutionTargetForSession(sessionKey),
        AssistantExecutionTarget.singleAgent,
      );
      expect(
        controller.singleAgentProviderForSession(sessionKey),
        SingleAgentProvider.codex,
      );
      expect(
        controller.singleAgentResolvedProviderForSession(sessionKey),
        SingleAgentProvider.codex,
      );

      await controller.refreshSingleAgentSkillsForSession(sessionKey);

      expect(controller.assistantImportedSkillsForSession(sessionKey), isEmpty);
      expect(
        requestCount,
        0,
        reason:
            'single-agent skill refresh should not probe provider ACP endpoints directly',
      );
    },
  );

  test(
    'single-agent threads default to bridge catalog providers without reviving auto mode',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'xworkmate-provider-selection-test-',
      );
      final store = SecureConfigStore(
        enableSecureStorage: false,
        appDataRootPathResolver: () async => root.path,
        secretRootPathResolver: () async => root.path,
        supportRootPathResolver: () async => root.path,
      );
      final controller = AppController(
        store: store,
        desktopPlatformService: UnsupportedDesktopPlatformService(),
        skillDirectoryAccessService: _FakeSkillDirectoryAccessService(
          root.path,
        ),
        goTaskServiceClient: const _FakeGoTaskServiceClient(),
        singleAgentSharedSkillScanRootOverrides: const <String>[],
      );
      _seedBridgeProviders(controller, const <SingleAgentProvider>[
        SingleAgentProvider.codex,
      ]);
      addTearDown(() async {
        controller.dispose();
        if (root.existsSync()) {
          try {
            await root.delete(recursive: true);
          } catch (_) {}
        }
      });

      expect(
        controller.singleAgentProviderForSession('draft:bridge-default'),
        SingleAgentProvider.codex,
      );

      controller.initializeAssistantThreadContext(
        'draft:bridge-default',
        executionTarget: AssistantExecutionTarget.singleAgent,
      );

      expect(
        controller.singleAgentProviderForSession('draft:bridge-default'),
        SingleAgentProvider.codex,
      );
      expect(
        controller.singleAgentResolvedProviderForSession(
          'draft:bridge-default',
        ),
        SingleAgentProvider.codex,
      );

      final thread = controller.taskThreadForSessionInternal(
        'draft:bridge-default',
      );
      expect(thread, isNotNull);
      expect(thread!.hasExplicitProviderSelection, isFalse);
    },
  );

  group('thread restore provider semantics', () {
    const owner = ThreadOwnerScope(
      realm: ThreadRealm.local,
      subjectType: ThreadSubjectType.user,
      subjectId: 'u1',
      displayName: 'User',
    );

    TaskThread buildThread({
      required String threadId,
      required ThreadExecutionMode mode,
      required String providerId,
      String latestResolvedProviderId = '',
    }) {
      return TaskThread(
        threadId: threadId,
        ownerScope: owner,
        workspaceBinding: const WorkspaceBinding(
          workspaceId: 'ws-1',
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: '/tmp/ws',
          displayPath: '/tmp/ws',
          writable: true,
        ),
        executionBinding: ExecutionBinding(
          executionMode: mode,
          executorId: providerId,
          providerId: providerId,
          endpointId: '',
        ),
        latestResolvedProviderId: latestResolvedProviderId,
      );
    }

    test(
      'restore preserves the stored single-agent provider selection without inventing a resolved provider',
      () {
        final controller = AppController();
        _seedBridgeProviders(controller, const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ]);
        addTearDown(controller.dispose);

        const sessionKey = 'draft:restore-selection';
        controller.restoreAssistantThreadsInternal(<TaskThread>[
          buildThread(
            threadId: sessionKey,
            mode: ThreadExecutionMode.localAgent,
            providerId: 'legacy-provider',
          ),
        ]);

        final restored = controller.requireTaskThreadForSessionInternal(
          sessionKey,
        );
        expect(restored.executionBinding.providerId, 'legacy-provider');
        expect(
          controller.singleAgentProviderForSession(sessionKey).providerId,
          'legacy-provider',
        );
        expect(
          controller.singleAgentResolvedProviderForSession(sessionKey),
          isNull,
        );
      },
    );

    test(
      'restore continues to treat latestResolvedProviderId as the only resolved provider source',
      () {
        final controller = AppController();
        _seedBridgeProviders(controller, const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ]);
        addTearDown(controller.dispose);

        const sessionKey = 'draft:restore-resolved-provider';
        controller.restoreAssistantThreadsInternal(<TaskThread>[
          buildThread(
            threadId: sessionKey,
            mode: ThreadExecutionMode.localAgent,
            providerId: 'legacy-provider',
            latestResolvedProviderId: SingleAgentProvider.codex.providerId,
          ),
        ]);

        expect(
          controller.singleAgentProviderForSession(sessionKey).providerId,
          'legacy-provider',
        );
        expect(
          controller.singleAgentResolvedProviderForSession(sessionKey),
          SingleAgentProvider.codex,
        );
      },
    );

    test('restore still canonicalizes gateway provider bindings', () {
      final controller = AppController();
      addTearDown(controller.dispose);

      const sessionKey = 'draft:restore-gateway';
      controller.restoreAssistantThreadsInternal(<TaskThread>[
        buildThread(
          threadId: sessionKey,
          mode: ThreadExecutionMode.gateway,
          providerId: 'legacy-provider',
        ),
      ]);

      final restored = controller.requireTaskThreadForSessionInternal(
        sessionKey,
      );
      expect(restored.executionBinding.providerId, kCanonicalGatewayProviderId);
      expect(restored.executionBinding.executorId, kCanonicalGatewayProviderId);
    });
  });
}

void _seedBridgeProviders(
  AppController controller,
  List<SingleAgentProvider> providers,
) {
  controller.bridgeProviderCatalogInternal = providers;
}

class _FakeSkillDirectoryAccessService implements SkillDirectoryAccessService {
  const _FakeSkillDirectoryAccessService(this.homeDirectory);

  final String homeDirectory;

  @override
  bool get isSupported => false;

  @override
  Future<List<AuthorizedSkillDirectory>> authorizeDirectories({
    List<String> suggestedPaths = const <String>[],
  }) async {
    return const <AuthorizedSkillDirectory>[];
  }

  @override
  Future<AuthorizedSkillDirectory?> authorizeDirectory({
    String suggestedPath = '',
  }) async {
    return null;
  }

  @override
  Future<SkillDirectoryAccessHandle?> openDirectory(
    AuthorizedSkillDirectory directory,
  ) async {
    return null;
  }

  @override
  Future<String> resolveUserHomeDirectory() async {
    return homeDirectory;
  }
}

class _FakeGoTaskServiceClient implements GoTaskServiceClient {
  const _FakeGoTaskServiceClient();

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
    return const GoTaskServiceResult(
      success: true,
      message: '',
      turnId: '',
      raw: <String, dynamic>{},
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );
  }

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async {
    return const ExternalCodeAgentAcpCapabilities(
      singleAgent: true,
      multiAgent: false,
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
  }) async {
    return const ExternalCodeAgentAcpRoutingResolution(
      raw: <String, dynamic>{
        'resolvedExecutionTarget': 'single-agent',
        'resolvedEndpointTarget': 'singleAgent',
        'resolvedProviderId': 'codex',
        'resolvedModel': '',
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
