import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_clipboard.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_picker.dart';
import 'package:xworkmate/features/assistant/assistant_page_main.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/surface_card.dart';

void main() {
  group('AssistantLowerPaneInternal', () {
    for (final variant in [
      'offline',
      'direct catalog',
      'Gateway catalog',
      'legacy Agent binding',
    ]) {
      testWidgets('$variant never exposes Provider or route controls', (
        tester,
      ) async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
          initialBridgeProviderCatalog: variant == 'direct catalog'
              ? const [SingleAgentProvider.codex, SingleAgentProvider.opencode]
              : const [],
          initialGatewayProviderCatalog:
              variant == 'Gateway catalog' || variant == 'legacy Agent binding'
              ? const [SingleAgentProvider.openclaw]
              : const [],
        );
        addTearDown(controller.dispose);
        await controller.sessionsController.switchSession(
          'unit-fixture-task-a',
        );
        if (variant == 'legacy Agent binding') {
          controller.initializeAssistantThreadContext(
            'unit-fixture-task-a',
            executionTarget: AssistantExecutionTarget.agent,
          );
        }
        await tester.pumpWidget(
          _buildTestApp(child: _buildLowerPane(controller: controller)),
        );
        await tester.pumpAndSettle();
        expect(
          controller.currentAssistantExecutionTarget,
          AssistantExecutionTarget.gateway,
        );
        expect(
          find.byKey(const Key('assistant-product-mode-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('assistant-provider-button')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('assistant-execution-target-button')),
          findsNothing,
        );
        for (final provider in ['openclaw', 'codex', 'opencode', 'gemini']) {
          expect(
            find.byKey(Key('assistant-provider-menu-item-$provider')),
            findsNothing,
          );
        }
      });
    }

    testWidgets(
      'four product modes are independent of the fixed Gateway route',
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
          find.byKey(const Key('assistant-product-mode-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('assistant-execution-target-menu-item-agent')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('assistant-execution-target-menu-item-gateway')),
          findsNothing,
        );
        for (final mode in ['chat', 'work', 'coding', 'autoBot']) {
          expect(
            find.byKey(Key('assistant-product-mode-$mode')),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets(
      'legacy Bridge targets do not become selectable product routes',
      (tester) async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
          uiFeatureManifest: _defaultDesktopManifest(),
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
          find.byKey(const Key('assistant-product-mode-button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('assistant-execution-target-menu-item-agent')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('assistant-execution-target-menu-item-gateway')),
          findsNothing,
        );

        expect(controller.currentAssistantExecutionTarget.isGateway, isTrue);
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

    testWidgets('skill picker shows loading state while skills refresh', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);
      controller.skillsController.loadingInternal = true;

      await controller.sessionsController.switchSession('unit-fixture-task-a');

      await tester.pumpWidget(
        _buildTestApp(child: _buildLowerPane(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assistant-skill-picker-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('正在加载技能…'), findsOneWidget);
      expect(find.text('当前没有已加载技能。'), findsNothing);
    });

    testWidgets('skill picker displays refreshed skills and filters them', (
      tester,
    ) async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('unit-fixture-task-a');

      await tester.pumpWidget(
        _buildTestApp(
          child: _buildLowerPane(
            controller: controller,
            availableSkills: const <ComposerSkillOptionInternal>[
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
                key: 'pdf',
                label: 'PDF Writer',
                description: 'Create PDF files',
                sourceLabel: 'openclaw-workspace',
                groupLabel: 'Workspace Skills',
                groupSortOrder: 0,
                icon: Icons.key_rounded,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('assistant-skill-picker-button')));
      await tester.pumpAndSettle();

      expect(find.text('Browser Automation'), findsOneWidget);
      expect(find.text('PDF Writer'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('assistant-skill-picker-search')),
        'browser',
      );
      await tester.pumpAndSettle();

      expect(find.text('Browser Automation'), findsOneWidget);
      expect(find.text('PDF Writer'), findsNothing);
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
            errorText: null,
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
            errorText: null,
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

    testWidgets(
      'empty skill picker shows refresh error instead of empty state',
      (tester) async {
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
              filteredSkills: const <ComposerSkillOptionInternal>[],
              isLoading: false,
              errorText: 'skills.status request failed',
              hasQuery: false,
              onQueryChanged: (_) {},
              onToggleSkill: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('技能列表加载失败，请稍后重试。'), findsOneWidget);
        expect(find.text('skills.status request failed'), findsOneWidget);
        expect(find.text('当前没有已加载技能。'), findsNothing);
      },
    );
  });
}

UiFeatureManifest _defaultDesktopManifest() {
  return UiFeatureManifest.fromYamlString(
    File(UiFeatureManifest.assetPath).readAsStringSync(),
  );
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
  List<ComposerSkillOptionInternal> availableSkills =
      const <ComposerSkillOptionInternal>[],
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
      availableSkills: availableSkills,
      selectedSkillKeys: const <String>[],
      onRemoveAttachment: (_) {},
      onToggleSkill: (_) {},
      onThinkingChanged: (_) {},
      onModelChanged: (_) async {},
      onPickAttachments: () {},
      onAddAttachment: (_) {},
      onPasteImageAttachment: () async => null,
      onSend: onSend ?? () async {},
    ),
  );
}
