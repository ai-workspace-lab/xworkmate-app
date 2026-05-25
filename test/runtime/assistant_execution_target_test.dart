import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_controller_desktop_external_acp_routing.dart';
import 'package:xworkmate/app/app_controller_openclaw_task_queue.dart';
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
      'normalizes OpenClaw from provider catalog into selectable gateway mode',
      () async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
          initialBridgeProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
            SingleAgentProvider.openclaw,
          ],
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
          ],
        );
        addTearDown(controller.dispose);

        expect(
          controller.assistantProviderCatalog.map((item) => item.providerId),
          const <String>['codex'],
        );
        expect(
          controller.gatewayProviderCatalog.map((item) => item.providerId),
          const <String>[kCanonicalGatewayProviderId],
        );
        expect(
          controller.bridgeAvailableExecutionTargets,
          const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
        );

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        expect(
          controller.assistantProviderForSession('unit-fixture-task-a'),
          SingleAgentProvider.openclaw,
        );
      },
    );

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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );

        expect(controller.currentAssistantExecutionTarget.isAgent, isTrue);
        expect(
          controller.assistantProviderForSession(controller.currentSessionKey),
          SingleAgentProvider.unspecified,
        );

        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        final record = controller.requireTaskThreadForSessionInternal(
          'unit-fixture-task-a',
        );
        expect(
          record.executionBinding.executionMode,
          ThreadExecutionMode.gateway,
        );
        expect(
          controller.assistantProviderForSession('unit-fixture-task-a'),
          SingleAgentProvider.openclaw,
        );
      },
    );

    test(
      'new task sessions do not inherit execution target from main',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-no-main-target-inheritance-',
        );
        addTearDown(() async {
          if (await localHome.exists()) {
            await localHome.delete(recursive: true);
          }
        });
        final controller = AppController(
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
        controller.resolvedUserHomeDirectoryInternal = localHome.path;

        expect(
          () => controller.upsertTaskThreadInternal(
            'main',
            executionTarget: AssistantExecutionTarget.gateway,
            selectedProvider: SingleAgentProvider.openclaw,
            selectedProviderSource: ThreadSelectionSource.explicit,
          ),
          throwsStateError,
        );

        expect(
          controller.assistantExecutionTargetForSession('draft:fresh-task'),
          AssistantExecutionTarget.agent,
        );

        await controller.switchSession('draft:fresh-task');

        final freshThread = controller.requireTaskThreadForSessionInternal(
          'draft:fresh-task',
        );
        expect(
          freshThread.executionBinding.executionMode,
          ThreadExecutionMode.agent,
        );
        expect(
          freshThread.workspaceBinding.workspacePath,
          endsWith('/.xworkmate/threads/draft-fresh-task'),
        );
      },
    );

    test('allocates unique draft session keys for repeated task creation', () {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      final first = controller.createAssistantDraftSessionKeyInternal();
      controller.initializeAssistantThreadContext(
        first,
        executionTarget: AssistantExecutionTarget.agent,
        messageViewMode: AssistantMessageViewMode.rendered,
      );
      final second = controller.createAssistantDraftSessionKeyInternal();

      expect(first, startsWith('draft:'));
      expect(second, startsWith('draft:'));
      expect(second, isNot(first));
    });

    test('navigateHome does not select the runtime main session key', () async {
      final localHome = await Directory.systemTemp.createTemp(
        'xworkmate-no-runtime-main-home-',
      );
      addTearDown(() async {
        if (await localHome.exists()) {
          await localHome.delete(recursive: true);
        }
      });
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);
      controller.resolvedUserHomeDirectoryInternal = localHome.path;
      controller.runtimeInternal.snapshotInternal = controller
          .runtimeInternal
          .snapshot
          .copyWith(mainSessionKey: 'session-1');

      const taskKey = 'draft:test-home-task';
      await controller.switchSession(taskKey);

      controller.navigateHome();
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentSessionKey, taskKey);
      expect(
        controller.assistantWorkspacePathForSession(taskKey),
        endsWith('/.xworkmate/threads/draft-test-home-task'),
      );
      expect(controller.assistantWorkspacePathForSession('session-1'), isEmpty);
      expect(controller.taskThreadForSessionInternal('session-1'), isNull);
    });

    test(
      'refreshSessions allocates an app task instead of runtime main when current is stale',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-refresh-no-session-one-',
        );
        addTearDown(() async {
          if (await localHome.exists()) {
            await localHome.delete(recursive: true);
          }
        });
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );
        addTearDown(controller.dispose);
        controller.resolvedUserHomeDirectoryInternal = localHome.path;
        controller.runtimeInternal.snapshotInternal = controller
            .runtimeInternal
            .snapshot
            .copyWith(mainSessionKey: 'session-1');

        await controller.refreshSessions();

        expect(controller.currentSessionKey, startsWith('draft:'));
        expect(controller.currentSessionKey, isNot('session-1'));
        expect(controller.currentSessionKey, isNot('main'));
        expect(
          controller.assistantWorkspacePathForSession(
            controller.currentSessionKey,
          ),
          contains('/.xworkmate/threads/draft-'),
        );
        expect(
          controller.assistantWorkspacePathForSession('session-1'),
          isEmpty,
        );
      },
    );

    test('assistant task list ignores runtime sessions from the gateway', () {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);
      controller.sessionsControllerInternal.sessionsInternal =
          const <GatewaySessionSummary>[
            GatewaySessionSummary(
              key: 'session-1',
              kind: 'assistant',
              displayName: 'runtime session',
              surface: 'Assistant',
              subject: null,
              room: null,
              space: null,
              updatedAtMs: 1,
              sessionId: 'session-1',
              systemSent: false,
              abortedLastRun: false,
              thinkingLevel: null,
              verboseLevel: null,
              inputTokens: null,
              outputTokens: null,
              totalTokens: null,
              model: null,
              contextTokens: null,
              derivedTitle: null,
              lastMessagePreview: null,
            ),
          ];
      controller.initializeAssistantThreadContext(
        'draft:test-visible-task',
        executionTarget: AssistantExecutionTarget.agent,
        messageViewMode: AssistantMessageViewMode.rendered,
      );

      final keys = controller.assistantSessions.map((item) => item.key);

      expect(keys, contains('draft:test-visible-task'));
      expect(keys, isNot(contains('session-1')));
    });

    test(
      'switching sessions does not refresh task ordering timestamp',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-stable-task-selection-home-',
        );
        addTearDown(() async {
          if (await localHome.exists()) {
            await localHome.delete(recursive: true);
          }
        });
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );
        addTearDown(controller.dispose);
        controller.resolvedUserHomeDirectoryInternal = localHome.path;

        const newerTask = 'draft:newer-task';
        const olderTask = 'draft:older-task';
        const newerUpdatedAtMs = 2000.0;
        const olderUpdatedAtMs = 1000.0;
        controller.upsertTaskThreadInternal(
          newerTask,
          executionTarget: AssistantExecutionTarget.gateway,
          messageViewMode: AssistantMessageViewMode.rendered,
          updatedAtMs: newerUpdatedAtMs,
        );
        controller.upsertTaskThreadInternal(
          olderTask,
          executionTarget: AssistantExecutionTarget.gateway,
          messageViewMode: AssistantMessageViewMode.rendered,
          updatedAtMs: olderUpdatedAtMs,
        );

        await controller.switchSession(olderTask);

        expect(controller.currentSessionKey, olderTask);
        expect(
          controller.requireTaskThreadForSessionInternal(olderTask).updatedAtMs,
          olderUpdatedAtMs,
        );
        expect(
          controller.assistantSessions.map((item) => item.key).take(2),
          <String>[newerTask, olderTask],
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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        final record = controller.requireTaskThreadForSessionInternal(
          'unit-fixture-task-a',
        );

        expect(
          controller.assistantExecutionTargetForSession('unit-fixture-task-a'),
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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        final routing = controller.buildExternalAcpRoutingForSessionInternal(
          'unit-fixture-task-a',
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
        expect(option.groupLabel, 'Gateway Skills');
        expect(option.icon, Icons.key_rounded);
      },
    );

    test('all bridge skill sources remain selectable and routed', () async {
      final fakeGoTaskService = _RecordingGoTaskServiceClient();
      final controller = _connectedGatewayController(fakeGoTaskService);
      addTearDown(controller.dispose);
      controller.skillsControllerInternal.itemsInternal =
          const <GatewaySkillSummary>[
            GatewaySkillSummary(
              name: 'Workspace PDF',
              description: 'Write PDF documents',
              source: 'openclaw-workspace',
              skillKey: 'pdf',
              primaryEnv: null,
              eligible: true,
              disabled: false,
              missingBins: <String>[],
              missingEnv: <String>[],
              missingConfig: <String>[],
            ),
            GatewaySkillSummary(
              name: 'Browser Automation',
              description: 'Use browser automation',
              source: 'agents-skills-personal',
              skillKey: 'browser-automation',
              primaryEnv: null,
              eligible: true,
              disabled: false,
              missingBins: <String>[],
              missingEnv: <String>[],
              missingConfig: <String>[],
            ),
            GatewaySkillSummary(
              name: 'Gateway Search',
              description: 'Search through the gateway',
              source: 'gateway',
              skillKey: 'gateway-search',
              primaryEnv: null,
              eligible: true,
              disabled: false,
              missingBins: <String>[],
              missingEnv: <String>[],
              missingConfig: <String>[],
            ),
          ];
      await _selectGatewaySession(controller, 'unit-skill-source-groups-task');

      await controller.toggleAssistantSkillForSession(
        'unit-skill-source-groups-task',
        'browser-automation',
      );

      final routing = controller.buildExternalAcpRoutingForSessionInternal(
        'unit-skill-source-groups-task',
      );
      expect(routing.availableSkills.map((item) => item.id), const <String>[
        'pdf',
        'browser-automation',
        'gateway-search',
      ]);
      expect(routing.explicitSkills, const <String>['browser-automation']);
      expect(
        controller.assistantSelectedSkillKeysForSession(
          'unit-skill-source-groups-task',
        ),
        const <String>['browser-automation'],
      );

      await controller.sendChatMessage(
        '打开网页完成检查',
        selectedSkillLabels: const <String>[
          'Browser Automation (browser-automation)',
        ],
      );

      expect(fakeGoTaskService.requests, hasLength(1));
      expect(fakeGoTaskService.requests.single.selectedSkills, const <String>[
        'Browser Automation (browser-automation)',
      ]);
    });

    test(
      'selected bridge skill is passed to task context with stable key',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(controller.dispose);
        controller.skillsControllerInternal.itemsInternal =
            const <GatewaySkillSummary>[
              GatewaySkillSummary(
                name: 'PDF Writer',
                description: 'Write PDF documents',
                source: 'openclaw-workspace',
                skillKey: 'pdf',
                primaryEnv: null,
                eligible: true,
                disabled: false,
                missingBins: <String>[],
                missingEnv: <String>[],
                missingConfig: <String>[],
              ),
            ];
        await _selectGatewaySession(controller, 'unit-skill-context-task');
        await controller.toggleAssistantSkillForSession(
          'unit-skill-context-task',
          'pdf',
        );

        await controller.sendChatMessage(
          '生成 PDF',
          selectedSkillLabels: const <String>['PDF Writer (pdf)'],
        );

        expect(fakeGoTaskService.requests, hasLength(1));
        final request = fakeGoTaskService.requests.single;
        expect(request.selectedSkills, const <String>['PDF Writer (pdf)']);
        expect(request.prompt, contains('Preferred skills:'));
        expect(request.prompt, contains('- PDF Writer (pdf)'));
      },
    );

    test('skill selection ignores stale non-bridge skill keys', () {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);
      controller.initializeAssistantThreadContext(
        'unit-skill-source-task',
        executionTarget: AssistantExecutionTarget.gateway,
        messageViewMode: AssistantMessageViewMode.rendered,
      );
      controller.upsertTaskThreadInternal(
        'unit-skill-source-task',
        selectedSkillKeys: const <String>['stale-non-bridge-skill'],
        selectedSkillsSource: ThreadSelectionSource.explicit,
      );
      controller.skillsControllerInternal.itemsInternal =
          const <GatewaySkillSummary>[
            GatewaySkillSummary(
              name: 'Bridge Skill',
              description: 'Bridge skill',
              source: 'bridge',
              skillKey: 'bridge-skill',
              primaryEnv: null,
              eligible: true,
              disabled: false,
              missingBins: <String>[],
              missingEnv: <String>[],
              missingConfig: <String>[],
            ),
          ];

      final routing = controller.buildExternalAcpRoutingForSessionInternal(
        'unit-skill-source-task',
      );

      expect(routing.availableSkills.map((item) => item.id), const <String>[
        'bridge-skill',
      ]);
      expect(routing.explicitSkills, isEmpty);
      expect(
        controller.assistantSelectedSkillKeysForSession(
          'unit-skill-source-task',
        ),
        isEmpty,
      );
    });

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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );
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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );
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
              ),
            );

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );
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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );
        expect(
          controller.hasCommittedUserTurnForGatewaySessionInternal(
            'unit-fixture-task-a',
          ),
          isFalse,
        );

        controller.appendLocalSessionMessageInternal(
          'unit-fixture-task-a',
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
          controller.hasCommittedUserTurnForGatewaySessionInternal(
            'unit-fixture-task-a',
          ),
          isFalse,
        );

        controller.appendLocalSessionMessageInternal(
          'unit-fixture-task-a',
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
          controller.hasCommittedUserTurnForGatewaySessionInternal(
            'unit-fixture-task-a',
          ),
          isFalse,
        );

        controller.appendLocalSessionMessageInternal(
          'unit-fixture-task-a',
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
          controller.hasCommittedUserTurnForGatewaySessionInternal(
            'unit-fixture-task-a',
          ),
          isTrue,
        );
        expect(
          controller.shouldResumeGatewaySessionForNextSendInternal(
            'unit-fixture-task-a',
          ),
          isTrue,
        );

        controller.upsertTaskThreadInternal(
          'unit-fixture-task-a',
          lastResultCode: gatewayAcpHttpConnectTimeoutCode,
        );
        expect(
          controller.shouldResumeGatewaySessionForNextSendInternal(
            'unit-fixture-task-a',
          ),
          isFalse,
        );
      },
    );

    test('sendChatMessage starts an empty thread with session.start', () async {
      final fakeGoTaskService = _RecordingGoTaskServiceClient();
      final controller = _connectedController(fakeGoTaskService);
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('unit-fixture-task-a');

      await controller.sendChatMessage('first turn');

      expect(fakeGoTaskService.requests, hasLength(1));
      final request = fakeGoTaskService.requests.single;
      expect(request.resumeSession, isFalse);
      expect(request.prompt, contains('TaskThread workspace context:'));
      expect(request.prompt, contains('- sessionKey: unit-fixture-task-a'));
      expect(request.prompt, contains(request.workingDirectory));
      expect(request.prompt, contains(request.remoteWorkingDirectoryHint));
      expect(request.prompt, contains('User request:\nfirst turn'));
      expect(
        controller.chatMessages.map((message) => message.text),
        contains('first turn'),
      );
      expect(
        controller.chatMessages.map((message) => message.text).join('\n'),
        isNot(contains('TaskThread workspace context:')),
      );
    });

    test(
      'sendChatMessage forwards inline attachment content and size',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('attachment-task');
        await controller.sendChatMessage(
          'use attachment',
          attachments: <GatewayChatAttachmentPayload>[
            GatewayChatAttachmentPayload(
              type: 'file',
              mimeType: 'text/plain',
              fileName: 'note.txt',
              content: base64Encode(utf8.encode('note body')),
            ),
          ],
        );

        final request = fakeGoTaskService.requests.single;
        expect(request.inlineAttachments, hasLength(1));
        final params = request.toExternalAcpParams();
        final inlineAttachments = params['inlineAttachments'] as List<dynamic>;
        final inlineAttachment =
            inlineAttachments.single as Map<String, dynamic>;
        expect(inlineAttachment['name'], 'note.txt');
        expect(inlineAttachment['mimeType'], 'text/plain');
        expect(
          inlineAttachment['content'],
          base64Encode(utf8.encode('note body')),
        );
        expect(inlineAttachment['sizeBytes'], 9);
        final attachments = params['attachments'] as List<dynamic>;
        final attachment = attachments.single as Map<String, dynamic>;
        expect(attachment['name'], 'note.txt');
        expect(attachment['path'], isEmpty);
      },
    );

    test(
      'sendChatMessage resumes existing task after response interruption',
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
              sessionId: 'unit-fixture-task-a',
              threadId: 'unit-fixture-task-a',
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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );

        await controller.sendChatMessage('first turn');

        expect(fakeGoTaskService.requests, hasLength(1));
        expect(fakeGoTaskService.requests.single.resumeSession, isFalse);
        expect(
          controller
              .taskThreadForSessionInternal('unit-fixture-task-a')
              ?.lifecycleState
              .status,
          'ready',
        );
        expect(
          controller.chatMessages.last.text,
          'Bridge 响应读取中断，本轮结果未完成。请重新发送请求。错误码：ACP_HTTP_CONNECTION_CLOSED',
        );
        expect(
          controller.chatMessages.map((message) => message.text),
          isNot(contains('partial output that must not persist')),
        );
        expect(
          controller
              .taskThreadForSessionInternal('unit-fixture-task-a')
              ?.lastArtifactSyncStatus,
          'failed',
        );

        await controller.sendChatMessage('follow up');

        expect(fakeGoTaskService.requests, hasLength(2));
        expect(fakeGoTaskService.requests.last.resumeSession, isTrue);
        expect(
          controller.localSessionMessagesInternal['unit-fixture-task-a']!.map(
            (message) => message.text,
          ),
          contains('全部 6 个文件已生成 ✅'),
        );
        final thread = controller.taskThreadForSessionInternal(
          'unit-fixture-task-a',
        );
        expect(thread?.lifecycleState.status, 'ready');
        expect(thread?.lastArtifactSyncStatus, 'synced');
        expect(thread?.lastArtifactSyncAtMs, greaterThan(0));
        final workspacePath = controller.assistantWorkspacePathForSession(
          'unit-fixture-task-a',
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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );

        await controller.sendChatMessage('first turn');

        expect(fakeGoTaskService.requests, hasLength(1));
        expect(fakeGoTaskService.requests.single.resumeSession, isFalse);
        final failedThread = controller.taskThreadForSessionInternal(
          'unit-fixture-task-a',
        );
        expect(failedThread?.lifecycleState.status, 'ready');
        expect(
          failedThread?.lifecycleState.lastResultCode,
          gatewayAcpHttpConnectTimeoutCode,
        );
        expect(failedThread?.lastArtifactSyncStatus, 'failed');
        expect(failedThread?.lastTaskArtifactRelativePaths, isEmpty);
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
        final thread = controller.taskThreadForSessionInternal(
          'unit-fixture-task-a',
        );
        expect(thread?.lifecycleState.status, 'ready');
        expect(thread?.lifecycleState.lastResultCode, 'success');
      },
    );

    test(
      'sendChatMessage restarts before handling OpenClaw artifact guard results',
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
              sessionId: 'unit-fixture-task-a',
              threadId: 'unit-fixture-task-a',
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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );

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

        final thread = controller.taskThreadForSessionInternal(
          'unit-fixture-task-a',
        );
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
              sessionId: 'unit-fixture-task-a',
              threadId: 'unit-fixture-task-a',
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
              raw: <String, dynamic>{
                'status': 'artifact_missing',
                'code': 'OPENCLAW_ARTIFACT_MISSING',
                'artifactWarnings': <String>[
                  'OpenClaw artifact export returned no files for a file-delivery request.',
                ],
              },
              errorMessage: guardMessage,
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          );
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);
        controller.resolvedUserHomeDirectoryInternal = localWorkspace.path;

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );
        await controller.sendChatMessage('create files');

        final transcript = controller.chatMessages
            .map((message) => message.text)
            .join('\n');
        expect(transcript, isNot(contains('未检测到 OpenClaw 本轮导出的实际文件')));
        expect(transcript, isNot(contains('口头下载声明')));
        final thread = controller.taskThreadForSessionInternal(
          'unit-fixture-task-a',
        );
        expect(thread?.lifecycleState.lastResultCode, 'artifact_missing');
        expect(thread?.lastArtifactSyncStatus, 'no-exported-artifacts');
        expect(thread?.lastArtifactSyncAtMs, greaterThan(0));
      },
    );

    test(
      'sendChatMessage restarts after ACP HTTP handshake interruption',
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
              sessionId: 'unit-fixture-task-a',
              threadId: 'unit-fixture-task-a',
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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );

        await controller.sendChatMessage('first turn');

        expect(fakeGoTaskService.requests, hasLength(1));
        expect(fakeGoTaskService.requests.single.resumeSession, isFalse);
        final failedThread = controller.taskThreadForSessionInternal(
          'unit-fixture-task-a',
        );
        expect(failedThread?.lifecycleState.status, 'ready');
        expect(
          failedThread?.lifecycleState.lastResultCode,
          gatewayAcpHttpHandshakeInterruptedCode,
        );
        expect(failedThread?.lastArtifactSyncStatus, 'failed');
        expect(
          controller.chatMessages.last.text,
          'Bridge 握手中断，本轮请求未完成。请重新发送请求。错误码：ACP_HTTP_HANDSHAKE_INTERRUPTED',
        );
        expect(
          controller.chatMessages.map((message) => message.text),
          isNot(contains('handshake partial output must not persist')),
        );

        await controller.sendChatMessage('follow up');

        expect(fakeGoTaskService.requests, hasLength(2));
        expect(fakeGoTaskService.requests.last.resumeSession, isFalse);
        await _waitForLastChatMessageText(controller, '全部 6 个文件已生成 ✅');
        expect(controller.chatMessages.last.text, '全部 6 个文件已生成 ✅');
        final thread = controller.taskThreadForSessionInternal(
          'unit-fixture-task-a',
        );
        expect(thread?.lifecycleState.status, 'ready');
        expect(thread?.lastArtifactSyncStatus, 'synced');
        expect(thread?.lastArtifactSyncAtMs, greaterThan(0));
        final workspacePath = controller.assistantWorkspacePathForSession(
          'unit-fixture-task-a',
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

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );

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
          'unit-fixture-task-a',
          userMessage,
          persistInThreadContext: true,
        );
        controller.appendLocalSessionMessageInternal(
          'unit-fixture-task-a',
          assistantMessage,
          persistInThreadContext: true,
        );
        controller.assistantThreadMessagesInternal['unit-fixture-task-a'] =
            List<GatewayChatMessage>.from(
              controller
                  .requireTaskThreadForSessionInternal('unit-fixture-task-a')
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
      'background task completion does not overwrite the selected session',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-background-completion-home-',
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

        const sessionA = 'background-task-a';
        const sessionB = 'background-task-b';
        await controller.switchSession(sessionA);
        final taskAFuture = controller.sendChatMessage('生成 A 的 markdown 文件');
        await fakeGoTaskService.waitForRequestCount(1);

        await controller.switchSession(sessionB);
        final taskBFuture = controller.sendChatMessage('生成 B 的 markdown 文件');
        await fakeGoTaskService.waitForRequestCount(2);
        expect(controller.currentSessionKey, sessionB);

        fakeGoTaskService.complete(
          sessionA,
          const GoTaskServiceResult(
            success: true,
            message: 'result A',
            turnId: 'turn-a',
            raw: <String, dynamic>{
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'a.md',
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

        expect(controller.currentSessionKey, sessionB);
        expect(
          controller.chatMessages.map((message) => message.text),
          isNot(contains('result A')),
        );
        expect(
          controller
              .requireTaskThreadForSessionInternal(sessionA)
              .lastArtifactSyncStatus,
          'synced',
        );
        expect(
          controller
              .requireTaskThreadForSessionInternal(sessionB)
              .lastArtifactSyncStatus,
          'running',
        );
        final sessionBSnapshot = await controller.loadAssistantArtifactSnapshot(
          sessionKey: sessionB,
        );
        expect(sessionBSnapshot.resultEntries, isEmpty);
        expect(
          controller
              .requireTaskThreadForSessionInternal(sessionB)
              .lastTaskArtifactRelativePaths,
          isEmpty,
        );
        expect(
          await File(
            '${controller.assistantWorkspacePathForSession(sessionA)}/a.md',
          ).readAsString(),
          'artifact A',
        );

        fakeGoTaskService.complete(
          sessionB,
          const GoTaskServiceResult(
            success: true,
            message: 'result B',
            turnId: 'turn-b',
            raw: <String, dynamic>{
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'b.md',
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

        expect(controller.currentSessionKey, sessionB);
        expect(
          controller.chatMessages.map((message) => message.text),
          contains('result B'),
        );
        expect(
          controller.chatMessages.map((message) => message.text),
          isNot(contains('result A')),
        );
        final completedSessionBPaths =
            (await controller.loadAssistantArtifactSnapshot(
              sessionKey: sessionB,
            )).fileEntries.map((entry) => entry.relativePath).toList();
        expect(completedSessionBPaths, contains('b.md'));
        expect(completedSessionBPaths, isNot(contains('a.md')));
      },
    );

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
        expect(taskARequest.prompt, isNot(taskBRequest.prompt));
        expect(taskARequest.prompt, contains(prompt));
        expect(taskBRequest.prompt, contains(prompt));
        expect(taskARequest.resumeSession, isFalse);
        expect(taskBRequest.resumeSession, isFalse);
        expect(taskARequest.workingDirectory, endsWith('/$sessionA'));
        expect(taskBRequest.workingDirectory, endsWith('/$sessionB'));
        expect(taskARequest.prompt, contains(taskARequest.workingDirectory));
        expect(taskBRequest.prompt, contains(taskBRequest.workingDirectory));
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

    test(
      'sendChatMessage accepts artifact-only task success as terminal output',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-artifact-only-home-',
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

        await controller.switchSession('artifact-only-task');
        final taskFuture = controller.sendChatMessage('create only a file');
        await fakeGoTaskService.waitForRequestCount(1);
        fakeGoTaskService.complete(
          'artifact-only-task',
          const GoTaskServiceResult(
            success: true,
            message: '',
            turnId: 'turn-artifact-only',
            raw: <String, dynamic>{
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'artifact-only.md',
                  'content': 'artifact-only body',
                  'contentType': 'text/markdown',
                },
              ],
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await taskFuture;

        final workspacePath = controller.assistantWorkspacePathForSession(
          'artifact-only-task',
        );
        final thread = controller.requireTaskThreadForSessionInternal(
          'artifact-only-task',
        );
        expect(thread.lifecycleState.lastResultCode, 'success');
        expect(thread.lastArtifactSyncStatus, 'synced');
        expect(thread.lastTaskArtifactRelativePaths, hasLength(1));
        final recordedPath = thread.lastTaskArtifactRelativePaths.single;
        expect(recordedPath, matches(RegExp(r'^artifact-only(\.v\d+)?\.md$')));
        expect(
          await File('$workspacePath/$recordedPath').readAsString(),
          'artifact-only body',
        );
        expect(
          controller.localSessionMessagesInternal['artifact-only-task']!.where(
            (message) => message.error,
          ),
          isEmpty,
        );
      },
    );

    test(
      'sendChatMessage clears stale current artifacts on terminal task failure',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-terminal-failure-home-',
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

        await controller.switchSession('terminal-failure-task');
        final firstFuture = controller.sendChatMessage('create first file');
        await fakeGoTaskService.waitForRequestCount(1);
        fakeGoTaskService.complete(
          'terminal-failure-task',
          const GoTaskServiceResult(
            success: true,
            message: 'first result',
            turnId: 'turn-first',
            raw: <String, dynamic>{
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'first.md',
                  'content': 'first body',
                  'contentType': 'text/markdown',
                },
              ],
              'remoteWorkingDirectory': '/remote/first-run',
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await firstFuture;

        final secondFuture = controller.sendChatMessage('second run fails');
        await fakeGoTaskService.waitForRequestCount(2);
        fakeGoTaskService.complete(
          'terminal-failure-task',
          const GoTaskServiceResult(
            success: false,
            message: '',
            turnId: 'turn-second',
            raw: <String, dynamic>{'status': 'failed'},
            errorMessage: 'second run failed',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await secondFuture;

        final thread = controller.requireTaskThreadForSessionInternal(
          'terminal-failure-task',
        );
        expect(thread.lifecycleState.lastResultCode, 'failed');
        expect(thread.lastArtifactSyncStatus, 'failed');
        expect(thread.lastTaskArtifactRelativePaths, isEmpty);
        expect(thread.lastRemoteWorkingDirectory?.trim(), isEmpty);

        final snapshot = await controller.loadAssistantArtifactSnapshot(
          sessionKey: 'terminal-failure-task',
        );
        expect(snapshot.resultEntries, isEmpty);
        expect(
          snapshot.fileEntries.map((entry) => entry.relativePath),
          contains('first.md'),
        );
      },
    );

    test(
      'sendChatMessage clears stale current artifacts when output is empty',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-empty-output-home-',
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

        await controller.switchSession('empty-output-task');
        final firstFuture = controller.sendChatMessage('create first file');
        await fakeGoTaskService.waitForRequestCount(1);
        fakeGoTaskService.complete(
          'empty-output-task',
          const GoTaskServiceResult(
            success: true,
            message: 'first result',
            turnId: 'turn-first',
            raw: <String, dynamic>{
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'first.md',
                  'content': 'first body',
                  'contentType': 'text/markdown',
                },
              ],
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await firstFuture;

        final secondFuture = controller.sendChatMessage('empty run');
        await fakeGoTaskService.waitForRequestCount(2);
        fakeGoTaskService.complete(
          'empty-output-task',
          const GoTaskServiceResult(
            success: true,
            message: '',
            turnId: 'turn-second',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await secondFuture;

        final thread = controller.requireTaskThreadForSessionInternal(
          'empty-output-task',
        );
        expect(thread.lifecycleState.lastResultCode, 'failed');
        expect(thread.lastArtifactSyncStatus, 'failed');
        expect(thread.lastTaskArtifactRelativePaths, isEmpty);
        final snapshot = await controller.loadAssistantArtifactSnapshot(
          sessionKey: 'empty-output-task',
        );
        expect(snapshot.resultEntries, isEmpty);
        expect(
          controller.localSessionMessagesInternal['empty-output-task']!.any(
            (message) => message.error && message.text.contains('没有返回可显示的输出'),
          ),
          isTrue,
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
      'OpenClaw gateway tasks queue globally and keep captured session context',
      () async {
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(() {
          fakeGoTaskService.completeAll();
          controller.dispose();
        });

        await _selectGatewaySession(controller, 'queue-task-a');
        final taskAFuture = controller.sendChatMessage('same prompt');
        await fakeGoTaskService.waitForRequestCount(1);
        await expectLater(
          taskAFuture.timeout(const Duration(milliseconds: 250)),
          completes,
        );

        await _selectGatewaySession(controller, 'queue-task-b');
        final queuedAttachment = GatewayChatAttachmentPayload(
          type: 'file',
          mimeType: 'text/plain',
          fileName: 'queued.txt',
          content: base64Encode(utf8.encode('queued content')),
        );
        final taskBFuture = controller.sendChatMessage(
          'same prompt',
          attachments: <GatewayChatAttachmentPayload>[queuedAttachment],
        );
        await _selectGatewaySession(controller, 'queue-task-c');
        final taskCFuture = controller.sendChatMessage('different prompt');
        await _waitForThreadLifecycleStatus(
          controller,
          'queue-task-b',
          'queued',
        );
        await _waitForThreadLifecycleStatus(
          controller,
          'queue-task-c',
          'queued',
        );
        await expectLater(
          taskBFuture.timeout(const Duration(milliseconds: 250)),
          completes,
        );
        await expectLater(
          taskCFuture.timeout(const Duration(milliseconds: 250)),
          completes,
        );

        expect(fakeGoTaskService.requests, hasLength(1));
        expect(
          controller
              .requireTaskThreadForSessionInternal('queue-task-b')
              .lifecycleState
              .status,
          'queued',
        );
        expect(
          controller
              .requireTaskThreadForSessionInternal('queue-task-c')
              .lifecycleState
              .status,
          'queued',
        );
        expect(
          controller.assistantSessionHasPendingRun('queue-task-b'),
          isTrue,
        );
        expect(
          controller.assistantSessionHasPendingRun('queue-task-c'),
          isTrue,
        );
        expect(
          controller.localSessionMessagesInternal['queue-task-b']!.map(
            (message) => message.text,
          ),
          contains('same prompt'),
        );
        expect(
          controller.localSessionMessagesInternal['queue-task-c']!.map(
            (message) => message.text,
          ),
          contains('different prompt'),
        );

        fakeGoTaskService.complete(
          'queue-task-a',
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
        await _waitForThreadLifecycleStatus(
          controller,
          'queue-task-a',
          'ready',
        );
        await fakeGoTaskService.waitForRequestCount(2);

        final taskBRequest = fakeGoTaskService.requests[1];
        expect(taskBRequest.sessionId, 'queue-task-b');
        expect(taskBRequest.prompt, contains('TaskThread workspace context:'));
        expect(taskBRequest.prompt, contains('- sessionKey: queue-task-b'));
        expect(taskBRequest.prompt, contains('User request:\nsame prompt'));
        expect(taskBRequest.resumeSession, isFalse);
        expect(taskBRequest.inlineAttachments, hasLength(1));
        expect(taskBRequest.inlineAttachments.single.fileName, 'queued.txt');
        expect(
          taskBRequest.inlineAttachments.single.content,
          queuedAttachment.content,
        );
        expect(taskBRequest.workingDirectory, endsWith('/queue-task-b'));
        expect(taskBRequest.prompt, contains(taskBRequest.workingDirectory));
        expect(
          taskBRequest.remoteWorkingDirectoryHint,
          endsWith('/threads/queue-task-b'),
        );

        fakeGoTaskService.complete(
          'queue-task-b',
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
        await _waitForThreadLifecycleStatus(
          controller,
          'queue-task-b',
          'ready',
        );
        expect(
          controller.localSessionMessagesInternal['queue-task-b']!
              .where(
                (message) =>
                    message.role == 'user' && message.text == 'same prompt',
              )
              .length,
          1,
        );
        await fakeGoTaskService.waitForRequestCount(3);

        final taskCRequest = fakeGoTaskService.requests[2];
        expect(taskCRequest.sessionId, 'queue-task-c');
        expect(
          taskCRequest.prompt,
          contains('User request:\ndifferent prompt'),
        );
        expect(taskCRequest.workingDirectory, endsWith('/queue-task-c'));
        expect(taskCRequest.prompt, contains(taskCRequest.workingDirectory));
        fakeGoTaskService.complete(
          'queue-task-c',
          const GoTaskServiceResult(
            success: true,
            message: 'result C',
            turnId: 'turn-c',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await _waitForThreadLifecycleStatus(
          controller,
          'queue-task-c',
          'ready',
        );
      },
    );

    test('OpenClaw gateway task uses the server default model', () async {
      final fakeGoTaskService = _BlockingGoTaskServiceClient();
      final controller = _connectedGatewayController(fakeGoTaskService);
      addTearDown(() {
        fakeGoTaskService.completeAll();
        controller.dispose();
      });

      await _selectGatewaySession(controller, 'openclaw-default-model-task');
      await controller.selectAssistantModelForSession(
        'openclaw-default-model-task',
        'ollama/kimi-k2.5',
      );

      final taskFuture = controller.sendChatMessage('use OpenClaw default');
      await fakeGoTaskService.waitForRequestCount(1);
      await expectLater(
        taskFuture.timeout(const Duration(milliseconds: 250)),
        completes,
      );

      final request = fakeGoTaskService.requests.single;
      expect(request.target, AssistantExecutionTarget.gateway);
      expect(request.provider, SingleAgentProvider.openclaw);
      expect(request.model, isEmpty);

      final params = request.toExternalAcpParams();
      expect(params.containsKey('model'), isFalse);
      expect(
        params['routing'],
        isNot(containsPair('explicitModel', 'ollama/kimi-k2.5')),
      );

      fakeGoTaskService.complete(
        'openclaw-default-model-task',
        const GoTaskServiceResult(
          success: true,
          message: 'result',
          turnId: 'turn-openclaw-default-model',
          raw: <String, dynamic>{},
          errorMessage: '',
          resolvedModel: '',
          route: GoTaskServiceRoute.externalAcpSingle,
        ),
      );
      await _waitForThreadLifecycleStatus(
        controller,
        'openclaw-default-model-task',
        'ready',
      );
    });

    test(
      'abortRun removes a queued OpenClaw task without bridge cancel',
      () async {
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(() {
          fakeGoTaskService.completeAll();
          controller.dispose();
        });

        await _selectGatewaySession(controller, 'running-openclaw-task');
        final runningFuture = controller.sendChatMessage('running');
        await fakeGoTaskService.waitForRequestCount(1);

        await _selectGatewaySession(controller, 'queued-openclaw-task');
        final queuedFuture = controller.sendChatMessage('queued');
        await _waitForThreadLifecycleStatus(
          controller,
          'queued-openclaw-task',
          'queued',
        );
        expect(fakeGoTaskService.requests, hasLength(1));

        await controller.abortRun();

        expect(fakeGoTaskService.cancelledSessionIds, isEmpty);
        expect(
          controller
              .requireTaskThreadForSessionInternal('queued-openclaw-task')
              .lifecycleState
              .lastResultCode,
          'aborted',
        );
        await queuedFuture;

        fakeGoTaskService.complete(
          'running-openclaw-task',
          const GoTaskServiceResult(
            success: true,
            message: 'running done',
            turnId: 'turn-running',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await runningFuture;
        await _waitForThreadLifecycleStatus(
          controller,
          'running-openclaw-task',
          'ready',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(fakeGoTaskService.requests, hasLength(1));
      },
    );

    test(
      'abortRun stops the current running OpenClaw task without clearing other queued tasks',
      () async {
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(() {
          fakeGoTaskService.completeAll();
          controller.dispose();
        });

        await _selectGatewaySession(controller, 'running-openclaw-stop-task');
        final runningFuture = controller.sendChatMessage('running');
        await fakeGoTaskService.waitForRequestCount(1);

        await _selectGatewaySession(controller, 'queued-openclaw-after-stop');
        final queuedFuture = controller.sendChatMessage('queued');
        await _waitForThreadLifecycleStatus(
          controller,
          'queued-openclaw-after-stop',
          'queued',
        );

        await _selectGatewaySession(controller, 'running-openclaw-stop-task');
        await controller.abortRun();

        expect(fakeGoTaskService.cancelledSessionIds, <String>[
          'running-openclaw-stop-task',
        ]);
        expect(
          controller.assistantSessionHasPendingRun(
            'running-openclaw-stop-task',
          ),
          isFalse,
        );
        expect(
          controller
              .requireTaskThreadForSessionInternal('running-openclaw-stop-task')
              .lifecycleState
              .lastResultCode,
          'aborted',
        );
        expect(
          controller.assistantSessionHasPendingRun(
            'queued-openclaw-after-stop',
          ),
          isTrue,
        );

        fakeGoTaskService.complete(
          'running-openclaw-stop-task',
          const GoTaskServiceResult(
            success: true,
            message: 'late stopped result',
            turnId: 'turn-stopped',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await runningFuture;
        await fakeGoTaskService.waitForRequestCount(2);
        expect(
          fakeGoTaskService.requests.last.sessionId,
          'queued-openclaw-after-stop',
        );

        fakeGoTaskService.complete(
          'queued-openclaw-after-stop',
          const GoTaskServiceResult(
            success: true,
            message: 'queued done',
            turnId: 'turn-queued',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await queuedFuture;
        await _waitForThreadLifecycleStatus(
          controller,
          'queued-openclaw-after-stop',
          'ready',
        );
        expect(fakeGoTaskService.requests, hasLength(2));
      },
    );

    test(
      'continueAssistantTaskInternal requeues a stopped OpenClaw task without clearing queued work',
      () async {
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(() {
          fakeGoTaskService.completeAll();
          controller.dispose();
        });

        await _selectGatewaySession(controller, 'continue-active-openclaw');
        await controller.sendChatMessage('active task');
        await fakeGoTaskService.waitForRequestCount(1);

        await _selectGatewaySession(controller, 'continue-queued-openclaw');
        await controller.sendChatMessage('queued before continue');
        await _waitForThreadLifecycleStatus(
          controller,
          'continue-queued-openclaw',
          'queued',
        );

        await _selectGatewaySession(controller, 'continue-stopped-openclaw');
        controller.appendLocalSessionMessageInternal(
          'continue-stopped-openclaw',
          GatewayChatMessage(
            id: 'user-continue-stopped-openclaw',
            role: 'user',
            text: 'resume stopped openclaw task',
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
          'continue-stopped-openclaw',
          executionTarget: AssistantExecutionTarget.gateway,
          selectedProvider: SingleAgentProvider.openclaw,
          selectedProviderSource: ThreadSelectionSource.explicit,
          lifecycleStatus: 'ready',
          lastResultCode: 'aborted',
        );

        await controller.continueAssistantTaskInternal(
          'continue-stopped-openclaw',
        );

        await _waitForThreadLifecycleStatus(
          controller,
          'continue-stopped-openclaw',
          'queued',
        );
        expect(fakeGoTaskService.requests, hasLength(1));
        expect(
          controller.assistantSessionHasPendingRun('continue-queued-openclaw'),
          isTrue,
        );
        expect(
          controller.assistantSessionHasPendingRun('continue-stopped-openclaw'),
          isTrue,
        );
        expect(
          controller.localSessionMessagesInternal['continue-stopped-openclaw']!
              .where(
                (message) =>
                    message.role == 'user' &&
                    message.text == 'resume stopped openclaw task',
              )
              .length,
          1,
        );

        fakeGoTaskService.complete(
          'continue-active-openclaw',
          const GoTaskServiceResult(
            success: true,
            message: 'active done',
            turnId: 'turn-active',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await fakeGoTaskService.waitForRequestCount(2);
        expect(
          fakeGoTaskService.requests.last.sessionId,
          'continue-queued-openclaw',
        );

        fakeGoTaskService.complete(
          'continue-queued-openclaw',
          const GoTaskServiceResult(
            success: true,
            message: 'queued done',
            turnId: 'turn-queued',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await fakeGoTaskService.waitForRequestCount(3);

        final continuedRequest = fakeGoTaskService.requests.last;
        expect(continuedRequest.sessionId, 'continue-stopped-openclaw');
        expect(continuedRequest.resumeSession, isFalse);
        expect(
          continuedRequest.prompt,
          contains('User request:\nresume stopped openclaw task'),
        );

        fakeGoTaskService.complete(
          'continue-stopped-openclaw',
          const GoTaskServiceResult(
            success: true,
            message: 'continued stopped',
            turnId: 'turn-continued-stopped',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await _waitForThreadLifecycleStatus(
          controller,
          'continue-stopped-openclaw',
          'ready',
        );
      },
    );

    test(
      'stale queued lifecycle without a real queue entry is not pending',
      () {
        final controller = _connectedGatewayController(
          _BlockingGoTaskServiceClient(),
        );
        addTearDown(controller.dispose);

        controller.upsertTaskThreadInternal(
          'stale-queued-task',
          lifecycleStatus: 'queued',
          lastResultCode: 'queued',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
        );

        expect(
          controller.assistantSessionHasPendingRun('stale-queued-task'),
          isFalse,
        );
      },
    );

    test('OpenClaw queue overflow fails without artifact sync', () async {
      final fakeGoTaskService = _BlockingGoTaskServiceClient();
      final controller = _connectedGatewayController(fakeGoTaskService);
      addTearDown(controller.dispose);

      controller.openClawGatewayActiveTasksInternal =
          openClawGatewayMaxActiveTasksInternal;
      for (
        var index = 0;
        index < openClawGatewayMaxQueuedTasksInternal;
        index += 1
      ) {
        final sessionKey = 'queue-full-waiting-$index';
        final turn = OpenClawGatewayQueuedTurnInternal(
          queueId: 'queue-full-$index',
          sessionKey: sessionKey,
          target: AssistantExecutionTarget.gateway,
          provider: SingleAgentProvider.openclaw,
          message: 'queued $index',
          thinking: 'off',
          selectedSkillLabels: const <String>[],
          attachments: const <GatewayChatAttachmentPayload>[],
          localAttachments: const <CollaborationAttachment>[],
          workingDirectory: '/tmp/$sessionKey',
          remoteWorkingDirectoryHint: '/threads/$sessionKey',
          model: '',
          routing: const ExternalCodeAgentAcpRoutingConfig.auto(
            preferredGatewayTarget: kCanonicalGatewayProviderId,
          ),
          agentId: '',
          metadata: const <String, dynamic>{},
          resumeSessionHint: false,
        );
        controller.openClawGatewayQueuedTurnsInternal.add(turn);
        controller.openClawGatewayQueuedTurnsBySessionInternal[sessionKey] =
            <OpenClawGatewayQueuedTurnInternal>[turn];
      }

      await _selectGatewaySession(controller, 'queue-full-overflow');
      await expectLater(
        controller.sendChatMessage('overflow'),
        throwsA(isA<StateError>()),
      );

      final overflowThread = controller.requireTaskThreadForSessionInternal(
        'queue-full-overflow',
      );
      expect(overflowThread.lastArtifactSyncStatus, 'failed');
      expect(overflowThread.lastTaskArtifactRelativePaths, isEmpty);
      expect(fakeGoTaskService.requests, isEmpty);
    });

    test(
      'OpenClaw transport interruption releases queue slot for another task',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient()
          ..outcomes.add(
            const GatewayAcpException(
              'ACP HTTP connection closed before the response finished arriving',
              code: 'ACP_HTTP_CONNECTION_CLOSED',
            ),
          )
          ..outcomes.add(
            const GoTaskServiceResult(
              success: true,
              message: 'second task completed',
              turnId: 'turn-second',
              raw: <String, dynamic>{},
              errorMessage: '',
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          );
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await _selectGatewaySession(controller, 'openclaw-failed-task');
        final failedSubmitFuture = controller.sendChatMessage('输出 word 文档');

        await _waitForThreadLastResultCode(
          controller,
          'openclaw-failed-task',
          'ACP_HTTP_CONNECTION_CLOSED',
        );
        expect(fakeGoTaskService.requests, hasLength(1));
        await failedSubmitFuture;
        expect(
          controller.assistantSessionHasPendingRun('openclaw-failed-task'),
          isFalse,
        );
        expect(controller.openClawGatewayActiveTasksInternal, 0);
        expect(
          controller
              .requireTaskThreadForSessionInternal('openclaw-failed-task')
              .lifecycleState
              .lastResultCode,
          'ACP_HTTP_CONNECTION_CLOSED',
        );

        await _selectGatewaySession(controller, 'openclaw-second-task');
        final secondSubmitFuture = controller.sendChatMessage('输出 markdown格式');

        await _waitForThreadLastResultCode(
          controller,
          'openclaw-second-task',
          'SUCCESS',
        );
        expect(fakeGoTaskService.requests, hasLength(2));
        expect(
          fakeGoTaskService.requests.last.sessionId,
          'openclaw-second-task',
        );
        await secondSubmitFuture;
        expect(controller.openClawGatewayActiveTasksInternal, 0);
        expect(
          controller.chatMessages.map((message) => message.text),
          contains('second task completed'),
        );
      },
    );

    test(
      'sendChatMessage resumes existing interrupted and error states',
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

        final interruptedFuture = controller.sendChatMessage('continue');
        await fakeGoTaskService.waitForRequestCount(1);
        expect(observedRequestStatuses.single, 'running');
        expect(fakeGoTaskService.requests.single.resumeSession, isTrue);
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
        await interruptedFuture;

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
        expect(observedRequestStatuses.last, 'running');
        expect(fakeGoTaskService.requests.last.resumeSession, isTrue);
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

    test(
      'continueAssistantTaskInternal resumes interrupted task without duplicating user turn',
      () async {
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(() {
          fakeGoTaskService.completeAll();
          controller.dispose();
        });

        await controller.switchSession('continue-interrupted-task');
        controller.appendLocalSessionMessageInternal(
          'continue-interrupted-task',
          GatewayChatMessage(
            id: 'user-continue-interrupted',
            role: 'user',
            text: 'previous interrupted request',
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
          'continue-interrupted-task',
          lifecycleStatus: 'interrupted',
          lastResultCode: 'ACP_HTTP_CONNECTION_CLOSED',
          lastArtifactSyncStatus: 'interrupted',
        );

        final continueFuture = controller.continueAssistantTaskInternal(
          'continue-interrupted-task',
        );
        await fakeGoTaskService.waitForRequestCount(1);

        final request = fakeGoTaskService.requests.single;
        expect(request.sessionId, 'continue-interrupted-task');
        expect(request.resumeSession, isTrue);
        expect(
          request.prompt,
          contains('User request:\nprevious interrupted request'),
        );
        expect(
          controller.localSessionMessagesInternal['continue-interrupted-task']!
              .where(
                (message) =>
                    message.role == 'user' &&
                    message.text == 'previous interrupted request',
              )
              .length,
          1,
        );

        fakeGoTaskService.complete(
          'continue-interrupted-task',
          const GoTaskServiceResult(
            success: true,
            message: 'continued interrupted',
            turnId: 'turn-continued-interrupted',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await continueFuture;
      },
    );

    test(
      'continueAssistantTaskInternal fails locally without a committed user turn',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.switchSession('continue-empty-task');
        controller.upsertTaskThreadInternal(
          'continue-empty-task',
          lifecycleStatus: 'ready',
          lastResultCode: 'aborted',
        );

        await expectLater(
          controller.continueAssistantTaskInternal('continue-empty-task'),
          throwsA(isA<StateError>()),
        );

        expect(fakeGoTaskService.requests, isEmpty);
        expect(
          controller
              .assistantThreadMessagesInternal['continue-empty-task']!
              .last
              .text,
          contains('没有可恢复的用户请求'),
        );
      },
    );

    test('sendChatMessage resumes after confirmed session activity', () async {
      final fakeGoTaskService = _RecordingGoTaskServiceClient()
        ..outcomes.add(
          const GoTaskServiceResult(
            success: true,
            message: 'first success',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        )
        ..outcomes.add(
          const GoTaskServiceResult(
            success: true,
            message: 'second success',
            turnId: 'turn-2',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
      final controller = _connectedController(fakeGoTaskService);
      addTearDown(controller.dispose);

      await controller.switchSession('confirmed-session');

      await controller.sendChatMessage('first turn');
      await controller.sendChatMessage('second turn');

      expect(fakeGoTaskService.requests, hasLength(2));
      expect(fakeGoTaskService.requests.first.resumeSession, isFalse);
      expect(fakeGoTaskService.requests.last.resumeSession, isTrue);
    });
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

AppController _connectedGatewayController(GoTaskServiceClient client) {
  return AppController(
    goTaskServiceClient: client,
    environmentOverride: const <String, String>{
      'BRIDGE_AUTH_TOKEN': 'bridge-token',
    },
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
}

Future<void> _selectGatewaySession(
  AppController controller,
  String sessionKey,
) async {
  await controller.switchSession(sessionKey);
  await controller.setAssistantExecutionTarget(
    AssistantExecutionTarget.gateway,
  );
  await controller.setAssistantProvider(SingleAgentProvider.openclaw);
  controller.upsertTaskThreadInternal(
    sessionKey,
    executionTarget: AssistantExecutionTarget.gateway,
    selectedProvider: SingleAgentProvider.openclaw,
    selectedProviderSource: ThreadSelectionSource.explicit,
  );
}

Future<void> _waitForThreadLifecycleStatus(
  AppController controller,
  String sessionKey,
  String status,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    final currentStatus = controller
        .taskThreadForSessionInternal(sessionKey)
        ?.lifecycleState
        .status;
    if (currentStatus == status) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final currentStatus = controller
      .taskThreadForSessionInternal(sessionKey)
      ?.lifecycleState
      .status;
  throw StateError(
    'Timed out waiting for $sessionKey status $status. Current status: $currentStatus.',
  );
}

Future<void> _waitForThreadLastResultCode(
  AppController controller,
  String sessionKey,
  String resultCode,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    final currentResultCode = controller
        .taskThreadForSessionInternal(sessionKey)
        ?.lifecycleState
        .lastResultCode;
    if (currentResultCode?.toUpperCase() == resultCode.toUpperCase()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final currentResultCode = controller
      .taskThreadForSessionInternal(sessionKey)
      ?.lifecycleState
      .lastResultCode;
  throw StateError(
    'Timed out waiting for $sessionKey result code $resultCode. Current result code: $currentResultCode.',
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

  void completeAll([
    GoTaskServiceResult result = const GoTaskServiceResult(
      success: true,
      message: 'cleanup',
      turnId: 'turn-cleanup',
      raw: <String, dynamic>{},
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    ),
  ]) {
    final pendingSessionIds = List<String>.from(_pending.keys);
    for (final sessionId in pendingSessionIds) {
      complete(sessionId, result);
    }
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
