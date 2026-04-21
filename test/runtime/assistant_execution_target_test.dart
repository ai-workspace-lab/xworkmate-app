import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_controller_desktop_external_acp_routing.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  group('AssistantExecutionTarget', () {
    test('maps agent and gateway values without collapsing them', () {
      expect(
        threadExecutionModeFromAssistantExecutionTarget(
          AssistantExecutionTarget.agent,
        ),
        ThreadExecutionMode.agent,
      );
      expect(
        threadExecutionModeFromAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        ),
        ThreadExecutionMode.gateway,
      );
      expect(
        assistantExecutionTargetFromExecutionMode(ThreadExecutionMode.agent),
        AssistantExecutionTarget.agent,
      );
      expect(
        assistantExecutionTargetFromExecutionMode(ThreadExecutionMode.gateway),
        AssistantExecutionTarget.gateway,
      );
    });

    test('keeps both task dialog modes visible when both are supported', () {
      expect(
        compactAssistantExecutionTargets(const <AssistantExecutionTarget>[
          AssistantExecutionTarget.agent,
          AssistantExecutionTarget.gateway,
        ]),
        const <AssistantExecutionTarget>[
          AssistantExecutionTarget.agent,
          AssistantExecutionTarget.gateway,
        ],
      );
    });

    test('recognizes openclaw as the canonical gateway provider', () {
      final provider = SingleAgentProvider.fromJsonValue('openclaw');

      expect(provider.providerId, kCanonicalGatewayProviderId);
      expect(provider.label, kCanonicalGatewayProviderLabel);
    });

    test(
      'switching a session to gateway uses the bridge-provided gateway catalog',
      () async {
        final controller = AppController(
          initialBridgeProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
            SingleAgentProvider.opencode,
            SingleAgentProvider.gemini,
          ],
          initialGatewayProviderCatalog: <SingleAgentProvider>[
            SingleAgentProvider.openclaw.copyWith(
              logoEmoji: '🦞',
              supportedTargets: const <AssistantExecutionTarget>[
                AssistantExecutionTarget.gateway,
              ],
            ),
          ],
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');

        expect(controller.currentAssistantExecutionTarget.isAgent, isTrue);
        expect(
          controller.assistantProviderForSession(controller.currentSessionKey),
          SingleAgentProvider.unspecified,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        final record = controller.requireTaskThreadForSessionInternal(
          'session-1',
        );
        expect(
          controller.assistantExecutionTargetForSession('session-1').isGateway,
          isTrue,
        );
        expect(
          assistantExecutionTargetFromExecutionMode(
            record.executionBinding.executionMode,
          ),
          AssistantExecutionTarget.gateway,
        );
        expect(
          controller.assistantProviderForSession('session-1'),
          SingleAgentProvider.openclaw,
        );
      },
    );

    test(
      'returns unspecified when a saved provider is no longer in the current catalog',
      () {
        final controller = AppController();
        addTearDown(controller.dispose);

        final unavailableProvider = controller
            .resolveProviderForExecutionTarget(
              'gemini',
              executionTarget: AssistantExecutionTarget.agent,
            );

        expect(unavailableProvider.isUnspecified, isTrue);
      },
    );

    test(
      'does not recover a stale gateway provider from an empty gateway catalog',
      () {
        final controller = AppController(
          initialBridgeProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
            SingleAgentProvider.opencode,
            SingleAgentProvider.gemini,
          ],
        );
        addTearDown(controller.dispose);

        final provider = controller.resolveProviderForExecutionTarget(
          'openclaw',
          executionTarget: AssistantExecutionTarget.gateway,
        );

        expect(provider.isUnspecified, isTrue);
      },
    );

    test(
      'switching a session to gateway with an empty gateway catalog keeps provider selection inherited',
      () async {
        final controller = AppController(
          initialBridgeProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
            SingleAgentProvider.opencode,
            SingleAgentProvider.gemini,
          ],
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        final record = controller.requireTaskThreadForSessionInternal(
          'session-1',
        );

        expect(
          controller.assistantExecutionTargetForSession('session-1'),
          AssistantExecutionTarget.gateway,
        );
        expect(record.executionBinding.providerId, isEmpty);
        expect(
          record.executionBinding.providerSource,
          ThreadSelectionSource.inherited,
        );
        expect(record.hasExplicitProviderSelection, isFalse);
      },
    );

    test(
      'gateway target without a live gateway provider falls back to auto routing',
      () async {
        final controller = AppController(
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        final routing = controller.buildExternalAcpRoutingForSessionInternal(
          'session-1',
        );

        expect(routing.isAuto, isTrue);
        expect(routing.explicitExecutionTarget, isEmpty);
        expect(routing.explicitProviderId, isEmpty);
      },
    );

    test(
      'locks the gateway provider catalog to the canonical openclaw contract',
      () {
        final controller = AppController(
          initialGatewayProviderCatalog: <SingleAgentProvider>[
            SingleAgentProvider.fromJsonValue(
              'hermes',
              label: 'Hermes',
              badge: 'H',
              supportedTargets: const <AssistantExecutionTarget>[
                AssistantExecutionTarget.gateway,
              ],
            ),
            SingleAgentProvider.openclaw.copyWith(
              supportedTargets: const <AssistantExecutionTarget>[
                AssistantExecutionTarget.gateway,
              ],
            ),
          ],
        );
        addTearDown(controller.dispose);

        expect(
          controller
              .providerCatalogForExecutionTarget(
                AssistantExecutionTarget.gateway,
              )
              .map((item) => item.providerId)
              .toList(growable: false),
          const <String>['openclaw'],
        );
      },
    );

    test(
      'does not refresh agent provider catalog when agent mode is selected with an empty catalog',
      () async {
        final capture = await _startCapabilityServer();
        addTearDown(capture.close);

        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-agent-provider-refresh-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here. The controller may still be
              // releasing files when teardown starts.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveAccountSyncState(
          AccountSyncState.defaults().copyWith(
            syncedDefaults: AccountRemoteProfile.defaults().copyWith(
              bridgeServerUrl: capture.baseEndpoint.toString(),
            ),
            syncState: 'ready',
            tokenConfigured: const AccountTokenConfigured(
              bridge: true,
              vault: false,
              apisix: false,
            ),
          ),
        );
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
          value: 'bridge-token',
        );

        final controller = AppController(
          store: store,
          environmentOverride: <String, String>{},
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(controller.assistantProviderCatalog, isEmpty);
        final requestCountBefore = capture.requestCount;

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.agent,
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(controller.assistantProviderCatalog, isEmpty);
        expect(capture.requestCount, lessThanOrEqualTo(requestCountBefore + 2));
        if (capture.requestCount > requestCountBefore) {
          expect(capture.lastAuthorizationHeader, 'Bearer bridge-token');
        }
      },
    );

    test(
      'sendChatMessage fails locally without bridge sync token and does not execute ACP task',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-missing-bridge-token-send-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here.
            }
          }
        });
        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();

        final controller = AppController(
          store: store,
          goTaskServiceClient: fakeGoTaskService,
          environmentOverride: const <String, String>{},
          initialBridgeProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
          ],
          initialGatewayProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.openclaw,
          ],
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        await expectLater(
          controller.sendChatMessage('hi'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('xworkmate-bridge 未连接'),
            ),
          ),
        );

        expect(fakeGoTaskService.executeCount, 0);
        expect(
          controller.chatMessages.last.text,
          contains('xworkmate-bridge 未连接'),
        );
      },
    );

    test(
      'sendChatMessage refreshes capabilities and fails locally when agent provider catalog stays empty',
      () async {
        final capture = await _startEmptyCapabilityServer();
        addTearDown(capture.close);

        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final storeRoot = await Directory.systemTemp.createTemp(
          'xworkmate-empty-gateway-provider-send-',
        );
        addTearDown(() async {
          if (await storeRoot.exists()) {
            try {
              await storeRoot.delete(recursive: true);
            } on FileSystemException {
              // Temp cleanup is best effort here. The controller may still be
              // releasing files when teardown starts.
            }
          }
        });

        final store = SecureConfigStore(
          secretRootPathResolver: () async => '${storeRoot.path}/secrets',
          appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
          supportRootPathResolver: () async => '${storeRoot.path}/support',
          enableSecureStorage: false,
        );
        await store.initialize();
        await store.saveAccountSyncState(
          AccountSyncState.defaults().copyWith(
            syncedDefaults: AccountRemoteProfile.defaults().copyWith(
              bridgeServerUrl: capture.baseEndpoint.toString(),
            ),
            syncState: 'ready',
            tokenConfigured: const AccountTokenConfigured(
              bridge: true,
              vault: false,
              apisix: false,
            ),
          ),
        );
        await store.saveAccountManagedSecret(
          target: kAccountManagedSecretTargetBridgeAuthToken,
          value: 'bridge-token',
        );

        final controller = AppController(
          store: store,
          goTaskServiceClient: fakeGoTaskService,
          environmentOverride: <String, String>{},
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        await _waitForRequest(capture, minimumCount: 1);
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.agent,
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));

        await expectLater(
          controller.sendChatMessage('hi'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('agent provider'),
            ),
          ),
        );

        expect(fakeGoTaskService.executeCount, 0);
        expect(capture.requestCount, greaterThanOrEqualTo(3));
        expect(controller.chatMessages.last.text, contains('agent provider'));
      },
    );
  });
}

