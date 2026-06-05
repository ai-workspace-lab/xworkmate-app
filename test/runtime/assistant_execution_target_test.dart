import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_controller_desktop_external_acp_routing.dart';
import 'package:xworkmate/app/app_controller_openclaw_task_queue.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_picker.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/desktop_platform_service.dart';
import 'package:xworkmate/runtime/account_runtime_client.dart';

const List<String> _openClawE2ECanonicalPrompts = <String>[
  '从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进 \n制作 使用codex 制作连续制作 7张的一些列图片',
  '参考附件模版制作 ,围绕\n从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进 \n连续制作 7张的一些列图片',
  '拆章节 -> 每章调用 Codex -> 每章 GPT images2 生成图 -> 汇总排版 -> 输出 PDF\n\n右侧 artifact栏 显示的陈旧文件',
  '围绕\n从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进 右侧是当下 \n测试制作视频',
  '围绕\n\n从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进 \n\n拆章节 -> 每章调用 Codex -> 每章 GPT images2 生成图 -> 汇总排版 -> 制作视频',
];
const Duration _openClawE2ESubmitTimeout = Duration(seconds: 10);

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
        final controller = _sandboxController(
          environmentOverride: const <String, String>{},
          uiFeatureManifest: _defaultDesktopManifest(),
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
        final controller = _sandboxController(
          environmentOverride: const <String, String>{},
          uiFeatureManifest: _defaultDesktopManifest(),
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
      'new task sessions use the feature-visible default instead of main',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-no-main-target-inheritance-',
        );
        addTearDown(() async {
          if (await localHome.exists()) {
            await localHome.delete(recursive: true);
          }
        });
        final controller = _sandboxController(
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
          homeDir: localHome.path,
        );
        addTearDown(controller.dispose);

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
          AssistantExecutionTarget.gateway,
        );

        await controller.switchSession('draft:fresh-task');

        final freshThread = controller.requireTaskThreadForSessionInternal(
          'draft:fresh-task',
        );
        expect(
          freshThread.executionBinding.executionMode,
          ThreadExecutionMode.gateway,
        );
        expect(
          freshThread.workspaceBinding.workspacePath,
          endsWith('/.xworkmate/threads/draft-fresh-task'),
        );
      },
    );

    test('allocates unique draft session keys for repeated task creation', () {
      final controller = _sandboxController(
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
      final controller = _sandboxController(
        environmentOverride: const <String, String>{},
        homeDir: localHome.path,
      );
      addTearDown(controller.dispose);
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
        final controller = _sandboxController(
          environmentOverride: const <String, String>{},
          homeDir: localHome.path,
        );
        addTearDown(controller.dispose);
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
      final controller = _sandboxController(
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
      'assistant task list keeps repository order when tasks update',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-stable-task-selection-home-',
        );
        addTearDown(() async {
          if (await localHome.exists()) {
            await localHome.delete(recursive: true);
          }
        });
        final controller = _sandboxController(
          environmentOverride: const <String, String>{},
          homeDir: localHome.path,
        );
        addTearDown(controller.dispose);

        const firstTask = 'draft:first-task';
        const secondTask = 'draft:second-task';
        const firstUpdatedAtMs = 1000.0;
        const secondUpdatedAtMs = 2000.0;
        controller.upsertTaskThreadInternal(
          firstTask,
          executionTarget: AssistantExecutionTarget.gateway,
          messageViewMode: AssistantMessageViewMode.rendered,
          updatedAtMs: firstUpdatedAtMs,
        );
        controller.upsertTaskThreadInternal(
          secondTask,
          executionTarget: AssistantExecutionTarget.gateway,
          messageViewMode: AssistantMessageViewMode.rendered,
          updatedAtMs: secondUpdatedAtMs,
        );

        await controller.switchSession(secondTask);
        controller.upsertTaskThreadInternal(
          secondTask,
          executionTarget: AssistantExecutionTarget.gateway,
          messageViewMode: AssistantMessageViewMode.rendered,
          updatedAtMs: 3000,
        );

        expect(controller.currentSessionKey, secondTask);
        expect(
          controller
              .requireTaskThreadForSessionInternal(secondTask)
              .updatedAtMs,
          3000,
        );
        expect(
          controller.assistantSessions.map((item) => item.key).take(2),
          <String>[firstTask, secondTask],
        );
      },
    );

    test(
      'returns unspecified when a saved provider is no longer in the current catalog',
      () {
        final controller = _sandboxController(
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
        final controller = _sandboxController(
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
        final controller = _sandboxController(
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
        final controller = _sandboxController(
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

    test(
      'skill picker selection allows multiple skills and independent deselect',
      () async {
        final controller = _connectedGatewayController(
          _RecordingGoTaskServiceClient(),
        );
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
            ];
        await _selectGatewaySession(controller, 'unit-skill-multi-select-task');

        await controller.toggleAssistantSkillForSession(
          'unit-skill-multi-select-task',
          'pdf',
        );
        await controller.toggleAssistantSkillForSession(
          'unit-skill-multi-select-task',
          'browser-automation',
        );

        expect(
          controller.assistantSelectedSkillKeysForSession(
            'unit-skill-multi-select-task',
          ),
          const <String>['pdf', 'browser-automation'],
        );

        await controller.toggleAssistantSkillForSession(
          'unit-skill-multi-select-task',
          'browser-automation',
        );

        expect(
          controller.assistantSelectedSkillKeysForSession(
            'unit-skill-multi-select-task',
          ),
          const <String>['pdf'],
        );
      },
    );

    test('skill selection is isolated across task sessions', () async {
      final controller = _connectedGatewayController(
        _RecordingGoTaskServiceClient(),
      );
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
          ];

      await _selectGatewaySession(controller, 'unit-skill-isolated-a');
      await controller.toggleAssistantSkillForSession(
        'unit-skill-isolated-a',
        'pdf',
      );
      await _selectGatewaySession(controller, 'unit-skill-isolated-b');

      expect(
        controller.assistantSelectedSkillKeysForSession(
          'unit-skill-isolated-b',
        ),
        isEmpty,
      );

      await controller.toggleAssistantSkillForSession(
        'unit-skill-isolated-b',
        'browser-automation',
      );

      expect(
        controller
            .buildExternalAcpRoutingForSessionInternal('unit-skill-isolated-a')
            .explicitSkills,
        const <String>['pdf'],
      );
      expect(
        controller
            .buildExternalAcpRoutingForSessionInternal('unit-skill-isolated-b')
            .explicitSkills,
        const <String>['browser-automation'],
      );
    });

    test('skill selection ignores stale non-bridge skill keys', () {
      final controller = _sandboxController(
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
        final controller = _sandboxController(
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
              // The controller may still be releasing files when teardown starts.
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

        final controller = _sandboxController(
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
              // Ignore temp cleanup failure during teardown.
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

        final controller = _sandboxController(
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
              // The controller may still be releasing files when teardown starts.
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
      'sendChatMessage leaves Gateway task classification to the remote runtime',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.ensureActiveAssistantThreadInternal();
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );
        await controller.sendChatMessage(
          '围绕\n\n'
          '从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进\n\n'
          '拆章节 -> 每章调用 Codex -> 每章 GPT images2 生成图 -> 汇总排版 -> 制作视频',
        );

        expect(fakeGoTaskService.requests, hasLength(1));
        final request = fakeGoTaskService.requests.single;
        expect(request.metadata, isNot(contains('taskLoadClass')));
        expect(request.metadata, isNot(contains('expectedArtifactExtensions')));
        expect(request.metadata, contains('xworkmateTaskArtifactContract'));
        final artifactContract =
            (request.metadata['xworkmateTaskArtifactContract'] as Map)
                .cast<String, dynamic>();
        expect(artifactContract['finalDeliverableDetection'], 'remote-runtime');
        expect(artifactContract['requiresExportBeforeFinalResponse'], isTrue);
        expect(artifactContract, isNot(contains('expectedArtifactExtensions')));
        expect(request.prompt, isNot(contains('Task load classification:')));
        expect(
          request.prompt,
          isNot(contains('First write the chapter breakdown')),
        );
        expect(
          request.prompt,
          isNot(contains('Run heavyweight stages in order')),
        );
        expect(
          request.prompt,
          contains('User request:\n围绕\n\n从单机权限 → 网络边界 → Web安全'),
        );
      },
    );

    test(
      'sendChatMessage leaves artifact expectations to the remote runtime',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.ensureActiveAssistantThreadInternal();
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );
        await controller.sendChatMessage(
          '围绕\n\n'
          '从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进 800-1500字\n'
          '拆章节 -> 每章调用 Codex -> 每章 GPT images2 生成图 -> 汇总排版 ->\n\n'
          '最后 输出 PDF文件',
        );

        expect(fakeGoTaskService.requests, hasLength(1));
        final request = fakeGoTaskService.requests.single;
        expect(request.metadata, isNot(contains('taskLoadClass')));
        expect(request.metadata, isNot(contains('expectedArtifactExtensions')));
        expect(request.metadata, contains('xworkmateTaskArtifactContract'));
        final artifactContract =
            (request.metadata['xworkmateTaskArtifactContract'] as Map)
                .cast<String, dynamic>();
        expect(artifactContract['scopeKind'], 'task');
        expect(artifactContract['rejectTextOnlyFileClaims'], isTrue);
        expect(
          artifactContract['currentTaskWorkspace'],
          request.workingDirectory,
        );
        expect(request.prompt, isNot(contains('Required final artifact')));
        expect(request.prompt, contains('XWorkmate task artifact contract:'));
        expect(
          request.prompt,
          contains(
            'export the final deliverables through the current XWorkmate task artifact scope',
          ),
        );
        expect(request.prompt, contains('最后 输出 PDF文件'));
      },
    );

    test(
      'sendChatMessage sends simple Gateway prompts without local classification',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.ensureActiveAssistantThreadInternal();
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );
        await controller.sendChatMessage('写一段普通说明');

        expect(fakeGoTaskService.requests, hasLength(1));
        final request = fakeGoTaskService.requests.single;
        expect(request.metadata, isNot(contains('taskLoadClass')));
        expect(request.prompt, isNot(contains('- class: short_task')));
        expect(request.prompt, contains('User request:\n写一段普通说明'));
      },
    );

    test(
      'sendChatMessage sends artifact output without local class metadata',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.ensureActiveAssistantThreadInternal();
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );
        await controller.sendChatMessage('生成 Markdown 和 PNG 产物');

        expect(fakeGoTaskService.requests, hasLength(1));
        final request = fakeGoTaskService.requests.single;
        expect(request.metadata, isNot(contains('taskLoadClass')));
        expect(request.metadata, isNot(contains('expectedArtifactExtensions')));
        expect(request.prompt, isNot(contains('- class: long_task')));
        expect(request.prompt, contains('User request:\n生成 Markdown 和 PNG 产物'));
      },
    );

    test(
      'sendChatMessage runs Gateway task with remote workspace when local workspace is unavailable',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(controller.dispose);
        controller.resolvedUserHomeDirectoryInternal = '';

        await controller.ensureActiveAssistantThreadInternal();
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );
        await controller.sendChatMessage('mobile gateway task');

        expect(fakeGoTaskService.requests, hasLength(1));
        final request = fakeGoTaskService.requests.single;
        expect(request.target, AssistantExecutionTarget.gateway);
        expect(request.provider.providerId, 'openclaw');
        expect(request.workingDirectory, startsWith('/owners/'));
        expect(request.workingDirectory, contains('/threads/'));
        expect(request.remoteWorkingDirectoryHint, request.workingDirectory);
        expect(request.prompt, contains(request.workingDirectory));
      },
    );

    test(
      'sendChatMessage sends remote Gateway cwd while keeping local workspace context',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.ensureActiveAssistantThreadInternal();
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );
        await controller.sendChatMessage(
          'gateway task with inline attachment',
          attachments: <GatewayChatAttachmentPayload>[
            GatewayChatAttachmentPayload(
              type: 'file',
              mimeType: 'text/plain',
              fileName: 'note.txt',
              content: base64Encode(utf8.encode('note body')),
            ),
          ],
        );

        expect(fakeGoTaskService.requests, hasLength(1));
        final request = fakeGoTaskService.requests.single;
        final localWorkspace = controller.assistantWorkspacePathForSession(
          request.sessionId,
        );
        expect(localWorkspace, isNotEmpty);
        expect(request.target, AssistantExecutionTarget.gateway);
        expect(request.provider.providerId, 'openclaw');
        expect(request.workingDirectory, startsWith('/owners/'));
        expect(request.workingDirectory, isNot(localWorkspace));
        expect(request.remoteWorkingDirectoryHint, request.workingDirectory);
        expect(request.prompt, contains('- localWorkspace: $localWorkspace'));
        expect(
          request.prompt,
          contains('- currentTaskWorkspace: ${request.workingDirectory}'),
        );
        expect(request.inlineAttachments, hasLength(1));
      },
    );

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
        expect(
          inlineAttachment['sha256'],
          '1c727d26215adccb96d725e8b63b3ee11cf73215a554e60295877244b0778847',
        );
        final attachments = params['attachments'] as List<dynamic>;
        final attachment = attachments.single as Map<String, dynamic>;
        expect(attachment['name'], 'note.txt');
        expect(attachment['path'], isEmpty);
      },
    );

    test(
      'sendChatMessage records task input attachments and does not reupload duplicates',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.ensureActiveAssistantThreadInternal();
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        final imageAttachment = GatewayChatAttachmentPayload(
          type: 'image',
          mimeType: 'image/png',
          fileName: 'diagram.png',
          content: base64Encode(utf8.encode('image bytes')),
        );

        await controller.sendChatMessage(
          'use the image',
          attachments: <GatewayChatAttachmentPayload>[imageAttachment],
        );
        await controller.sendChatMessage(
          'continue with the same image',
          attachments: <GatewayChatAttachmentPayload>[imageAttachment],
        );

        expect(fakeGoTaskService.requests, hasLength(2));
        expect(
          fakeGoTaskService.requests.first.inlineAttachments,
          hasLength(1),
        );
        expect(fakeGoTaskService.requests.last.inlineAttachments, isEmpty);
        expect(
          fakeGoTaskService.requests.last.prompt,
          contains('- taskInputAttachments:'),
        );
        expect(
          fakeGoTaskService.requests.last.prompt,
          contains('diagram.png (image/png, sha256:'),
        );
        final thread = controller.requireTaskThreadForSessionInternal(
          fakeGoTaskService.requests.last.sessionId,
        );
        expect(thread.taskInputAttachments, hasLength(1));
        expect(thread.taskInputAttachments.single.name, 'diagram.png');
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
          ..onExecuteTask = ((request) async {
            await Directory(
              '${request.workingDirectory}/assets/images',
            ).create(recursive: true);
            await File(
              '${request.workingDirectory}/assets/images/final.v2.png',
            ).writeAsBytes(<int>[1, 2, 3, 4]);
          })
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
        final controller = _connectedController(
          fakeGoTaskService,
          homeDir: localWorkspace.path,
        );
        addTearDown(controller.dispose);

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
          'interrupted',
        );
        expect(
          controller
              .taskThreadForSessionInternal('unit-fixture-task-a')
              ?.lastTaskArtifactRelativePaths,
          <String>['assets/images/final.v2.png'],
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
      'sendChatMessage starts a new session after ACP HTTP authorization failure',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient()
          ..outcomes.add(
            const GatewayAcpException(
              'ACP HTTP request failed (401) · missing bearer authorization',
              code: 'ACP_HTTP_401',
            ),
          )
          ..outcomes.add(
            const GoTaskServiceResult(
              success: true,
              message: 'retried with bridge authorization',
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
        expect(failedThread?.lifecycleState.lastResultCode, 'ACP_HTTP_401');
        expect(failedThread?.lastArtifactSyncStatus, 'failed');

        await controller.sendChatMessage('retry after auth recovery');

        expect(fakeGoTaskService.requests, hasLength(2));
        expect(fakeGoTaskService.requests.last.resumeSession, isFalse);
        await _waitForLastChatMessageText(
          controller,
          'retried with bridge authorization',
        );
      },
    );

    test(
      'sendChatMessage restarts before handling OpenClaw artifact guard results',
    test(
      'sendChatMessage starts a new session after OpenClaw terminal artifact failure',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient()
          ..outcomes.add(
            const GoTaskServiceResult(
              success: false,
              message: 'OpenClaw completed without required final artifacts.',
              turnId: 'turn-1',
              raw: <String, dynamic>{
                'status': 'failed',
                'code': 'OPENCLAW_NO_EXPORTED_ARTIFACTS',
              },
              errorMessage:
                  'openclaw returned partial artifacts without required final deliverables',
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          )
          ..outcomes.add(
            const GoTaskServiceResult(
              success: true,
              message: 'final artifact delivered',
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
        expect(
          failedThread?.lifecycleState.lastResultCode,
          'OPENCLAW_NO_EXPORTED_ARTIFACTS',
        );
        expect(failedThread?.lastArtifactSyncStatus, 'failed');

        await controller.sendChatMessage('retry final artifact');

        expect(fakeGoTaskService.requests, hasLength(2));
        expect(fakeGoTaskService.requests.last.resumeSession, isFalse);
        await _waitForLastChatMessageText(
          controller,
          'final artifact delivered',
        );
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
        final controller = _connectedController(
          fakeGoTaskService,
          homeDir: localWorkspace.path,
        );
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
        await _waitForThreadLastResultCode(
          controller,
          'unit-fixture-task-a',
          'SUCCESS',
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

    test('sendChatMessage can pin submit to the captured session', () async {
      final fakeGoTaskService = _BlockingGoTaskServiceClient();
      final controller = _connectedController(fakeGoTaskService);
      addTearDown(controller.dispose);

      await controller.switchSession('same-prompt-old-task');
      await controller.switchSession('same-prompt-new-task');
      final taskFuture = controller.sendChatMessage(
        '连续制作7张图片',
        sessionKey: 'same-prompt-new-task',
      );
      await fakeGoTaskService.waitForRequestCount(1);

      final request = fakeGoTaskService.requests.single;
      expect(request.sessionId, 'same-prompt-new-task');
      expect(request.threadId, 'same-prompt-new-task');
      expect(request.workingDirectory, endsWith('/same-prompt-new-task'));
      expect(
        request.remoteWorkingDirectoryHint,
        endsWith('/threads/same-prompt-new-task'),
      );

      fakeGoTaskService.complete(
        'same-prompt-new-task',
        const GoTaskServiceResult(
          success: true,
          message: 'new task result',
          turnId: 'turn-new',
          raw: <String, dynamic>{},
          errorMessage: '',
          resolvedModel: '',
          route: GoTaskServiceRoute.externalAcpSingle,
        ),
      );
      await taskFuture;

      expect(
        controller.localSessionMessagesInternal['same-prompt-new-task']!.map(
          (message) => message.text,
        ),
        contains('new task result'),
      );
      expect(
        controller.localSessionMessagesInternal['same-prompt-old-task'],
        isNot(contains('new task result')),
      );
    });

    test(
      'sendChatMessage queues follow-up turns on the same session',
      () async {
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await controller.switchSession('running-task');
        final firstFuture = controller.sendChatMessage('first turn');
        await fakeGoTaskService.waitForRequestCount(1);
        expect(fakeGoTaskService.requests.single.sessionId, 'running-task');
        expect(fakeGoTaskService.requests.single.threadId, 'running-task');
        expect(
          controller.assistantSessionHasPendingRun('running-task'),
          isTrue,
        );

        final secondFuture = controller.sendChatMessage('follow up');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(fakeGoTaskService.requests, hasLength(1));
        expect(controller.currentSessionKey, 'running-task');

        fakeGoTaskService.complete(
          'running-task',
          const GoTaskServiceResult(
            success: true,
            message: 'first result',
            turnId: 'turn-1',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await firstFuture;
        await fakeGoTaskService.waitForRequestCount(2);

        final followUpRequest = fakeGoTaskService.requests.last;
        expect(followUpRequest.sessionId, 'running-task');
        expect(followUpRequest.threadId, 'running-task');
        expect(followUpRequest.prompt, contains('follow up'));
        expect(controller.currentSessionKey, 'running-task');

        fakeGoTaskService.complete(
          'running-task',
          const GoTaskServiceResult(
            success: true,
            message: 'second result',
            turnId: 'turn-2',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await secondFuture;

        expect(
          controller.localSessionMessagesInternal['running-task']!.map(
            (message) => message.text,
          ),
          containsAll(<String>[
            'first turn',
            'first result',
            'follow up',
            'second result',
          ]),
        );
      },
    );

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
        final controller = _connectedController(
          fakeGoTaskService,
          homeDir: localHome.path,
        );
        addTearDown(controller.dispose);

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
        final controller = _connectedController(
          fakeGoTaskService,
          homeDir: localHome.path,
        );
        addTearDown(controller.dispose);

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
        final controller = _connectedController(
          fakeGoTaskService,
          homeDir: localHome.path,
        );
        addTearDown(controller.dispose);

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
          taskBSnapshot.resultMessage,
          'No task artifacts recorded for this run.',
        );
        expect(taskBSnapshot.filesMessage, isEmpty);
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
        final controller = _connectedController(
          fakeGoTaskService,
          homeDir: localHome.path,
        );
        addTearDown(controller.dispose);

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
        final controller = _connectedController(
          fakeGoTaskService,
          homeDir: localHome.path,
        );
        addTearDown(controller.dispose);

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
        expect(snapshot.fileEntries, isEmpty);
        expect(
          snapshot.resultMessage,
          'No task artifacts recorded for this run.',
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
        final controller = _connectedController(
          fakeGoTaskService,
          homeDir: localHome.path,
        );
        addTearDown(controller.dispose);

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
        expect(
          thread.lifecycleState.lastResultCode,
          'OPENCLAW_NO_DISPLAYABLE_OUTPUT',
        );
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

        final queuedAttachment = GatewayChatAttachmentPayload(
          type: 'file',
          mimeType: 'text/plain',
          fileName: 'queued.txt',
          content: base64Encode(utf8.encode('queued content')),
        );
        for (
          var index = 0;
          index < openClawGatewayMaxActiveTasksInternal;
          index += 1
        ) {
          final sessionKey = 'queue-task-$index';
          await _selectGatewaySession(controller, sessionKey);
          await expectLater(
            controller
                .sendChatMessage('active prompt $index')
                .timeout(const Duration(seconds: 2)),
            completes,
          );
          await fakeGoTaskService.waitForRequestCount(index + 1);
          expect(
            controller
                .requireTaskThreadForSessionInternal(sessionKey)
                .lifecycleState
                .status,
            'running',
          );
        }

        await _selectGatewaySession(controller, 'queue-task-waiting');
        await expectLater(
          controller
              .sendChatMessage(
                'queued prompt',
                attachments: <GatewayChatAttachmentPayload>[queuedAttachment],
              )
              .timeout(const Duration(seconds: 2)),
          completes,
        );
        await _waitForThreadLifecycleStatus(
          controller,
          'queue-task-waiting',
          'queued',
        );
        expect(
          fakeGoTaskService.requests,
          hasLength(openClawGatewayMaxActiveTasksInternal),
        );
        expect(
          controller
              .requireTaskThreadForSessionInternal('queue-task-waiting')
              .lifecycleState
              .status,
          'queued',
        );
        expect(
          controller.assistantSessionHasPendingRun('queue-task-waiting'),
          isTrue,
        );
        expect(
          controller.localSessionMessagesInternal['queue-task-waiting']!.map(
            (message) => message.text,
          ),
          contains('queued prompt'),
        );

        fakeGoTaskService.complete(
          'queue-task-0',
          const GoTaskServiceResult(
            success: true,
            message: 'result 0',
            turnId: 'turn-0',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await _waitForThreadLifecycleStatus(
          controller,
          'queue-task-0',
          'ready',
        );
        await fakeGoTaskService.waitForRequestCount(
          openClawGatewayMaxActiveTasksInternal + 1,
        );

        final queuedRequest = fakeGoTaskService.requests.last;
        expect(queuedRequest.sessionId, 'queue-task-waiting');
        expect(queuedRequest.prompt, contains('TaskThread workspace context:'));
        expect(
          queuedRequest.prompt,
          contains('- sessionKey: queue-task-waiting'),
        );
        expect(queuedRequest.prompt, contains('User request:\nqueued prompt'));
        expect(queuedRequest.resumeSession, isFalse);
        expect(queuedRequest.inlineAttachments, hasLength(1));
        expect(queuedRequest.inlineAttachments.single.fileName, 'queued.txt');
        expect(
          queuedRequest.inlineAttachments.single.content,
          queuedAttachment.content,
        );
        expect(queuedRequest.workingDirectory, endsWith('/queue-task-waiting'));
        expect(queuedRequest.prompt, contains(queuedRequest.workingDirectory));
        expect(
          queuedRequest.remoteWorkingDirectoryHint,
          endsWith('/threads/queue-task-waiting'),
        );

        fakeGoTaskService.complete(
          'queue-task-waiting',
          const GoTaskServiceResult(
            success: true,
            message: 'queued done',
            turnId: 'turn-waiting',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await _waitForThreadLifecycleStatus(
          controller,
          'queue-task-waiting',
          'ready',
        );
        expect(
          controller.localSessionMessagesInternal['queue-task-waiting']!
              .where(
                (message) =>
                    message.role == 'user' && message.text == 'queued prompt',
              )
              .length,
          1,
        );
      },
    );

    test(
      'OpenClaw gateway admits five representative E2E tasks without queueing',
      () async {
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(() {
          fakeGoTaskService.completeAll();
          controller.dispose();
        });

        const prompts = <String>[
          '从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进 \n制作 使用codex 制作连续制作 7张的一些列图片',
          '参考附件模版制作 ,围绕\n从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进 \n连续制作 7张的一些列图片',
          '拆章节 -> 每章调用 Codex -> 每章 GPT images2 生成图 -> 汇总排版 -> 输出 PDF\n\n右侧 artifact栏 显示的陈旧文件',
          '围绕\n从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进 右侧是当下 \n测试制作视频',
          '围绕\n\n从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进 \n\n拆章节 -> 每章调用 Codex -> 每章 GPT images2 生成图 -> 汇总排版 -> 制作视频',
        ];

        for (var index = 0; index < prompts.length; index += 1) {
          final sessionKey = 'openclaw-e2e-$index';
          await _selectGatewaySession(controller, sessionKey);
          await expectLater(
            controller
                .sendChatMessage(prompts[index])
                .timeout(_openClawE2ESubmitTimeout),
            completes,
          );
        }

        await fakeGoTaskService.waitForRequestCount(prompts.length);
        expect(fakeGoTaskService.requests, hasLength(prompts.length));
        expect(
          controller.openClawGatewayActiveTurnsInternal.length,
          prompts.length,
        );
        expect(controller.openClawGatewayQueuedTurnsInternal, isEmpty);
        for (var index = 0; index < prompts.length; index += 1) {
          final sessionKey = 'openclaw-e2e-$index';
          expect(
            controller
                .requireTaskThreadForSessionInternal(sessionKey)
                .lifecycleState
                .status,
            'running',
          );
          expect(fakeGoTaskService.requests[index].sessionId, sessionKey);
          expect(
            fakeGoTaskService.requests[index].prompt,
            contains(prompts[index]),
          );
        }
      },
    );

    test(
      'OpenClaw gateway five E2E tasks complete with isolated results and artifacts',
      () async {
        final localHome = await Directory.systemTemp.createTemp(
          'xworkmate-openclaw-five-e2e-',
        );
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedGatewayController(
          fakeGoTaskService,
          homeDir: localHome.path,
        );
        addTearDown(() async {
          fakeGoTaskService.completeAll();
          controller.dispose();
          if (await localHome.exists()) {
            await localHome.delete(recursive: true);
          }
        });

        for (
          var index = 0;
          index < _openClawE2ECanonicalPrompts.length;
          index += 1
        ) {
          final sessionKey = 'openclaw-e2e-result-$index';
          await _selectGatewaySession(controller, sessionKey);
          await expectLater(
            controller
                .sendChatMessage(_openClawE2ECanonicalPrompts[index])
                .timeout(_openClawE2ESubmitTimeout),
            completes,
          );
        }

        await fakeGoTaskService.waitForRequestCount(
          _openClawE2ECanonicalPrompts.length,
        );
        expect(
          controller.openClawGatewayActiveTurnsInternal.length,
          _openClawE2ECanonicalPrompts.length,
        );

        for (
          var index = 0;
          index < _openClawE2ECanonicalPrompts.length;
          index += 1
        ) {
          final sessionKey = 'openclaw-e2e-result-$index';
          final relativePath = switch (index) {
            0 => 'assets/images/security-evolution-01.png',
            1 => 'assets/images/template-security-evolution-01.png',
            2 => 'reports/security-evolution.pdf',
            3 => 'video/security-evolution.mp4',
            _ => 'video/security-evolution-pipeline.mp4',
          };
          fakeGoTaskService.complete(
            sessionKey,
            GoTaskServiceResult(
              success: true,
              message: 'OPENCLAW-E2E-00${index + 1} done',
              turnId: 'turn-$sessionKey',
              raw: <String, dynamic>{
                'artifacts': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'relativePath': relativePath,
                    'content': 'artifact for $sessionKey',
                    'contentType': 'application/octet-stream',
                  },
                ],
              },
              errorMessage: '',
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          );
        }

        for (
          var index = 0;
          index < _openClawE2ECanonicalPrompts.length;
          index += 1
        ) {
          await _waitForThreadLifecycleStatus(
            controller,
            'openclaw-e2e-result-$index',
            'ready',
          );
        }
        await _waitForOpenClawActiveTaskCount(controller, 0);
        expect(controller.openClawGatewayQueuedTurnsInternal, isEmpty);

        for (
          var index = 0;
          index < _openClawE2ECanonicalPrompts.length;
          index += 1
        ) {
          final sessionKey = 'openclaw-e2e-result-$index';
          final thread = controller.requireTaskThreadForSessionInternal(
            sessionKey,
          );
          expect(thread.lifecycleState.status, 'ready');
          expect(thread.lastArtifactSyncStatus, 'synced');
          expect(thread.lastTaskArtifactRelativePaths, hasLength(1));
          expect(
            controller.localSessionMessagesInternal[sessionKey]!.map(
              (message) => message.text,
            ),
            contains('OPENCLAW-E2E-00${index + 1} done'),
          );
          final workspacePath = controller.assistantWorkspacePathForSession(
            sessionKey,
          );
          expect(
            await File(
              '$workspacePath/${thread.lastTaskArtifactRelativePaths.single}',
            ).readAsString(),
            'artifact for $sessionKey',
          );
        }
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
        taskFuture.timeout(const Duration(seconds: 2)),
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

        final activeSessionKeys = await _startOpenClawActiveTasks(
          controller,
          fakeGoTaskService,
          prefix: 'running-openclaw-task',
        );

        await _selectGatewaySession(controller, 'queued-openclaw-task');
        final queuedFuture = controller.sendChatMessage('queued');
        await _waitForThreadLifecycleStatus(
          controller,
          'queued-openclaw-task',
          'queued',
        );
        expect(
          fakeGoTaskService.requests,
          hasLength(openClawGatewayMaxActiveTasksInternal),
        );

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
          activeSessionKeys.first,
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
        await _waitForThreadLifecycleStatus(
          controller,
          activeSessionKeys.first,
          'ready',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          fakeGoTaskService.requests,
          hasLength(openClawGatewayMaxActiveTasksInternal),
        );
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

        final activeSessionKeys = await _startOpenClawActiveTasks(
          controller,
          fakeGoTaskService,
          prefix: 'running-openclaw-stop-task',
        );
        final runningSessionKey = activeSessionKeys.first;

        await _selectGatewaySession(controller, 'queued-openclaw-after-stop');
        final queuedFuture = controller.sendChatMessage('queued');
        await _waitForThreadLifecycleStatus(
          controller,
          'queued-openclaw-after-stop',
          'queued',
        );

        await _selectGatewaySession(controller, runningSessionKey);
        await controller.abortRun();

        expect(fakeGoTaskService.cancelledSessionIds, <String>[
          runningSessionKey,
        ]);
        expect(
          controller.assistantSessionHasPendingRun(runningSessionKey),
          isFalse,
        );
        expect(
          controller
              .requireTaskThreadForSessionInternal(runningSessionKey)
              .lifecycleState
              .lastResultCode,
          'aborted',
        );
        await fakeGoTaskService.waitForRequestCount(
          openClawGatewayMaxActiveTasksInternal + 1,
        );
        expect(
          fakeGoTaskService.requests.last.sessionId,
          'queued-openclaw-after-stop',
        );
        expect(
          controller.assistantSessionHasPendingRun(
            'queued-openclaw-after-stop',
          ),
          isTrue,
        );

        fakeGoTaskService.complete(
          runningSessionKey,
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
        expect(
          fakeGoTaskService.requests,
          hasLength(openClawGatewayMaxActiveTasksInternal + 1),
        );
      },
    );

    test(
      'cancelAssistantTaskForSessionInternal stops an archived OpenClaw task by session key',
      () async {
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(() {
          fakeGoTaskService.completeAll();
          controller.dispose();
        });

        const sessionKey = 'archived-running-openclaw';
        await _selectGatewaySession(controller, sessionKey);
        final pendingFuture = controller.sendChatMessage('stop me');
        await _waitForThreadLifecycleStatus(controller, sessionKey, 'running');
        await controller.saveAssistantTaskArchived(sessionKey, true);

        await controller.cancelAssistantTaskForSessionInternal(sessionKey);

        expect(fakeGoTaskService.cancelledSessionIds, <String>[sessionKey]);
        expect(
          controller.archivedAssistantSessions.map((item) => item.key),
          <String>[sessionKey],
        );

        fakeGoTaskService.complete(
          sessionKey,
          const GoTaskServiceResult(
            success: true,
            message: 'stopped',
            turnId: 'turn-archived-running-openclaw',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await pendingFuture;
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

        final activeSessionKeys = await _startOpenClawActiveTasks(
          controller,
          fakeGoTaskService,
          prefix: 'continue-active-openclaw',
        );

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
        expect(
          fakeGoTaskService.requests,
          hasLength(openClawGatewayMaxActiveTasksInternal),
        );
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
          activeSessionKeys.first,
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
        await fakeGoTaskService.waitForRequestCount(
          openClawGatewayMaxActiveTasksInternal + 1,
        );
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
        fakeGoTaskService.complete(
          activeSessionKeys[1],
          const GoTaskServiceResult(
            success: true,
            message: 'second active done',
            turnId: 'turn-second-active',
            raw: <String, dynamic>{},
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        );
        await fakeGoTaskService.waitForRequestCount(
          openClawGatewayMaxActiveTasksInternal + 2,
        );

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

    test(
      'OpenClaw drain starts queued work when no active turns remain',
      () async {
        final fakeGoTaskService = _BlockingGoTaskServiceClient();
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(() {
          fakeGoTaskService.completeAll();
          controller.dispose();
        });

        const sessionKey = 'stale-slot-queued-task';
        await _selectGatewaySession(controller, sessionKey);
        final turn = OpenClawGatewayQueuedTurnInternal(
          queueId: 'stale-slot-queued-turn',
          sessionKey: sessionKey,
          target: AssistantExecutionTarget.gateway,
          provider: SingleAgentProvider.openclaw,
          message: 'recover queued work',
          thinking: 'off',
          selectedSkillLabels: const <String>[],
          attachments: const <GatewayChatAttachmentPayload>[],
          localAttachments: const <CollaborationAttachment>[],
          workingDirectory: '/tmp/$sessionKey',
          localWorkingDirectory: '/tmp/$sessionKey-local',
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
        controller.markOpenClawGatewayQueuedTurnInternal(sessionKey);

        controller.drainOpenClawGatewayQueueInternal();

        await fakeGoTaskService.waitForRequestCount(1);
        expect(fakeGoTaskService.requests.single.sessionId, sessionKey);
        expect(
          controller
              .requireTaskThreadForSessionInternal(sessionKey)
              .lifecycleState
              .status,
          'running',
        );
        expect(controller.openClawGatewayActiveTurnsInternal.length, 1);
      },
    );

    test('OpenClaw queue overflow fails without artifact sync', () async {
      final fakeGoTaskService = _BlockingGoTaskServiceClient();
      final controller = _connectedGatewayController(fakeGoTaskService);
      addTearDown(controller.dispose);

      for (
        var index = 0;
        index < openClawGatewayMaxActiveTasksInternal;
        index += 1
      ) {
        final sessionKey = 'queue-full-active-$index';
        final turn = OpenClawGatewayQueuedTurnInternal(
          queueId: 'queue-full-active-$index',
          sessionKey: sessionKey,
          target: AssistantExecutionTarget.gateway,
          provider: SingleAgentProvider.openclaw,
          message: 'active $index',
          thinking: 'off',
          selectedSkillLabels: const <String>[],
          attachments: const <GatewayChatAttachmentPayload>[],
          localAttachments: const <CollaborationAttachment>[],
          workingDirectory: '/tmp/$sessionKey',
          localWorkingDirectory: '/tmp/$sessionKey-local',
          remoteWorkingDirectoryHint: '/threads/$sessionKey',
          model: '',
          routing: const ExternalCodeAgentAcpRoutingConfig.auto(
            preferredGatewayTarget: kCanonicalGatewayProviderId,
          ),
          agentId: '',
          metadata: const <String, dynamic>{},
          resumeSessionHint: false,
        );
        controller.openClawGatewayActiveTurnsInternal[turn.queueId] = turn;
      }
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
          localWorkingDirectory: '/tmp/$sessionKey-local',
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
        await _waitForOpenClawActiveTaskCount(controller, 0);
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
        await _waitForOpenClawActiveTaskCount(controller, 0);
        expect(
          controller.chatMessages.map((message) => message.text),
          contains('second task completed'),
        );
      },
    );

    test('OpenClaw task snapshot failure records a terminal result', () async {
      final fakeGoTaskService = _RecordingGoTaskServiceClient()
        ..outcomes.add(
          const GoTaskServiceResult(
            success: true,
            message: '',
            turnId: 'turn-openclaw-poll-failed',
            raw: <String, dynamic>{
              'success': true,
              'status': 'running',
              'sessionId': 'openclaw-poll-failed-task',
              'threadId': 'openclaw-poll-failed-task',
              'turnId': 'turn-openclaw-poll-failed',
              'runId': 'run-openclaw-poll-failed',
              'artifactScope':
                  'tasks/openclaw-poll-failed-task/run-openclaw-poll-failed',
              'artifactDirectory':
                  '/tmp/tasks/openclaw-poll-failed-task/run-openclaw-poll-failed',
              'gatewayProviderId': 'openclaw',
              'runtimeBudgetMinutes': 1,
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          ),
        )
        ..taskOutcomes.add(
          const GatewayAcpException(
            'ACP HTTP connection closed before the OpenClaw task snapshot returned',
            code: 'ACP_HTTP_CONNECTION_CLOSED',
          ),
        );
      final controller = _connectedGatewayController(fakeGoTaskService);
      addTearDown(controller.dispose);

      await _selectGatewaySession(controller, 'openclaw-poll-failed-task');

      await expectLater(
        controller
            .sendChatMessage('输出 PDF')
            .timeout(const Duration(seconds: 2)),
        completes,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final failedThread = controller.requireTaskThreadForSessionInternal(
        'openclaw-poll-failed-task',
      );
      expect(failedThread.lifecycleState.status, 'ready');
      expect(
        failedThread.lifecycleState.lastResultCode,
        'ACP_HTTP_CONNECTION_CLOSED',
      );
      expect(failedThread.lastArtifactSyncStatus, 'failed');
      expect(failedThread.openClawTaskAssociation, isNull);
      expect(
        controller.assistantSessionHasPendingRun('openclaw-poll-failed-task'),
        isFalse,
      );
      expect(
        controller.chatMessages.map((message) => message.text).join('\n'),
        contains('ACP_HTTP_CONNECTION_CLOSED'),
      );
    });

    test(
      'OpenClaw terminal snapshot without required artifacts does not stay running',
      () async {
        final fakeGoTaskService = _RecordingGoTaskServiceClient()
          ..outcomes.add(
            const GoTaskServiceResult(
              success: true,
              message: '',
              turnId: 'turn-openclaw-missing-screenshot',
              raw: <String, dynamic>{
                'success': true,
                'status': 'running',
                'sessionId': 'openclaw-missing-screenshot',
                'threadId': 'openclaw-missing-screenshot',
                'turnId': 'turn-openclaw-missing-screenshot',
                'runId': 'run-openclaw-missing-screenshot',
                'artifactScope':
                    'tasks/openclaw-missing-screenshot/run-openclaw-missing-screenshot',
                'artifactDirectory':
                    '/tmp/tasks/openclaw-missing-screenshot/run-openclaw-missing-screenshot',
                'gatewayProviderId': 'openclaw',
                'runtimeBudgetMinutes': 1,
                'requiredArtifactExtensions': <String>['.png'],
              },
              errorMessage: '',
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          )
          ..taskOutcomes.add(
            const GoTaskServiceResult(
              success: true,
              message: 'gateway completed the screenshot task',
              turnId: 'turn-openclaw-missing-screenshot',
              raw: <String, dynamic>{
                'success': true,
                'status': 'completed',
                'turnId': 'turn-openclaw-missing-screenshot',
                'runId': 'run-openclaw-missing-screenshot',
                'output': 'gateway completed the screenshot task',
              },
              errorMessage: '',
              resolvedModel: '',
              route: GoTaskServiceRoute.externalAcpSingle,
            ),
          );
        final controller = _connectedGatewayController(fakeGoTaskService);
        addTearDown(controller.dispose);

        await _selectGatewaySession(controller, 'openclaw-missing-screenshot');

        await expectLater(
          controller
              .sendChatMessage('执行截图并导出 PNG')
              .timeout(const Duration(milliseconds: 500)),
          completes,
        );
        await _waitForThreadLifecycleStatusWithin(
          controller,
          'openclaw-missing-screenshot',
          'ready',
          const Duration(seconds: 10),
        );
        await _waitForThreadArtifactSyncStatusWithin(
          controller,
          'openclaw-missing-screenshot',
          'no-artifacts',
          const Duration(seconds: 10),
        );

        final thread = controller.requireTaskThreadForSessionInternal(
          'openclaw-missing-screenshot',
        );
        expect(thread.lifecycleState.status, 'ready');
        expect(thread.lifecycleState.lastResultCode, 'success');
        expect(thread.lastArtifactSyncStatus, 'no-artifacts');
        expect(thread.openClawTaskAssociation, isNull);
        expect(
          controller.assistantSessionHasPendingRun(
            'openclaw-missing-screenshot',
          ),
          isFalse,
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

UiFeatureManifest _defaultDesktopManifest() {
  return UiFeatureManifest.fromYamlString(
    File(UiFeatureManifest.assetPath).readAsStringSync(),
  ).copyWithFeature(
    platform: UiFeaturePlatform.desktop,
    module: 'assistant',
    feature: 'multi_agent',
    enabled: true,
    buildModes: const <UiFeatureBuildMode>{
      UiFeatureBuildMode.debug,
      UiFeatureBuildMode.profile,
      UiFeatureBuildMode.release,
    },
  );
}

Future<void> _resilientDelete(Directory dir) async {
  if (!await dir.exists()) {
    return;
  }
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      await dir.delete(recursive: true);
      return;
    } catch (error) {
      debugPrint('Temporary directory delete retry: $error');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  await dir.delete(recursive: true);
}

AppController _sandboxController({
  SecureConfigStore? store,
  RuntimeCoordinator? runtimeCoordinator,
  DesktopPlatformService? desktopPlatformService,
  UiFeatureManifest? uiFeatureManifest,
  List<SingleAgentProvider>? initialBridgeProviderCatalog,
  List<SingleAgentProvider>? initialGatewayProviderCatalog,
  List<AssistantExecutionTarget>? initialAvailableExecutionTargets,
  AccountRuntimeClient Function(String baseUrl)? accountClientFactory,
  Map<String, String>? environmentOverride,
  GoTaskServiceClient? goTaskServiceClient,
  String? homeDir,
}) {
  final actualHome =
      homeDir ??
      Directory.systemTemp.createTempSync('xworkmate-sandbox-home-').path;
  if (homeDir == null) {
    addTearDown(() async {
      await _resilientDelete(Directory(actualHome));
    });
  }
  return AppController(
    store: store,
    runtimeCoordinator: runtimeCoordinator,
    desktopPlatformService: desktopPlatformService,
    uiFeatureManifest: uiFeatureManifest,
    initialBridgeProviderCatalog: initialBridgeProviderCatalog,
    initialGatewayProviderCatalog: initialGatewayProviderCatalog,
    initialAvailableExecutionTargets: initialAvailableExecutionTargets,
    accountClientFactory: accountClientFactory,
    environmentOverride: <String, String>{
      ...?environmentOverride,
      'HOME': actualHome,
    },
    goTaskServiceClient: goTaskServiceClient,
  );
}

AppController _connectedController(
  GoTaskServiceClient client, {
  String? homeDir,
}) {
  return _sandboxController(
    goTaskServiceClient: client,
    uiFeatureManifest: _defaultDesktopManifest(),
    environmentOverride: const <String, String>{
      'BRIDGE_AUTH_TOKEN': 'bridge-token',
    },
    initialBridgeProviderCatalog: const <SingleAgentProvider>[
      SingleAgentProvider.codex,
    ],
    initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
      AssistantExecutionTarget.agent,
    ],
    homeDir: homeDir,
  );
}

AppController _connectedGatewayController(
  GoTaskServiceClient client, {
  String? homeDir,
}) {
  return _sandboxController(
    goTaskServiceClient: client,
    uiFeatureManifest: _defaultDesktopManifest(),
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
    homeDir: homeDir,
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

Future<void> _waitForOpenClawActiveTaskCount(
  AppController controller,
  int expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (controller.openClawGatewayActiveTurnsInternal.length == expected) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(controller.openClawGatewayActiveTurnsInternal.length, expected);
}

Future<List<String>> _startOpenClawActiveTasks(
  AppController controller,
  _BlockingGoTaskServiceClient fakeGoTaskService, {
  required String prefix,
}) async {
  final sessionKeys = <String>[];
  for (
    var index = 0;
    index < openClawGatewayMaxActiveTasksInternal;
    index += 1
  ) {
    final sessionKey = '$prefix-$index';
    sessionKeys.add(sessionKey);
    await _selectGatewaySession(controller, sessionKey);
    await expectLater(
      controller
          .sendChatMessage('active task $index')
          .timeout(const Duration(seconds: 2)),
      completes,
    );
    await fakeGoTaskService.waitForRequestCount(index + 1);
    expect(
      controller
          .requireTaskThreadForSessionInternal(sessionKey)
          .lifecycleState
          .status,
      'running',
    );
  }
  return sessionKeys;
}

Future<void> _waitForThreadLifecycleStatus(
  AppController controller,
  String sessionKey,
  String status,
) async {
  await _waitForThreadLifecycleStatusWithin(
    controller,
    sessionKey,
    status,
    const Duration(seconds: 15),
  );
}

Future<void> _waitForThreadLifecycleStatusWithin(
  AppController controller,
  String sessionKey,
  String status,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
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

Future<void> _waitForThreadArtifactSyncStatusWithin(
  AppController controller,
  String sessionKey,
  String status,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final currentStatus = controller
        .taskThreadForSessionInternal(sessionKey)
        ?.lastArtifactSyncStatus;
    if (currentStatus == status) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final currentStatus = controller
      .taskThreadForSessionInternal(sessionKey)
      ?.lastArtifactSyncStatus;
  throw StateError(
    'Timed out waiting for $sessionKey artifact sync status $status. Current status: $currentStatus.',
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
  final List<Object> taskOutcomes = <Object>[];
  Future<void> Function(GoTaskServiceRequest request)? onExecuteTask;

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    executeCount += 1;
    requests.add(request);
    await onExecuteTask?.call(request);
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
  Future<GoTaskServiceResult> getTask({
    required AssistantExecutionTarget target,
    required OpenClawTaskAssociation association,
    required GoTaskServiceRoute route,
  }) async {
    if (taskOutcomes.isNotEmpty) {
      final outcome = taskOutcomes.removeAt(0);
      if (outcome is GoTaskServiceResult) {
        return outcome;
      }
      throw outcome;
    }
    return GoTaskServiceResult(
      success: true,
      message: 'ok',
      turnId: association.turnId,
      raw: <String, dynamic>{
        'success': true,
        'status': 'completed',
        'turnId': association.turnId,
        'runId': association.runId,
        'output': 'ok',
      },
      errorMessage: '',
      resolvedModel: '',
      route: route,
    );
  }

  @override
  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
    OpenClawTaskAssociation? association,
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

  @override
  Future<GoTaskServiceResult> getTask({
    required AssistantExecutionTarget target,
    required OpenClawTaskAssociation association,
    required GoTaskServiceRoute route,
  }) async {
    return GoTaskServiceResult(
      success: true,
      message: 'cleanup',
      turnId: association.turnId,
      raw: <String, dynamic>{
        'success': true,
        'status': 'completed',
        'turnId': association.turnId,
        'runId': association.runId,
        'output': 'cleanup',
      },
      errorMessage: '',
      resolvedModel: '',
      route: route,
    );
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
    OpenClawTaskAssociation? association,
  }) async {
    cancelledSessionIds.add(sessionId);
  }

  @override
  Future<void> dispose() async {}
}
