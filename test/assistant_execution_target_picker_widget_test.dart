import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/app/app_controller_desktop_workspace_execution.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_bar.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_clipboard.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_skill_models.dart';
import 'package:xworkmate/runtime/desktop_platform_service.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/skill_directory_access.dart';
import 'package:xworkmate/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'mode picker keeps single-agent and gateway visible while thread-only provider controls stay available',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'xworkmate-picker-widget-test-',
      );
      final store = SecureConfigStore(
        enableSecureStorage: false,
        appDataRootPathResolver: () async => '${root.path}/settings.sqlite3',
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
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
      );
      final inputController = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(() async {
        controller.dispose();
        inputController.dispose();
        focusNode.dispose();
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      controller.appUiStateInternal = controller.appUiState.copyWith(
        savedGatewayTargets: const <String>['gateway'],
      );
      controller.lastObservedSettingsSnapshotInternal =
          controller.settingsController.snapshotInternal;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: ComposerBarInternal(
              controller: controller,
              inputController: inputController,
              focusNode: focusNode,
              thinkingLabel: 'Normal',
              showModelControl: false,
              modelLabel: '',
              modelOptions: const <String>[],
              attachments: const <ComposerAttachmentInternal>[],
              availableSkills: const <ComposerSkillOptionInternal>[],
              selectedSkillKeys: const <String>[],
              onRemoveAttachment: (_) {},
              onToggleSkill: (_) {},
              onThinkingChanged: (_) {},
              onModelChanged: (_) async {},
              onOpenGateway: () {},
              onOpenAiGatewaySettings: () {},
              onReconnectGateway: () async {},
              onPickAttachments: () {},
              onAddAttachment: (_) {},
              onPasteImageAttachment: () async => null,
              onContentHeightChanged: (_) {},
              onInputHeightChanged: (_) {},
              onSend: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        controller.assistantExecutionTarget,
        AssistantExecutionTarget.singleAgent,
      );

      final buttonFinder = find.byKey(
        const Key('assistant-execution-target-button'),
      );
      expect(buttonFinder, findsOneWidget);

      final button = tester.widget<PopupMenuButton<AssistantExecutionTarget>>(
        buttonFinder,
      );
      final items = button.itemBuilder(tester.element(buttonFinder));
      final values = items
          .whereType<PopupMenuItem<AssistantExecutionTarget>>()
          .map((item) => item.value)
          .toList(growable: false);

      expect(values, <AssistantExecutionTarget>[
        AssistantExecutionTarget.singleAgent,
        AssistantExecutionTarget.gateway,
      ]);
      expect(
        find.byKey(const Key('assistant-working-directory-button')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('assistant-single-agent-provider-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assistant-collaboration-toggle')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('gateway mode shows the canonical OpenClaw provider selector', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync(
      'xworkmate-picker-widget-gateway-test-',
    );
    final store = SecureConfigStore(
      enableSecureStorage: false,
      appDataRootPathResolver: () async => '${root.path}/settings.sqlite3',
      secretRootPathResolver: () async => root.path,
      supportRootPathResolver: () async => root.path,
    );
    final controller = AppController(
      store: store,
      desktopPlatformService: UnsupportedDesktopPlatformService(),
      skillDirectoryAccessService: _FakeSkillDirectoryAccessService(root.path),
      goTaskServiceClient: const _FakeGoTaskServiceClient(),
      singleAgentSharedSkillScanRootOverrides: const <String>[],
      availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
        SingleAgentProvider.codex,
      ],
    );
    final inputController = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(() async {
      controller.dispose();
      inputController.dispose();
      focusNode.dispose();
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });

    controller.appUiStateInternal = controller.appUiState.copyWith(
      savedGatewayTargets: const <String>['gateway'],
    );
    controller.lastObservedSettingsSnapshotInternal =
        controller.settingsController.snapshotInternal;
    controller.initializeAssistantThreadContext(
      controller.currentSessionKey,
      executionTarget: AssistantExecutionTarget.gateway,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: ComposerBarInternal(
            controller: controller,
            inputController: inputController,
            focusNode: focusNode,
            thinkingLabel: 'Normal',
            showModelControl: false,
            modelLabel: '',
            modelOptions: const <String>[],
            attachments: const <ComposerAttachmentInternal>[],
            availableSkills: const <ComposerSkillOptionInternal>[],
            selectedSkillKeys: const <String>[],
            onRemoveAttachment: (_) {},
            onToggleSkill: (_) {},
            onThinkingChanged: (_) {},
            onModelChanged: (_) async {},
            onOpenGateway: () {},
            onOpenAiGatewaySettings: () {},
            onReconnectGateway: () async {},
            onPickAttachments: () {},
            onAddAttachment: (_) {},
            onPasteImageAttachment: () async => null,
            onContentHeightChanged: (_) {},
            onInputHeightChanged: (_) {},
            onSend: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const Key('assistant-single-agent-provider-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('assistant-gateway-provider-button')),
      findsOneWidget,
    );
    final gatewayButton = tester.widget<PopupMenuButton<String>>(
      find.byKey(const Key('assistant-gateway-provider-button')),
    );
    final items = gatewayButton.itemBuilder(
      tester.element(
        find.byKey(const Key('assistant-gateway-provider-button')),
      ),
    );
    expect(items, hasLength(1));
    expect(
      items.whereType<PopupMenuItem<String>>().single.value,
      kCanonicalGatewayProviderId,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
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
  Future<ExternalCodeAgentAcpRoutingResolution> resolveExternalAcpRouting({
    required String taskPrompt,
    required String workingDirectory,
    required ExternalCodeAgentAcpRoutingConfig routing,
    String aiGatewayBaseUrl = '',
    String aiGatewayApiKey = '',
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
  Future<void> syncExternalProviders(
    List<ExternalCodeAgentAcpSyncedProvider> providers,
  ) async {}
}
