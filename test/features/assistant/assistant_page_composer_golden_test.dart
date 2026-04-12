import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
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

  testWidgets('renders composer with thread provider controls only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 320));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    final root = Directory.systemTemp.createTempSync(
      'xworkmate-composer-golden-',
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
      skillDirectoryAccessService: _GoldenSkillDirectoryAccessService(
        root.path,
      ),
      goTaskServiceClient: const _GoldenGoTaskServiceClient(),
      singleAgentSharedSkillScanRootOverrides: const <String>[],
    );
    _seedBridgeProviders(controller, const <SingleAgentProvider>[
      SingleAgentProvider.codex,
    ]);
    final inputController = TextEditingController(text: '请整理今天的任务进展');
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
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('assistant-composer-boundary'),
              child: SizedBox(
                width: 1280,
                child: ComposerBarInternal(
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
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byKey(const ValueKey('assistant-composer-boundary')),
      matchesGoldenFile(
        'goldens/assistant_page_composer_working_directory.png',
      ),
    );
  });
}

void _seedBridgeProviders(
  AppController controller,
  List<SingleAgentProvider> providers,
) {
  controller.bridgeAdvertisedProvidersInternal = providers;
}

class _GoldenSkillDirectoryAccessService
    implements SkillDirectoryAccessService {
  const _GoldenSkillDirectoryAccessService(this.homeDirectory);

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

class _GoldenGoTaskServiceClient implements GoTaskServiceClient {
  const _GoldenGoTaskServiceClient();

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
      multiAgent: true,
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