Future<void> _waitForRequest(
  _CapabilityServerCapture capture, {
  required int minimumCount,
}) async {
  for (var index = 0; index < 20; index += 1) {
    if (capture.requestCount >= minimumCount) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $minimumCount capability requests');
}

Future<_CapabilityServerCapture> _startCapabilityServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final capture = _CapabilityServerCapture._(
    server,
    Uri.parse('http://127.0.0.1:${server.port}'),
  );
  server.listen((request) async {
    capture.requestCount += 1;
    capture.lastAuthorizationHeader =
        request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    await utf8.decoder.bind(request).join();
    if (capture.requestCount == 1) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'error': <String, dynamic>{'message': 'startup refresh failed'},
        }),
      );
      await request.response.close();
      return;
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'capabilities',
        'result': <String, dynamic>{
          'singleAgent': true,
          'multiAgent': true,
          'providerCatalog': <Map<String, dynamic>>[
            <String, dynamic>{'providerId': 'codex', 'label': 'Codex'},
            <String, dynamic>{'providerId': 'opencode', 'label': 'OpenCode'},
            <String, dynamic>{'providerId': 'gemini', 'label': 'Gemini'},
          ],
        },
      }),
    );
    await request.response.close();
  });
  return capture;
}

Future<_CapabilityServerCapture> _startEmptyCapabilityServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final capture = _CapabilityServerCapture._(
    server,
    Uri.parse('http://127.0.0.1:${server.port}'),
  );
  server.listen((request) async {
    capture.requestCount += 1;
    capture.lastAuthorizationHeader =
        request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'capabilities',
        'result': <String, dynamic>{
          'singleAgent': false,
          'multiAgent': true,
          'availableExecutionTargets': const <String>[],
          'providerCatalog': const <Map<String, dynamic>>[],
          'gatewayProviders': const <Map<String, dynamic>>[],
        },
      }),
    );
    await request.response.close();
  });
  return capture;
}

class _CapabilityServerCapture {
  _CapabilityServerCapture._(this._server, this.baseEndpoint);

  final HttpServer _server;
  final Uri baseEndpoint;
  int requestCount = 0;
  String lastAuthorizationHeader = '';

  Future<void> close() => _server.close(force: true);
}

class _RecordingGoTaskServiceClient implements GoTaskServiceClient {
  int executeCount = 0;

  @override
  Future<ExternalCodeAgentAcpCapabilities> loadExternalAcpCapabilities({
    required AssistantExecutionTarget target,
    bool forceRefresh = false,
  }) async => const ExternalCodeAgentAcpCapabilities.empty();

  @override
  Future<ExternalCodeAgentAcpRoutingResolution> resolveExternalAcpRouting({
    required String taskPrompt,
    required String workingDirectory,
    required ExternalCodeAgentAcpRoutingConfig routing,
  }) async =>
      const ExternalCodeAgentAcpRoutingResolution(raw: <String, dynamic>{});

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    executeCount += 1;
    return const GoTaskServiceResult(
      success: true,
      message: 'unexpected executeTask call',
      turnId: 'turn',
      raw: <String, dynamic>{},
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );
  }

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
}
