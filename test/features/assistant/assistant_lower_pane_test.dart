import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_clipboard.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_models.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/surface_card.dart';

void main() {
  group('AssistantLowerPaneInternal', () {
    testWidgets(
      'does not fabricate providers when live capabilities are unavailable',
      (tester) async {
        final controller = AppController();
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('session-1');

        await tester.pumpWidget(
          _buildTestApp(child: _buildLowerPane(controller: controller)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('assistant-provider-button')),
          findsOneWidget,
        );
        expect(find.text('未提供'), findsNothing);

        final providerButton = tester.widget<PopupMenuButton<SingleAgentProvider>>(
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
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('assistant-provider-menu-item-codex')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('assistant-execution-target-button')),
        findsOneWidget,
      );

      final gatewayThread = controller
          .requireTaskThreadForSessionInternal('session-1')
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
          .requireTaskThreadForSessionInternal('session-1')
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
        initialBridgeProviderCatalog: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
          SingleAgentProvider.opencode,
          SingleAgentProvider.gemini,
        ],
      );
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('session-1');

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
      controller.initializeAssistantThreadContext(
        'session-1',
        executionTarget: AssistantExecutionTarget.gateway,
        messageViewMode: controller.assistantMessageViewModeForSession(
          'session-1',
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

    testWidgets('uses submit button instead of connect action', (tester) async {
      final controller = AppController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('session-1');

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
  });
}

Widget _buildTestApp({required Widget child}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Material(
      child: Center(child: SizedBox(width: 1400, height: 360, child: child)),
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
