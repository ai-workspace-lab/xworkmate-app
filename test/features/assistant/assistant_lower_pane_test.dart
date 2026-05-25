import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_clipboard.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_models.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_picker.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/surface_card.dart';

void main() {
  group('AssistantLowerPaneInternal', () {
    testWidgets(
      'does not fabricate providers when live capabilities are unavailable',
      (tester) async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );

        await tester.pumpWidget(
          _buildTestApp(child: _buildLowerPane(controller: controller)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('assistant-provider-button')),
          findsOneWidget,
        );
        expect(find.text('未提供'), findsNothing);

        final providerButton = tester
            .widget<PopupMenuButton<SingleAgentProvider>>(
              find.byKey(const Key('assistant-provider-button')),
            );
        expect(providerButton.enabled, isFalse);

        expect(
          find.byKey(const Key('assistant-provider-menu-item-codex')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('assistant-provider-menu-item-opencode')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('assistant-provider-menu-item-gemini')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('assistant-provider-menu-item-openclaw')),
          findsNothing,
        );
      },
    );

    testWidgets('shows mode-specific provider catalogs', (tester) async {
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

      await controller.sessionsController.switchSession('unit-fixture-task-a');

      await tester.pumpWidget(
        _buildTestApp(child: _buildLowerPane(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assistant-provider-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assistant-provider-menu-item-codex')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-provider-menu-item-opencode')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-provider-menu-item-gemini')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await tester.tap(
        find.byKey(const Key('assistant-provider-menu-item-codex')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assistant-execution-target-button')),
        findsOneWidget,
      );

      final gatewayThread = controller
          .requireTaskThreadForSessionInternal('unit-fixture-task-a')
          .copyWith(
            executionBinding: ExecutionBinding(
              executionMode: threadExecutionModeFromAssistantExecutionTarget(
                AssistantExecutionTarget.gateway,
              ),
              executorId: SingleAgentProvider.openclaw.providerId,
              providerId: SingleAgentProvider.openclaw.providerId,
              endpointId: '',
              executionModeSource: ThreadSelectionSource.explicit,
              providerSource: ThreadSelectionSource.explicit,
            ),
            updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          );
      controller.taskThreadRepositoryInternal.replace(
        gatewayThread,
        persist: false,
      );
      controller.notifyListeners();
      await tester.pumpAndSettle();

      expect(controller.assistantExecutionTarget.name, 'gateway');
      expect(
        find.byKey(const Key('assistant-provider-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('assistant-provider-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assistant-provider-menu-item-openclaw')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('assistant-provider-menu-item-openclaw')),
      );
      await tester.pumpAndSettle();

      final agentThread = controller
          .requireTaskThreadForSessionInternal('unit-fixture-task-a')
          .copyWith(
            executionBinding: ExecutionBinding(
              executionMode: threadExecutionModeFromAssistantExecutionTarget(
                AssistantExecutionTarget.agent,
              ),
              executorId: SingleAgentProvider.codex.providerId,
              providerId: SingleAgentProvider.codex.providerId,
              endpointId: '',
              executionModeSource: ThreadSelectionSource.explicit,
              providerSource: ThreadSelectionSource.explicit,
            ),
            updatedAtMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
          );
      controller.taskThreadRepositoryInternal.replace(
        agentThread,
        persist: false,
      );
      controller.notifyListeners();
      await tester.pumpAndSettle();

      expect(controller.assistantExecutionTarget.name, 'agent');
      expect(
        find.byKey(const Key('assistant-provider-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('assistant-provider-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assistant-provider-menu-item-codex')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-provider-menu-item-openclaw')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('assistant-provider-menu-item-opencode')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-provider-menu-item-gemini')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('shows assistant providers and allows switching provider', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
        initialBridgeProviderCatalog: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
          SingleAgentProvider.opencode,
          SingleAgentProvider.gemini,
        ],
      );
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('unit-fixture-task-a');

      await tester.pumpWidget(
        _buildTestApp(child: _buildLowerPane(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assistant-provider-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assistant-provider-menu-item-codex')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-provider-menu-item-opencode')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-provider-menu-item-gemini')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('assistant-provider-menu-item-opencode')),
      );
      await tester.pumpAndSettle();

      expect(
        controller
            .assistantProviderForSession(controller.currentSessionKey)
            .providerId,
        'opencode',
      );
    });

    testWidgets('locks gateway provider menu to canonical openclaw only', (
      tester,
    ) async {
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

      await controller.sessionsController.switchSession('unit-fixture-task-a');
      controller.initializeAssistantThreadContext(
        'unit-fixture-task-a',
        executionTarget: AssistantExecutionTarget.gateway,
        messageViewMode: controller.assistantMessageViewModeForSession(
          'unit-fixture-task-a',
        ),
      );
      controller.notifyListeners();

      await tester.pumpWidget(
        _buildTestApp(child: _buildLowerPane(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assistant-provider-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assistant-provider-menu-item-openclaw')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-provider-menu-item-hermes')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('assistant-provider-menu-item-codex')),
        findsNothing,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      expect(
        controller
            .assistantProviderForSession(controller.currentSessionKey)
            .providerId,
        'openclaw',
      );
    });

    testWidgets(
      'does not fabricate agent mode when only OpenClaw gateway is live',
      (tester) async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
          initialGatewayProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.openclaw,
          ],
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.gateway,
          ],
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );
        controller.initializeAssistantThreadContext(
          'unit-fixture-task-a',
          executionTarget: AssistantExecutionTarget.gateway,
          messageViewMode: controller.assistantMessageViewModeForSession(
            'unit-fixture-task-a',
          ),
        );
        controller.notifyListeners();

        await tester.pumpWidget(
          _buildTestApp(child: _buildLowerPane(controller: controller)),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('assistant-execution-target-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('assistant-execution-target-menu-item-agent')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('assistant-execution-target-menu-item-gateway')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'allows switching from Gateway back to Agent when bridge reports both',
      (tester) async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
          initialBridgeProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
            SingleAgentProvider.opencode,
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
        controller.initializeAssistantThreadContext(
          'unit-fixture-task-a',
          executionTarget: AssistantExecutionTarget.gateway,
          messageViewMode: controller.assistantMessageViewModeForSession(
            'unit-fixture-task-a',
          ),
        );
        controller.notifyListeners();

        await tester.pumpWidget(
          _buildTestApp(child: _buildLowerPane(controller: controller)),
        );
        await tester.pumpAndSettle();

        expect(controller.currentAssistantExecutionTarget.isGateway, isTrue);

        await tester.tap(
          find.byKey(const Key('assistant-execution-target-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('assistant-execution-target-menu-item-agent')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('assistant-execution-target-menu-item-gateway')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('assistant-execution-target-menu-item-agent')),
        );
        await tester.pumpAndSettle();

        expect(controller.currentAssistantExecutionTarget.isAgent, isTrue);
        expect(
          controller
              .providerCatalogForExecutionTarget(AssistantExecutionTarget.agent)
              .map((provider) => provider.providerId),
          const <String>['codex', 'opencode'],
        );
        expect(
          controller
              .providerCatalogForExecutionTarget(
                AssistantExecutionTarget.gateway,
              )
              .map((provider) => provider.providerId),
          const <String>[kCanonicalGatewayProviderId],
        );
      },
    );

    testWidgets('uses submit button instead of connect action', (tester) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('unit-fixture-task-a');

      var sendCount = 0;

      await tester.pumpWidget(
        _buildTestApp(
          child: _buildLowerPane(
            controller: controller,
            inputController: TextEditingController(text: 'hello'),
            onSend: () async {
              sendCount += 1;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('提交'), findsOneWidget);
      expect(find.text('连接'), findsNothing);

      await tester.tap(find.byKey(const Key('assistant-send-button')));
      await tester.pump();

      expect(sendCount, 1);
    });

    testWidgets('keeps bottom action row visible when pane height is reduced', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('unit-fixture-task-a');

      await tester.pumpWidget(
        _buildTestApp(
          height: 112,
          child: _buildLowerPane(
            controller: controller,
            inputController: TextEditingController(text: 'hello'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final paneBottom = tester
          .getBottomLeft(find.byKey(const Key('assistant-lower-pane-host')))
          .dy;
      final sendButtonBottom = tester
          .getBottomLeft(find.byKey(const Key('assistant-send-button')))
          .dy;

      expect(sendButtonBottom, lessThanOrEqualTo(paneBottom));
    });

    testWidgets('groups all visible skills by source', (tester) async {
      final toggledKeys = <String>[];
      final searchController = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(searchController.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _buildTestApp(
          child: SkillPickerPopoverInternal(
            maxHeight: 360,
            searchController: searchController,
            searchFocusNode: focusNode,
            selectedSkillKeys: const <String>[],
            filteredSkills: const <ComposerSkillOptionInternal>[
              ComposerSkillOptionInternal(
                key: 'pdf',
                label: 'PDF',
                description: 'Create PDF files',
                sourceLabel: 'openclaw-workspace',
                groupLabel: 'Workspace Skills',
                groupSortOrder: 0,
                icon: Icons.key_rounded,
              ),
              ComposerSkillOptionInternal(
                key: 'browser-automation',
                label: 'Browser Automation',
                description: 'Automate browsers',
                sourceLabel: 'agents-skills-personal',
                groupLabel: 'Agent Skills',
                groupSortOrder: 1,
                icon: Icons.key_rounded,
              ),
              ComposerSkillOptionInternal(
                key: 'gateway-search',
                label: 'Gateway Search',
                description: 'Search through the gateway',
                sourceLabel: 'gateway',
                groupLabel: 'Gateway Skills',
                groupSortOrder: 2,
                icon: Icons.key_rounded,
              ),
            ],
            isLoading: false,
            hasQuery: false,
            onQueryChanged: (_) {},
            onToggleSkill: toggledKeys.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Workspace Skills'), findsOneWidget);
      expect(find.text('Agent Skills'), findsOneWidget);
      expect(find.text('Gateway Skills'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('assistant-skill-option-browser-automation'),
        ),
      );
      await tester.pump();

      expect(toggledKeys, const <String>['browser-automation']);
    });

    testWidgets('search results only keep groups with matching skills', (
      tester,
    ) async {
      final searchController = TextEditingController(text: 'gateway');
      final focusNode = FocusNode();
      addTearDown(searchController.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _buildTestApp(
          child: SkillPickerPopoverInternal(
            maxHeight: 360,
            searchController: searchController,
            searchFocusNode: focusNode,
            selectedSkillKeys: const <String>[],
            filteredSkills: const <ComposerSkillOptionInternal>[
              ComposerSkillOptionInternal(
                key: 'gateway-search',
                label: 'Gateway Search',
                description: 'Search through the gateway',
                sourceLabel: 'gateway',
                groupLabel: 'Gateway Skills',
                groupSortOrder: 2,
                icon: Icons.key_rounded,
              ),
            ],
            isLoading: false,
            hasQuery: true,
            onQueryChanged: (_) {},
            onToggleSkill: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gateway Skills'), findsOneWidget);
      expect(find.text('Gateway Search'), findsOneWidget);
      expect(find.text('Workspace Skills'), findsNothing);
      expect(find.text('Agent Skills'), findsNothing);
    });
  });
}

Widget _buildTestApp({required Widget child, double height = 360}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Material(
      child: Center(
        child: SizedBox(
          key: const Key('assistant-lower-pane-host'),
          width: 1400,
          height: height,
          child: child,
        ),
      ),
    ),
  );
}

Widget _buildLowerPane({
  required AppController controller,
  TextEditingController? inputController,
  Future<void> Function()? onSend,
}) {
  final composerController = inputController ?? TextEditingController();
  return SurfaceCard(
    child: AssistantLowerPaneInternal(
      bottomContentInset: 0,
      controller: controller,
      inputController: composerController,
      focusNode: FocusNode(),
      thinkingLabel: 'medium',
      showModelControl: false,
      modelLabel: 'gpt-5.4',
      modelOptions: const <String>[],
      attachments: const <ComposerAttachmentInternal>[],
      availableSkills: const <ComposerSkillOptionInternal>[],
      selectedSkillKeys: const <String>[],
      onRemoveAttachment: (_) {},
      onToggleSkill: (_) {},
      onThinkingChanged: (_) {},
      onModelChanged: (_) async {},
      onPickAttachments: () {},
      onAddAttachment: (_) {},
      onPasteImageAttachment: () async => null,
      onComposerContentHeightChanged: (_) {},
      onComposerInputHeightChanged: (_) {},
      onSend: onSend ?? () async {},
    ),
  );
}
