import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_controller_desktop_external_acp_routing.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_models.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
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
          environmentOverride: const <String, String>{},
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
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );
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
          environmentOverride: const <String, String>{},
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
          environmentOverride: const <String, String>{},
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
      'gateway target without a live gateway provider uses explicit gateway routing',
      () async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
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

        expect(routing.mode, ExternalCodeAgentAcpRoutingMode.explicit);
        expect(routing.explicitExecutionTarget, 'gateway');
        expect(routing.preferredGatewayTarget, 'openclaw');
        expect(routing.explicitProviderId, '');
      },
    );

    test(
      'bridge skill summaries preserve bridge key and name without remap',
      () {
        final option = skillOptionFromGatewayInternal(
          const GatewaySkillSummary(
            name: 'Browser Fetch',
            description: 'Bridge-managed browser skill',
            source: 'bridge',
            skillKey: 'browser-fetch',
            primaryEnv: null,
            eligible: true,
            disabled: false,
            missingBins: <String>[],
            missingEnv: <String>[],
            missingConfig: <String>[],
          ),
        );

        expect(option.key, 'browser-fetch');
        expect(option.label, 'Browser Fetch');
        expect(option.description, 'Bridge-managed browser skill');
      },
    );

    test(
      'locks the gateway provider catalog to the canonical openclaw contract',
      () {
        final controller = AppController(
          environmentOverride: const <String, String>{},
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
        await store.saveAccountSessionToken('session-token');
        await store.saveAccountSessionSummary(
          const AccountSessionSummary(
            userId: 'user-1',
            email: 'review@svc.plus',
            name: 'Review User',
            role: 'reviewer',
            mfaEnabled: true,
          ),
        );
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
        controller.bridgeCapabilitiesRefreshAttemptedInternal = true;
        controller.bridgeCapabilitiesRefreshErrorInternal = '';
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
              contains('请先登录 svc.plus'),
            ),
          ),
        );

        expect(fakeGoTaskService.executeCount, 0);
        expect(controller.chatMessages.last.text, contains('请先登录 svc.plus'));
      },
    );

    test(
      'sendChatMessage surfaces managed bridge auth failure before agent provider dispatch',
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
        await store.saveAccountSessionToken('session-token');
        await store.saveAccountSessionSummary(
          const AccountSessionSummary(
            userId: 'user-1',
            email: 'review@svc.plus',
            name: 'Review User',
            role: 'reviewer',
            mfaEnabled: true,
          ),
        );
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
          environmentOverride: <String, String>{
            'BRIDGE_AUTH_TOKEN': 'bridge-token',
          },
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
        );
        addTearDown(controller.dispose);

        controller.settingsControllerInternal.accountSessionTokenInternal =
            'session-token';
        controller.settingsControllerInternal.accountSessionInternal =
            const AccountSessionSummary(
              userId: 'user-1',
              email: 'review@svc.plus',
              name: 'Review User',
              role: 'reviewer',
              mfaEnabled: true,
            );
        controller.settingsControllerInternal.accountSyncStateInternal =
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
            );

        await controller.sessionsController.switchSession('session-1');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.agent,
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        controller.bridgeCapabilitiesRefreshAttemptedInternal = true;
        controller.bridgeCapabilitiesRefreshErrorInternal = '';

        await expectLater(
          controller.sendChatMessage('hi'),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              anyOf(contains('ACP_HTTP_401'), contains('请先登录 svc.plus')),
            ),
          ),
        );

        expect(fakeGoTaskService.executeCount, 0);
        expect(capture.requestCount, 0);
        if (controller.chatMessages.isNotEmpty) {
          expect(
            controller.chatMessages.last.text,
            anyOf(contains('ACP_HTTP_401'), contains('请先登录 svc.plus')),
          );
        }
      },
    );

    test(
      'sendChatMessage resumes only when the thread already has a committed user turn',
      () async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');
        expect(
          controller.hasCommittedUserTurnForGatewaySessionInternal('session-1'),
          isFalse,
        );

        controller.appendLocalSessionMessageInternal(
          'session-1',
          GatewayChatMessage(
            id: 'error-1',
            role: 'assistant',
            text: 'ACP_HTTP_CONNECTION_CLOSED',
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: true,
          ),
          persistInThreadContext: true,
        );

        expect(
          controller.hasCommittedUserTurnForGatewaySessionInternal('session-1'),
          isFalse,
        );

        controller.appendLocalSessionMessageInternal(
          'session-1',
          GatewayChatMessage(
            id: 'assistant-1',
            role: 'assistant',
            text: 'assistant-only history',
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
          persistInThreadContext: true,
        );

        expect(
          controller.hasCommittedUserTurnForGatewaySessionInternal('session-1'),
          isFalse,
        );

        controller.appendLocalSessionMessageInternal(
          'session-1',
          GatewayChatMessage(
            id: 'user-1',
            role: 'user',
            text: 'first turn',
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
          persistInThreadContext: true,
        );

        expect(
          controller.hasCommittedUserTurnForGatewaySessionInternal('session-1'),
          isTrue,
        );
      },
    );

    test('sendChatMessage starts an empty thread with session.start', () async {
      final fakeGoTaskService = _RecordingGoTaskServiceClient();
      final controller = _connectedController(fakeGoTaskService);
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('session-1');

      await controller.sendChatMessage('first turn');

      expect(fakeGoTaskService.requests, hasLength(1));
      expect(fakeGoTaskService.requests.single.resumeSession, isFalse);
    });

    test(
      'sendChatMessage continues the same session after ACP HTTP connection close',
      () async {
        final localWorkspace = await Directory.systemTemp.createTemp(
          'xworkmate-acp-interrupt-artifacts-',
        );
        addTearDown(() async {
          if (await localWorkspace.exists()) {
            await localWorkspace.delete(recursive: true);
          }
        });
        final fakeGoTaskService = _RecordingGoTaskServiceClient()
          ..updatesBeforeNextOutcome.add(
            const GoTaskServiceUpdate(
              sessionId: 'session-1',
              threadId: 'session-1',
              turnId: 'turn-1',
              type: 'delta',
              text: 'partial output that must not persist',
              message: '',
              pending: true,
              error: false,
              route: GoTaskServiceRoute.externalAcpSingle,
              payload: <String, dynamic>{},
            ),
          )
          ..outcomes.add(
            const GatewayAcpException(
              'ACP HTTP connection closed before the response finished arriving',
              code: 'ACP_HTTP_CONNECTION_CLOSED',
            ),
          )
          ..outcomes.add(
            GoTaskServiceResult(
              success: true,
              message: '全部 6 个文件已生成 ✅',
              turnId: 'turn-2',
              raw: <String, dynamic>{'artifacts': _generatedArtifactPayloads()},
              errorMessage: '',
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          );
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);
        controller.resolvedUserHomeDirectoryInternal = localWorkspace.path;

        await controller.sessionsController.switchSession('session-1');

        await controller.sendChatMessage('first turn');

        expect(fakeGoTaskService.requests, hasLength(1));
        expect(fakeGoTaskService.requests.single.resumeSession, isFalse);
        expect(
          controller
              .taskThreadForSessionInternal('session-1')
              ?.lifecycleState
              .status,
          'interrupted',
        );
        expect(
          controller.chatMessages.last.text,
          'Bridge 响应读取中断；当前对话已保留，下一次发送会继续同一会话。错误码：ACP_HTTP_CONNECTION_CLOSED',
        );
        expect(
          controller.chatMessages.map((message) => message.text),
          isNot(contains('partial output that must not persist')),
        );

        await controller.sendChatMessage('follow up');

        expect(fakeGoTaskService.requests, hasLength(2));
        expect(fakeGoTaskService.requests.last.resumeSession, isTrue);
        await _waitForLastChatMessageText(controller, '全部 6 个文件已生成 ✅');
        expect(controller.chatMessages.last.text, '全部 6 个文件已生成 ✅');
        final thread = controller.taskThreadForSessionInternal('session-1');
        expect(thread?.lifecycleState.status, 'ready');
        expect(thread?.lastArtifactSyncStatus, 'synced');
        expect(thread?.lastArtifactSyncAtMs, greaterThan(0));
        final workspacePath = controller.assistantWorkspacePathForSession(
          'session-1',
        );
        for (final artifact in _generatedArtifactPayloads()) {
          final relativePath = artifact['relativePath']! as String;
          final content = artifact['content']! as String;
          expect(
            await File('$workspacePath/$relativePath').readAsString(),
            content,
          );
        }
      },
    );

    test(
      'sendChatMessage starts a new session after ACP HTTP connect timeout',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient()
          ..outcomes.add(
            const GatewayAcpException(
              'ACP HTTP connection timed out before the request was confirmed',
              code: gatewayAcpHttpConnectTimeoutCode,
            ),
          )
          ..outcomes.add(
            const GoTaskServiceResult(
              success: true,
              message: 'retried from a confirmed new start',
              turnId: 'turn-2',
              raw: <String, dynamic>{},
              errorMessage: '',
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          );
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');

        await controller.sendChatMessage('first turn');

        expect(fakeGoTaskService.requests, hasLength(1));
        expect(fakeGoTaskService.requests.single.resumeSession, isFalse);
        final failedThread = controller.taskThreadForSessionInternal(
          'session-1',
        );
        expect(failedThread?.lifecycleState.status, 'ready');
        expect(
          failedThread?.lifecycleState.lastResultCode,
          gatewayAcpHttpConnectTimeoutCode,
        );
        expect(failedThread?.lastArtifactSyncStatus, isNull);
        expect(
          controller.chatMessages.last.text,
          'Bridge 连接超时，本轮请求未确认，可重试。错误码：ACP_HTTP_CONNECT_TIMEOUT',
        );

        await controller.sendChatMessage('retry after unconfirmed connect');

        expect(fakeGoTaskService.requests, hasLength(2));
        expect(fakeGoTaskService.requests.last.resumeSession, isFalse);
        await _waitForLastChatMessageText(
          controller,
          'retried from a confirmed new start',
        );
        expect(
          controller.chatMessages.last.text,
          'retried from a confirmed new start',
        );
        final thread = controller.taskThreadForSessionInternal('session-1');
        expect(thread?.lifecycleState.status, 'ready');
        expect(thread?.lifecycleState.lastResultCode, 'success');
      },
    );

    test(
      'sendChatMessage hides OpenClaw artifact guard text after an interrupted continuation',
      () async {
        final localWorkspace = await Directory.systemTemp.createTemp(
          'xworkmate-acp-interrupt-guard-',
        );
        addTearDown(() async {
          if (await localWorkspace.exists()) {
            await localWorkspace.delete(recursive: true);
          }
        });
        const guardMessage =
            '未检测到 OpenClaw 本轮导出的实际文件。已阻止口头下载声明进入 artifacts 面板；请重新执行并要求 OpenClaw 在 workspace 中真实生成文件。';
        final fakeGoTaskService = _RecordingGoTaskServiceClient()
          ..updatesBeforeNextOutcome.add(
            const GoTaskServiceUpdate(
              sessionId: 'session-1',
              threadId: 'session-1',
              turnId: 'turn-1',
              type: 'delta',
              text: 'guard partial output must not persist',
              message: '',
              pending: true,
              error: false,
              route: GoTaskServiceRoute.externalAcpSingle,
              payload: <String, dynamic>{},
            ),
          )
          ..outcomes.add(
            const GatewayAcpException(
              'ACP HTTP connection closed before the response finished arriving',
              code: 'ACP_HTTP_CONNECTION_CLOSED',
            ),
          )
          ..outcomes.add(
            const GoTaskServiceResult(
              success: true,
              message: guardMessage,
              turnId: 'turn-2',
              raw: <String, dynamic>{'code': 'OPENCLAW_NO_EXPORTED_ARTIFACTS'},
              errorMessage: '',
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          );
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);
        controller.resolvedUserHomeDirectoryInternal = localWorkspace.path;

        await controller.sessionsController.switchSession('session-1');

        await controller.sendChatMessage('first turn');
        await controller.sendChatMessage('follow up');

        expect(fakeGoTaskService.requests, hasLength(2));
        expect(fakeGoTaskService.requests.first.resumeSession, isFalse);
        expect(fakeGoTaskService.requests.last.resumeSession, isTrue);

        final transcript = controller.chatMessages
            .map((message) => message.text)
            .join('\n');
        expect(transcript, isNot(contains('未检测到 OpenClaw 本轮导出的实际文件')));
        expect(transcript, isNot(contains('口头下载声明')));
        expect(
          transcript,
          isNot(contains('guard partial output must not persist')),
        );

        final thread = controller.taskThreadForSessionInternal('session-1');
        expect(thread?.lifecycleState.status, 'ready');
        expect(thread?.lastArtifactSyncStatus, 'no-exported-artifacts');
        expect(thread?.lastArtifactSyncAtMs, greaterThan(0));
      },
    );

    test(
      'sendChatMessage hides OpenClaw artifact guard text from failed results and streaming',
      () async {
        final localWorkspace = await Directory.systemTemp.createTemp(
          'xworkmate-acp-guard-failure-',
        );
        addTearDown(() async {
          if (await localWorkspace.exists()) {
            await localWorkspace.delete(recursive: true);
          }
        });
        const guardMessage =
            '未检测到 OpenClaw 本轮导出的实际文件。已阻止口头下载声明进入 artifacts 面板；请重新执行并要求 OpenClaw 在 workspace 中真实生成文件。';
        final fakeGoTaskService = _RecordingGoTaskServiceClient()
          ..updatesBeforeNextOutcome.add(
            const GoTaskServiceUpdate(
              sessionId: 'session-1',
              threadId: 'session-1',
              turnId: 'turn-1',
              type: 'delta',
              text: guardMessage,
              message: '',
              pending: true,
              error: false,
              route: GoTaskServiceRoute.externalAcpSingle,
              payload: <String, dynamic>{},
            ),
          )
          ..outcomes.add(
            const GoTaskServiceResult(
              success: false,
              message: '',
              turnId: 'turn-1',
              raw: <String, dynamic>{'code': 'OPENCLAW_ARTIFACT_GUARD'},
              errorMessage: guardMessage,
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          );
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);
        controller.resolvedUserHomeDirectoryInternal = localWorkspace.path;

        await controller.sessionsController.switchSession('session-1');
        await controller.sendChatMessage('create files');

        final transcript = controller.chatMessages
            .map((message) => message.text)
            .join('\n');
        expect(transcript, isNot(contains('未检测到 OpenClaw 本轮导出的实际文件')));
        expect(transcript, isNot(contains('口头下载声明')));
        final thread = controller.taskThreadForSessionInternal('session-1');
        expect(thread?.lastArtifactSyncStatus, 'no-exported-artifacts');
        expect(thread?.lastArtifactSyncAtMs, greaterThan(0));
      },
    );

    test(
      'sendChatMessage continues the same session after ACP HTTP handshake interruption',
      () async {
        final localWorkspace = await Directory.systemTemp.createTemp(
          'xworkmate-acp-handshake-interrupt-artifacts-',
        );
        addTearDown(() async {
          if (await localWorkspace.exists()) {
            await localWorkspace.delete(recursive: true);
          }
        });
        final fakeGoTaskService = _RecordingGoTaskServiceClient()
          ..updatesBeforeNextOutcome.add(
            const GoTaskServiceUpdate(
              sessionId: 'session-1',
              threadId: 'session-1',
              turnId: 'turn-1',
              type: 'delta',
              text: 'handshake partial output must not persist',
              message: '',
              pending: true,
              error: false,
              route: GoTaskServiceRoute.externalAcpSingle,
              payload: <String, dynamic>{},
            ),
          )
          ..outcomes.add(
            const GatewayAcpException(
              'ACP HTTP handshake was interrupted before the response started',
              code: gatewayAcpHttpHandshakeInterruptedCode,
            ),
          )
          ..outcomes.add(
            GoTaskServiceResult(
              success: true,
              message: '全部 6 个文件已生成 ✅',
              turnId: 'turn-2',
              raw: <String, dynamic>{'artifacts': _generatedArtifactPayloads()},
              errorMessage: '',
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          );
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);
        controller.resolvedUserHomeDirectoryInternal = localWorkspace.path;

        await controller.sessionsController.switchSession('session-1');

        await controller.sendChatMessage('first turn');

        expect(fakeGoTaskService.requests, hasLength(1));
        expect(fakeGoTaskService.requests.single.resumeSession, isFalse);
        final interruptedThread = controller.taskThreadForSessionInternal(
          'session-1',
        );
        expect(interruptedThread?.lifecycleState.status, 'interrupted');
        expect(
          interruptedThread?.lifecycleState.lastResultCode,
          gatewayAcpHttpHandshakeInterruptedCode,
        );
        expect(
          controller.chatMessages.last.text,
          'Bridge 握手中断；当前对话已保留，下一次发送会继续同一会话。错误码：ACP_HTTP_HANDSHAKE_INTERRUPTED',
        );
        expect(
          controller.chatMessages.map((message) => message.text),
          isNot(contains('handshake partial output must not persist')),
        );

        await controller.sendChatMessage('follow up');

        expect(fakeGoTaskService.requests, hasLength(2));
        expect(fakeGoTaskService.requests.last.resumeSession, isTrue);
        await _waitForLastChatMessageText(controller, '全部 6 个文件已生成 ✅');
        expect(controller.chatMessages.last.text, '全部 6 个文件已生成 ✅');
        final thread = controller.taskThreadForSessionInternal('session-1');
        expect(thread?.lifecycleState.status, 'ready');
        expect(thread?.lastArtifactSyncStatus, 'synced');
        expect(thread?.lastArtifactSyncAtMs, greaterThan(0));
        final workspacePath = controller.assistantWorkspacePathForSession(
          'session-1',
        );
        for (final artifact in _generatedArtifactPayloads()) {
          final relativePath = artifact['relativePath']! as String;
          final content = artifact['content']! as String;
          expect(
            await File('$workspacePath/$relativePath').readAsString(),
            content,
          );
        }
      },
    );

    test(
      'chatMessages does not duplicate persisted local turn messages',
      () async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');

        final userMessage = GatewayChatMessage(
          id: 'local-user-1',
          role: 'user',
          text: 'hi',
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        );
        final assistantMessage = GatewayChatMessage(
          id: 'local-assistant-1',
          role: 'assistant',
          text: 'Bridge response',
          timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        );

        controller.appendLocalSessionMessageInternal(
          'session-1',
          userMessage,
          persistInThreadContext: true,
        );
        controller.appendLocalSessionMessageInternal(
          'session-1',
          assistantMessage,
          persistInThreadContext: true,
        );
        controller.assistantThreadMessagesInternal['session-1'] =
            List<GatewayChatMessage>.from(
              controller
                  .requireTaskThreadForSessionInternal('session-1')
                  .messages,
            );

        final visibleMessages = controller.chatMessages;

        expect(
          visibleMessages.where((message) => message.id == userMessage.id),
          hasLength(1),
        );
        expect(
          visibleMessages.where((message) => message.id == assistantMessage.id),
          hasLength(1),
        );
        expect(
          visibleMessages.map((message) => message.text),
          containsAllInOrder(<String>[userMessage.text, assistantMessage.text]),
        );
      },
    );

    test('sendChatMessage runs independent sessions concurrently', () async {
      final fakeGoTaskService = _BlockingGoTaskServiceClient();
      final controller = _connectedController(fakeGoTaskService);
      addTearDown(controller.dispose);

      await controller.switchSession('task-a');
      final taskAFuture = controller.sendChatMessage('task A');
      await fakeGoTaskService.waitForRequestCount(1);
      expect(fakeGoTaskService.requests.single.sessionId, 'task-a');
      expect(controller.assistantSessionHasPendingRun('task-a'), isTrue);

      await controller.switchSession('task-b');
      final taskBFuture = controller.sendChatMessage('task B');
      await fakeGoTaskService.waitForRequestCount(2);

      expect(
        fakeGoTaskService.requests.map((request) => request.sessionId),
        <String>['task-a', 'task-b'],
      );
      expect(controller.assistantSessionHasPendingRun('task-a'), isTrue);
      expect(controller.assistantSessionHasPendingRun('task-b'), isTrue);

      fakeGoTaskService.complete(
        'task-b',
        const GoTaskServiceResult(
          success: true,
          message: 'result B',
          turnId: 'turn-b',
          raw: <String, dynamic>{},
          errorMessage: '',
          resolvedModel: '',
          route: GoTaskServiceRoute.externalAcpSingle,
        ),
      );
      await taskBFuture;
      expect(controller.assistantSessionHasPendingRun('task-a'), isTrue);
      expect(controller.assistantSessionHasPendingRun('task-b'), isFalse);
      expect(
        controller.localSessionMessagesInternal['task-b']!.map(
          (message) => message.text,
        ),
        contains('result B'),
      );
      expect(
        controller.localSessionMessagesInternal['task-a']!.map(
          (message) => message.text,
        ),
        isNot(contains('result B')),
      );

      fakeGoTaskService.complete(
        'task-a',
        const GoTaskServiceResult(
          success: true,
          message: 'result A',
          turnId: 'turn-a',
          raw: <String, dynamic>{},
          errorMessage: '',
          resolvedModel: '',
          route: GoTaskServiceRoute.externalAcpSingle,
        ),
      );
      await taskAFuture;
      expect(controller.assistantSessionHasPendingRun('task-a'), isFalse);
      expect(
        controller.localSessionMessagesInternal['task-a']!.map(
          (message) => message.text,
        ),
        contains('result A'),
      );
    });

    test(
      'sendChatMessage keeps same-prompt draft task artifacts isolated',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-same-prompt-home-',
        );
        addTearDown(() async {
          if (await localHome.exists()) {
            await localHome.delete(recursive: true);
          }
        });
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);
        controller.resolvedUserHomeDirectoryInternal = localHome.path;

        const prompt = '用户要求我生成一个关于现代AI基础设施的技术营销内容';
        final uniqueSuffix = DateTime.now().microsecondsSinceEpoch.toString();
        final sessionA = 'draft-task-a-$uniqueSuffix';
        final sessionB = 'draft-task-b-$uniqueSuffix';
        addTearDown(() async {
          for (final sessionKey in <String>[sessionA, sessionB]) {
            final workspace = controller.assistantWorkspacePathForSession(
              sessionKey,
            );
            if (workspace.trim().isEmpty) {
              continue;
            }
            final directory = Directory(workspace);
            if (await directory.exists()) {
              await directory.delete(recursive: true);
            }
          }
        });

        await controller.switchSession(sessionA);
        final taskAFuture = controller.sendChatMessage(prompt);
        await fakeGoTaskService.waitForRequestCount(1);

        await controller.switchSession(sessionB);
        final taskBFuture = controller.sendChatMessage(prompt);
        await fakeGoTaskService.waitForRequestCount(2);

        final taskARequest = fakeGoTaskService.requests[0];
        final taskBRequest = fakeGoTaskService.requests[1];
        expect(taskARequest.sessionId, sessionA);
        expect(taskBRequest.sessionId, sessionB);
        expect(taskARequest.prompt, taskBRequest.prompt);
        expect(taskARequest.resumeSession, isFalse);
        expect(taskBRequest.resumeSession, isFalse);
        expect(taskARequest.workingDirectory, endsWith('/$sessionA'));
        expect(taskBRequest.workingDirectory, endsWith('/$sessionB'));
        expect(
          taskARequest.workingDirectory,
          isNot(taskBRequest.workingDirectory),
        );
        expect(
          taskARequest.remoteWorkingDirectoryHint,
          isNot(taskBRequest.remoteWorkingDirectoryHint),
        );
        expect(
          taskARequest.remoteWorkingDirectoryHint,
          endsWith('/threads/$sessionA'),
        );
        expect(
          taskBRequest.remoteWorkingDirectoryHint,
          endsWith('/threads/$sessionB'),
        );

        fakeGoTaskService.complete(
          sessionA,
          GoTaskServiceResult(
            success: true,
            message: 'result A',
            turnId: 'turn-a',
            raw: <String, dynamic>{
              'remoteWorkingDirectory':
                  '/home/ubuntu/.openclaw/workspace/tasks/$sessionA/turn-a',
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'same-prompt-a.md',
                  'content': 'artifact A',
                  'contentType': 'text/markdown',
                },
              ],
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await taskAFuture;

        fakeGoTaskService.complete(
          sessionB,
          GoTaskServiceResult(
            success: true,
            message: 'result B',
            turnId: 'turn-b',
            raw: <String, dynamic>{
              'remoteWorkingDirectory':
                  '/home/ubuntu/.openclaw/workspace/tasks/$sessionB/turn-b',
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'same-prompt-b.md',
                  'content': 'artifact B',
                  'contentType': 'text/markdown',
                },
              ],
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await taskBFuture;

        final taskAWorkspace = controller.assistantWorkspacePathForSession(
          sessionA,
        );
        final taskBWorkspace = controller.assistantWorkspacePathForSession(
          sessionB,
        );
        expect(
          await File('$taskAWorkspace/same-prompt-a.md').readAsString(),
          'artifact A',
        );
        expect(
          await File('$taskBWorkspace/same-prompt-b.md').readAsString(),
          'artifact B',
        );

        final taskAThread = controller.requireTaskThreadForSessionInternal(
          sessionA,
        );
        final taskBThread = controller.requireTaskThreadForSessionInternal(
          sessionB,
        );
        expect(taskAThread.lastArtifactSyncStatus, 'synced');
        expect(taskBThread.lastArtifactSyncStatus, 'synced');
        expect(taskAThread.lastTaskArtifactRelativePaths, <String>[
          'same-prompt-a.md',
        ]);
        expect(taskBThread.lastTaskArtifactRelativePaths, <String>[
          'same-prompt-b.md',
        ]);
        expect(
          taskAThread.lastRemoteWorkingDirectory,
          '/home/ubuntu/.openclaw/workspace/tasks/$sessionA/turn-a',
        );
        expect(
          taskBThread.lastRemoteWorkingDirectory,
          '/home/ubuntu/.openclaw/workspace/tasks/$sessionB/turn-b',
        );

        final taskBSnapshot = await controller.loadAssistantArtifactSnapshot(
          sessionKey: sessionB,
        );
        expect(
          taskBSnapshot.fileEntries.map((entry) => entry.relativePath),
          <String>['same-prompt-b.md'],
        );
      },
    );

    test(
      'sendChatMessage clears same-prompt draft task artifacts when no files return',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-same-prompt-empty-home-',
        );
        addTearDown(() async {
          if (await localHome.exists()) {
            await localHome.delete(recursive: true);
          }
        });
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);
        controller.resolvedUserHomeDirectoryInternal = localHome.path;

        const prompt = '用户要求我生成一个关于现代AI基础设施的技术营销内容';
        final uniqueSuffix = DateTime.now().microsecondsSinceEpoch.toString();
        final sessionA = 'draft-task-a-empty-$uniqueSuffix';
        final sessionB = 'draft-task-b-empty-$uniqueSuffix';
        addTearDown(() async {
          for (final sessionKey in <String>[sessionA, sessionB]) {
            final workspace = controller.assistantWorkspacePathForSession(
              sessionKey,
            );
            if (workspace.trim().isEmpty) {
              continue;
            }
            final directory = Directory(workspace);
            if (await directory.exists()) {
              await directory.delete(recursive: true);
            }
          }
        });

        await controller.switchSession(sessionA);
        final taskAFuture = controller.sendChatMessage(prompt);
        await fakeGoTaskService.waitForRequestCount(1);
        fakeGoTaskService.complete(
          sessionA,
          const GoTaskServiceResult(
            success: true,
            message: 'result A',
            turnId: 'turn-a',
            raw: <String, dynamic>{
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'same-prompt-a.md',
                  'content': 'artifact A',
                  'contentType': 'text/markdown',
                },
              ],
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await taskAFuture;

        await controller.switchSession(sessionB);
        final taskBFuture = controller.sendChatMessage(prompt);
        await fakeGoTaskService.waitForRequestCount(2);
        fakeGoTaskService.complete(
          sessionB,
          const GoTaskServiceResult(
            success: true,
            message: 'result B',
            turnId: 'turn-b',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await taskBFuture;

        final taskBThread = controller.requireTaskThreadForSessionInternal(
          sessionB,
        );
        expect(taskBThread.lastArtifactSyncStatus, 'no-artifacts');
        expect(taskBThread.lastTaskArtifactRelativePaths, isEmpty);

        final taskBSnapshot = await controller.loadAssistantArtifactSnapshot(
          sessionKey: sessionB,
        );
        expect(taskBSnapshot.fileEntries, isEmpty);
        expect(
          taskBSnapshot.filesMessage,
          'No files found in the recorded working directory.',
        );
      },
    );

    test('abortRun cancels only the current pending session', () async {
      final fakeGoTaskService = _BlockingGoTaskServiceClient();
      final controller = _connectedController(fakeGoTaskService);
      addTearDown(controller.dispose);

      await controller.switchSession('task-a');
      final taskAFuture = controller.sendChatMessage('task A');
      await fakeGoTaskService.waitForRequestCount(1);

      await controller.switchSession('task-b');
      final taskBFuture = controller.sendChatMessage('task B');
      await fakeGoTaskService.waitForRequestCount(2);
      fakeGoTaskService.emitDelta('task-b', 'streaming text');
      expect(controller.assistantSessionHasPendingRun('task-a'), isTrue);
      expect(controller.assistantSessionHasPendingRun('task-b'), isTrue);

      await controller.abortRun();

      expect(fakeGoTaskService.cancelledSessionIds, <String>['task-b']);
      expect(controller.assistantSessionHasPendingRun('task-a'), isTrue);
      expect(controller.assistantSessionHasPendingRun('task-b'), isFalse);
      expect(
        controller
            .requireTaskThreadForSessionInternal('task-b')
            .lifecycleState
            .lastResultCode,
        'aborted',
      );
      expect(
        controller.aiGatewayStreamingTextBySessionInternal['task-b'],
        isNull,
      );

      fakeGoTaskService.complete(
        'task-b',
        const GoTaskServiceResult(
          success: true,
          message: 'late result B',
          turnId: 'turn-b',
          raw: <String, dynamic>{},
          errorMessage: '',
          resolvedModel: '',
          route: GoTaskServiceRoute.externalAcpSingle,
        ),
      );
      await taskBFuture;
      expect(
        controller.localSessionMessagesInternal['task-b']!.map(
          (message) => message.text,
        ),
        isNot(contains('late result B')),
      );

      fakeGoTaskService.complete(
        'task-a',
        const GoTaskServiceResult(
          success: true,
          message: 'result A',
          turnId: 'turn-a',
          raw: <String, dynamic>{},
          errorMessage: '',
          resolvedModel: '',
          route: GoTaskServiceRoute.externalAcpSingle,
        ),
      );
      await taskAFuture;
      expect(
        controller.localSessionMessagesInternal['task-a']!.map(
          (message) => message.text,
        ),
        contains('result A'),
      );
    });

    test(
      'sendChatMessage exposes continuing and retrying lifecycle states',
      () async {
        late final AppController controller;
        final observedRequestStatuses = <String>[];
        final fakeGoTaskService = _BlockingGoTaskServiceClient(
          onRequest: (request) {
            observedRequestStatuses.add(
              controller
                      .taskThreadForSessionInternal(request.sessionId)
                      ?.lifecycleState
                      .status ??
                  '',
            );
          },
        );
        controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.switchSession('interrupted-task');
        controller.appendLocalSessionMessageInternal(
          'interrupted-task',
          GatewayChatMessage(
            id: 'user-interrupted',
            role: 'user',
            text: 'previous turn',
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
          persistInThreadContext: true,
        );
        controller.upsertTaskThreadInternal(
          'interrupted-task',
          lifecycleStatus: 'interrupted',
          lastResultCode: 'ACP_HTTP_CONNECTION_CLOSED',
        );
        expect(
          controller.hasCommittedUserTurnForGatewaySessionInternal(
            'interrupted-task',
          ),
          isTrue,
        );

        final continuingFuture = controller.sendChatMessage('continue');
        await fakeGoTaskService.waitForRequestCount(1);
        expect(observedRequestStatuses.single, 'continuing');
        expect(
          controller.assistantSessionHasPendingRun('interrupted-task'),
          isTrue,
        );
        fakeGoTaskService.complete(
          'interrupted-task',
          const GoTaskServiceResult(
            success: true,
            message: 'continued',
            turnId: 'turn-continued',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await continuingFuture;

        await controller.switchSession('retry-task');
        controller.appendLocalSessionMessageInternal(
          'retry-task',
          GatewayChatMessage(
            id: 'user-retry',
            role: 'user',
            text: 'previous failed turn',
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
          persistInThreadContext: true,
        );
        controller.upsertTaskThreadInternal(
          'retry-task',
          lifecycleStatus: 'ready',
          lastResultCode: 'error',
        );

        final retryFuture = controller.sendChatMessage('retry');
        await fakeGoTaskService.waitForRequestCount(2);
        expect(observedRequestStatuses.last, 'retrying');
        expect(controller.assistantSessionHasPendingRun('retry-task'), isTrue);
        fakeGoTaskService.complete(
          'retry-task',
          const GoTaskServiceResult(
            success: true,
            message: 'retried',
            turnId: 'turn-retried',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await retryFuture;
      },
    );
  });
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

Future<void> _waitForLastChatMessageText(
  AppController controller,
  String expectedText,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (controller.chatMessages.isNotEmpty &&
        controller.chatMessages.last.text == expectedText) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    controller.chatMessages.isEmpty ? '' : controller.chatMessages.last.text,
    expectedText,
  );
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

List<Map<String, dynamic>> _generatedArtifactPayloads() {
  return <Map<String, dynamic>>[
    <String, dynamic>{
      'relativePath': '网络与协议专题-图片生成提示词.md',
      'content': 'prompt content',
      'contentType': 'text/markdown',
    },
    <String, dynamic>{
      'relativePath': '小红书风格文案.md',
      'content': 'xiaohongshu copy',
      'contentType': 'text/markdown',
    },
    <String, dynamic>{
      'relativePath': 'X文案.md',
      'content': 'x copy',
      'contentType': 'text/markdown',
    },
    <String, dynamic>{
      'relativePath': '领英文案.md',
      'content': 'linkedin copy',
      'contentType': 'text/markdown',
    },
    <String, dynamic>{
      'relativePath': '云原生网络与协议专题.pptx',
      'content': 'pptx bytes',
      'contentType': 'application/octet-stream',
    },
    <String, dynamic>{
      'relativePath': 'PptxGenJS_脚本.js',
      'content': 'console.log("pptx");',
      'contentType': 'text/javascript',
    },
  ];
}

AppController _connectedController(GoTaskServiceClient client) {
  return AppController(
    goTaskServiceClient: client,
    environmentOverride: const <String, String>{
      'BRIDGE_AUTH_TOKEN': 'bridge-token',
    },
    initialBridgeProviderCatalog: const <SingleAgentProvider>[
      SingleAgentProvider.codex,
    ],
    initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
      AssistantExecutionTarget.agent,
    ],
  );
}

class _RecordingGoTaskServiceClient implements GoTaskServiceClient {
  int executeCount = 0;
  final List<GoTaskServiceRequest> requests = <GoTaskServiceRequest>[];
  final List<GoTaskServiceUpdate> updatesBeforeNextOutcome =
      <GoTaskServiceUpdate>[];
  final List<Object> outcomes = <Object>[];

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
    requests.add(request);
    for (final update in List<GoTaskServiceUpdate>.from(
      updatesBeforeNextOutcome,
    )) {
      onUpdate(update);
    }
    updatesBeforeNextOutcome.clear();
    if (outcomes.isNotEmpty) {
      final outcome = outcomes.removeAt(0);
      if (outcome is GoTaskServiceResult) {
        return outcome;
      }
      throw outcome;
    }
    return const GoTaskServiceResult(
      success: true,
      message: 'ok',
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

class _BlockingGoTaskServiceClient implements GoTaskServiceClient {
  _BlockingGoTaskServiceClient({this.onRequest});

  final void Function(GoTaskServiceRequest request)? onRequest;
  final List<GoTaskServiceRequest> requests = <GoTaskServiceRequest>[];
  final List<String> cancelledSessionIds = <String>[];
  final Map<String, Completer<GoTaskServiceResult>> _pending =
      <String, Completer<GoTaskServiceResult>>{};
  final Map<String, void Function(GoTaskServiceUpdate)> _updates =
      <String, void Function(GoTaskServiceUpdate)>{};

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
  }) {
    requests.add(request);
    onRequest?.call(request);
    _updates[request.sessionId] = onUpdate;
    final completer = Completer<GoTaskServiceResult>();
    _pending[request.sessionId] = completer;
    return completer.future;
  }

  Future<void> waitForRequestCount(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (requests.length < count && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (requests.length < count) {
      throw StateError('Timed out waiting for $count requests.');
    }
  }

  void complete(String sessionId, GoTaskServiceResult result) {
    final completer = _pending.remove(sessionId);
    _updates.remove(sessionId);
    if (completer == null) {
      throw StateError('No pending task for $sessionId.');
    }
    completer.complete(result);
  }

  void emitDelta(String sessionId, String text) {
    final onUpdate = _updates[sessionId];
    if (onUpdate == null) {
      throw StateError('No pending update sink for $sessionId.');
    }
    onUpdate(
      GoTaskServiceUpdate(
        sessionId: sessionId,
        threadId: sessionId,
        turnId: 'turn-$sessionId',
        type: 'delta',
        text: text,
        message: '',
        pending: true,
        error: false,
        route: GoTaskServiceRoute.externalAcpSingle,
        payload: const <String, dynamic>{},
      ),
    );
  }

  @override
  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
  }) async {
    cancelledSessionIds.add(sessionId);
  }

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
