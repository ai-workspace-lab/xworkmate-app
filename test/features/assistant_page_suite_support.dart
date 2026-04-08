// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/ui_feature_manifest.dart';
import 'package:xworkmate/features/assistant/assistant_page.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/codex_runtime.dart';
import 'package:xworkmate/runtime/device_identity_store.dart';
import 'package:xworkmate/runtime/gateway_runtime.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/multi_agent_mount_resolver.dart';
import 'package:xworkmate/runtime/multi_agent_mounts.dart';
import 'package:xworkmate/runtime/multi_agent_orchestrator.dart';
import 'package:xworkmate/runtime/runtime_coordinator.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/pane_resize_handle.dart';
import '../test_support.dart';
import '../runtime/app_controller_thread_skills_suite_fixtures.dart';
import 'assistant_page_suite_core.dart';
import 'assistant_page_suite_composer.dart';

class AssistantPageMemorySecureConfigStoreInternal extends SecureConfigStore {
  AssistantPageMemorySecureConfigStoreInternal({
    required SettingsSnapshot initialSettingsSnapshot,
    List<TaskThread> initialTaskThreads = const <TaskThread>[],
  }) : _settingsSnapshot = initialSettingsSnapshot,
       _taskThreads = List<TaskThread>.from(initialTaskThreads),
       super(enableSecureStorage: false);

  SettingsSnapshot _settingsSnapshot;
  List<TaskThread> _taskThreads;
  Map<String, String> _secretValueByRef = <String, String>{};
  Map<String, dynamic> _supportJsonByPath = <String, dynamic>{};
  LocalDeviceIdentity? _deviceIdentity;

  @override
  Future<void> initialize() async {}

  @override
  Future<SettingsSnapshot> loadSettingsSnapshot() async {
    return _settingsSnapshot;
  }

  @override
  Future<SettingsSnapshot> reloadSettingsSnapshot() async {
    return _settingsSnapshot;
  }

  @override
  Future<SettingsSnapshotReloadResult> reloadSettingsSnapshotResult() async {
    return SettingsSnapshotReloadResult(
      snapshot: _settingsSnapshot,
      status: SettingsSnapshotReloadStatus.applied,
    );
  }

  @override
  Future<void> saveSettingsSnapshot(SettingsSnapshot snapshot) async {
    _settingsSnapshot = snapshot;
  }

  @override
  Future<List<File>> resolvedSettingsFiles() async => const <File>[];

  @override
  Future<List<Directory>> resolvedSettingsWatchDirectories() async =>
      const <Directory>[];

  @override
  Future<List<TaskThread>> loadTaskThreads() async {
    return List<TaskThread>.from(_taskThreads);
  }

  @override
  Future<void> saveTaskThreads(List<TaskThread> records) async {
    _taskThreads = List<TaskThread>.from(records);
  }

  @override
  Future<void> clearAssistantLocalState() async {
    _settingsSnapshot = _settingsSnapshot.copyWith(
      assistantCustomTaskTitles: const <String, String>{},
      assistantArchivedTaskKeys: const <String>[],
      assistantLastSessionKey: '',
    );
    _taskThreads = const <TaskThread>[];
  }

  @override
  Future<List<SecretAuditEntry>> loadAuditTrail() async =>
      const <SecretAuditEntry>[];

  @override
  Future<void> appendAudit(SecretAuditEntry entry) async {}

  @override
  Future<Map<String, String>> loadSecureRefs() async =>
      Map<String, String>.unmodifiable(_secretValueByRef);

  @override
  Future<Map<String, dynamic>?> loadSupportJson(String relativePath) async {
    final payload = _supportJsonByPath[relativePath.trim()];
    return payload is Map<String, dynamic> ? payload : null;
  }

  @override
  Future<void> saveSupportJson(
    String relativePath,
    Map<String, dynamic> payload,
  ) async {
    _supportJsonByPath = <String, dynamic>{
      ..._supportJsonByPath,
      relativePath.trim(): Map<String, dynamic>.from(payload),
    };
  }

  @override
  Future<AccountSyncState?> loadAccountSyncState() async => null;

  @override
  Future<void> saveAccountSyncState(AccountSyncState value) async {}

  @override
  Future<void> clearAccountSyncState() async {}

  @override
  Future<AccountRemoteProfile?> loadAccountProfile() async => null;

  @override
  Future<void> saveAccountProfile(AccountRemoteProfile value) async {}

  @override
  Future<void> clearAccountProfile() async {}

  @override
  Future<String?> loadAccountManagedSecret({required String target}) async =>
      null;

  @override
  Future<void> saveAccountManagedSecret({
    required String target,
    required String value,
  }) async {}

  @override
  Future<void> clearAccountManagedSecret({required String target}) async {}

  @override
  Future<void> clearAccountManagedSecrets() async {}

  @override
  Future<LocalDeviceIdentity?> loadDeviceIdentity() async => _deviceIdentity;

  @override
  Future<void> saveDeviceIdentity(LocalDeviceIdentity identity) async {
    _deviceIdentity = identity;
  }

  @override
  Future<String?> loadDeviceToken({
    required String deviceId,
    required String role,
  }) async =>
      null;

  @override
  Future<void> saveDeviceToken({
    required String deviceId,
    required String role,
    required String token,
  }) async {}

  @override
  Future<void> clearDeviceToken({
    required String deviceId,
    required String role,
  }) async {}

  @override
  Future<String?> loadGatewayToken({int? profileIndex}) async => null;

  @override
  Future<void> saveGatewayToken(String value, {int? profileIndex}) async {}

  @override
  Future<void> clearGatewayToken({int? profileIndex}) async {}

  @override
  Future<String?> loadGatewayPassword({int? profileIndex}) async => null;

  @override
  Future<void> saveGatewayPassword(String value, {int? profileIndex}) async {}

  @override
  Future<void> clearGatewayPassword({int? profileIndex}) async {}

  @override
  Future<String?> loadOllamaCloudApiKey() async => null;

  @override
  Future<void> saveOllamaCloudApiKey(String value) async {}

  @override
  Future<String?> loadVaultToken() async => null;

  @override
  Future<void> saveVaultToken(String value) async {}

  @override
  Future<String?> loadAiGatewayApiKey() async =>
      _getSecretValue('ai_gateway_api_key');

  @override
  Future<void> saveAiGatewayApiKey(String value) async {
    _setSecretValue('ai_gateway_api_key', value);
  }

  @override
  Future<void> clearAiGatewayApiKey() async {
    _clearSecretValue('ai_gateway_api_key');
  }

  @override
  Future<String?> loadAccountSessionToken() async => null;

  @override
  Future<void> saveAccountSessionToken(String value) async {}

  @override
  Future<void> clearAccountSessionToken() async {}

  @override
  Future<int> loadAccountSessionExpiresAtMs() async => 0;

  @override
  Future<void> saveAccountSessionExpiresAtMs(int value) async {}

  @override
  Future<void> clearAccountSessionExpiresAtMs() async {}

  @override
  Future<String?> loadAccountSessionUserId() async => null;

  @override
  Future<void> saveAccountSessionUserId(String value) async {}

  @override
  Future<void> clearAccountSessionUserId() async {}

  @override
  Future<String?> loadAccountSessionIdentifier() async => null;

  @override
  Future<void> saveAccountSessionIdentifier(String value) async {}

  @override
  Future<void> clearAccountSessionIdentifier() async {}

  @override
  Future<AccountSessionSummary?> loadAccountSessionSummary() async => null;

  @override
  Future<void> saveAccountSessionSummary(AccountSessionSummary value) async {}

  @override
  Future<void> clearAccountSessionSummary() async {}

  @override
  Future<String?> loadSecretValueByRef(String refName) async =>
      _getSecretValue(refName);

  @override
  Future<void> saveSecretValueByRef(String refName, String value) async {
    _setSecretValue(refName, value);
  }

  @override
  Future<void> clearSecretValueByRef(String refName) async {
    _clearSecretValue(refName);
  }

  @override
  void dispose() {}

  @override
  PersistentWriteFailures get persistentWriteFailures =>
      const PersistentWriteFailures();

  void _setSecretValue(String refName, String value) {
    final normalizedRef = refName.trim();
    final trimmedValue = value.trim();
    if (normalizedRef.isEmpty || trimmedValue.isEmpty) {
      return;
    }
    _secretValueByRef = <String, String>{
      ..._secretValueByRef,
      normalizedRef: trimmedValue,
    };
  }

  String? _getSecretValue(String refName) {
    final normalizedRef = refName.trim();
    if (normalizedRef.isEmpty) {
      return null;
    }
    return _secretValueByRef[normalizedRef];
  }

  void _clearSecretValue(String refName) {
    final normalizedRef = refName.trim();
    if (normalizedRef.isEmpty || !_secretValueByRef.containsKey(normalizedRef)) {
      return;
    }
    _secretValueByRef = <String, String>{
      for (final entry in _secretValueByRef.entries)
        if (entry.key != normalizedRef) entry.key: entry.value,
    };
  }
}

class NoopMultiAgentMountManagerInternal extends MultiAgentMountManager {
  NoopMultiAgentMountManagerInternal() : super();

  @override
  Future<MultiAgentConfig> reconcile({
    required MultiAgentConfig config,
    required String aiGatewayUrl,
    String configuredCodexCliPath = '',
  }) async {
    return config;
  }
}

void registerAssistantPageSuiteSupportTestsInternal() {
  testWidgets(
    'AssistantPage shows Single Agent chip and keeps task rows minimal',
    (WidgetTester tester) async {
      final controller = await createTestController(tester);
      await controller.settingsController.saveAiGatewayApiKey('live-key');
      await controller.saveSettings(
        controller.settings.copyWith(
          aiGateway: controller.settings.aiGateway.copyWith(
            baseUrl: 'http://127.0.0.1:11434/v1',
            availableModels: const <String>['qwen2.5-coder:latest'],
            selectedModels: const <String>['qwen2.5-coder:latest'],
          ),
          defaultModel: 'qwen2.5-coder:latest',
          assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
        ),
        refreshAfterSave: false,
      );

      await pumpPage(
        tester,
        child: AssistantPage(controller: controller, onOpenDetail: (_) {}),
      );

      expect(
        find.byKey(const Key('assistant-connection-chip')),
        findsOneWidget,
      );
      expect(
        find.text('Auto · qwen2.5-coder:latest · 127.0.0.1:11434'),
        findsOneWidget,
      );
      expect(find.text('等待描述这个任务的第一条消息'), findsNothing);

      await tester.tap(find.byKey(const Key('assistant-new-task-button')));
      await tester.pumpAndSettle();

      expect(find.text('等待描述这个任务的第一条消息'), findsNothing);
    },
    skip: true,
  );
}

SettingsSnapshot buildAssistantPageTestSettingsSnapshotInternal(
  SettingsSnapshot defaults, {
  required String workspacePath,
  required bool disableGatewayProfileEndpoints,
  required AssistantExecutionTarget assistantExecutionTarget,
}) {
  final gatewayProfiles = disableGatewayProfileEndpoints
      ? <GatewayConnectionProfile>[
          GatewayConnectionProfile(
            mode: RuntimeConnectionMode.local,
            useSetupCode: false,
            setupCode: '',
            host: '',
            port: 0,
            tls: false,
            tokenRef: defaults.primaryLocalGatewayProfile.tokenRef,
            passwordRef: defaults.primaryLocalGatewayProfile.passwordRef,
            selectedAgentId: defaults.primaryLocalGatewayProfile.selectedAgentId,
          ),
          GatewayConnectionProfile(
            mode: RuntimeConnectionMode.remote,
            useSetupCode: false,
            setupCode: '',
            host: '',
            port: 0,
            tls: false,
            tokenRef: defaults.primaryRemoteGatewayProfile.tokenRef,
            passwordRef: defaults.primaryRemoteGatewayProfile.passwordRef,
            selectedAgentId: defaults.primaryRemoteGatewayProfile.selectedAgentId,
          ),
          ...defaults.gatewayProfiles.skip(2),
        ]
      : defaults.gatewayProfiles;
  return SettingsSnapshot(
    appLanguage: defaults.appLanguage,
    appActive: defaults.appActive,
    launchAtLogin: defaults.launchAtLogin,
    showDockIcon: defaults.showDockIcon,
    workspacePath: workspacePath,
    remoteProjectRoot: defaults.remoteProjectRoot,
    cliPath: defaults.cliPath,
    codeAgentRuntimeMode: defaults.codeAgentRuntimeMode,
    codexCliPath: defaults.codexCliPath,
    defaultModel: 'qwen2.5-coder:latest',
    defaultProvider: defaults.defaultProvider,
    gatewayProfiles: gatewayProfiles,
    externalAcpEndpoints: defaults.externalAcpEndpoints,
    authorizedSkillDirectories: defaults.authorizedSkillDirectories,
    ollamaLocal: defaults.ollamaLocal.copyWith(
      endpoint: 'http://127.0.0.1:11434',
      defaultModel: 'qwen2.5-coder:latest',
      autoDiscover: true,
    ),
    ollamaCloud: defaults.ollamaCloud,
    vault: defaults.vault,
    aiGateway: defaults.aiGateway.copyWith(
      baseUrl: 'http://127.0.0.1:11434/v1',
      availableModels: const <String>['qwen2.5-coder:latest'],
      selectedModels: const <String>['qwen2.5-coder:latest'],
    ),
    webSessionPersistence: defaults.webSessionPersistence,
    multiAgent: defaults.multiAgent.copyWith(
      enabled: defaults.multiAgent.enabled,
    ),
    experimentalCanvas: defaults.experimentalCanvas,
    experimentalBridge: defaults.experimentalBridge,
    experimentalDebug: defaults.experimentalDebug,
    accountBaseUrl: defaults.accountBaseUrl,
    accountUsername: defaults.accountUsername,
    accountWorkspace: defaults.accountWorkspace,
    accountWorkspaceFollowed: defaults.accountWorkspaceFollowed,
    accountLocalMode: defaults.accountLocalMode,
    acpBridgeServerModeConfig: defaults.acpBridgeServerModeConfig,
    linuxDesktop: defaults.linuxDesktop,
    assistantExecutionTarget: assistantExecutionTarget,
    assistantPermissionLevel: defaults.assistantPermissionLevel,
    assistantNavigationDestinations: defaults.assistantNavigationDestinations,
    assistantCustomTaskTitles: defaults.assistantCustomTaskTitles,
    assistantArchivedTaskKeys: defaults.assistantArchivedTaskKeys,
    savedGatewayTargets: defaults.savedGatewayTargets,
    assistantLastSessionKey: defaults.assistantLastSessionKey,
  );
}

Future<AppController> createControllerWithThreadRecordsInternal({
  WidgetTester? tester,
  required List<TaskThread> records,
  bool useFakeGatewayRuntime = false,
  AssistantExecutionTarget assistantExecutionTargetOverride =
      AssistantExecutionTarget.singleAgent,
  List<SingleAgentProvider>? availableSingleAgentProvidersOverride,
  GoTaskServiceClient? goTaskServiceClient,
  MultiAgentMountManager? multiAgentMountManager,
  List<String>? singleAgentSharedSkillScanRootOverrides,
  bool disableGatewayProfileEndpoints = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final tempDirectory = Directory.systemTemp.createTempSync(
    'xworkmate-assistant-page-tests-',
  );
  final settingsSnapshot = buildAssistantPageTestSettingsSnapshotInternal(
    SettingsSnapshot.defaults(),
    workspacePath: tempDirectory.path,
    disableGatewayProfileEndpoints: disableGatewayProfileEndpoints,
    assistantExecutionTarget: assistantExecutionTargetOverride,
  );
  final store = AssistantPageMemorySecureConfigStoreInternal(
    initialSettingsSnapshot: settingsSnapshot,
    initialTaskThreads: records,
  );
  addTearDown(() async {
    if (await tempDirectory.exists()) {
      try {
        await tempDirectory.delete(recursive: true);
      } catch (_) {}
    }
  });
  final controller = AppController(
    store: store,
    runtimeCoordinator: useFakeGatewayRuntime
        ? RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          )
        : null,
    availableSingleAgentProvidersOverride:
        availableSingleAgentProvidersOverride,
    goTaskServiceClient: goTaskServiceClient,
    multiAgentMountManager: multiAgentMountManager,
    singleAgentSharedSkillScanRootOverrides:
        singleAgentSharedSkillScanRootOverrides,
  );
  addTearDown(controller.dispose);
  final stopwatch = Stopwatch()..start();
  while (controller.initializing) {
    if (stopwatch.elapsed > const Duration(seconds: 10)) {
      fail('controller did not finish initializing before timeout');
    }
    if (tester != null) {
      await tester.pump(const Duration(milliseconds: 20));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
  return controller;
}

Future<void> writeSkillInternal(
  Directory root,
  String folderName, {
  required String skillName,
  required String description,
}) async {
  final directory = Directory('${root.path}/$folderName');
  await directory.create(recursive: true);
  await File(
    '${directory.path}/SKILL.md',
  ).writeAsString('---\nname: $skillName\ndescription: $description\n---\n');
}

Future<void> pumpForUiSyncInternal(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> waitForConditionInternal(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class PendingSendAppControllerInternal extends AppController {
  PendingSendAppControllerInternal({
    required SecureConfigStore store,
    required this.sendGate,
    super.singleAgentSharedSkillScanRootOverrides,
  }) : super(
         store: store,
         runtimeCoordinator: RuntimeCoordinator(
           gateway: FakeGatewayRuntimeInternal(store: store),
           codex: FakeCodexRuntimeInternal(),
         ),
       );

  final Completer<void> sendGate;
  int sendCallCount = 0;
  String lastSentMessage = '';

  @override
  Future<void> sendChatMessage(
    String message, {
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<CollaborationAttachment> localAttachments =
        const <CollaborationAttachment>[],
    List<String> selectedSkillLabels = const <String>[],
  }) async {
    sendCallCount += 1;
    lastSentMessage = message;
    await sendGate.future;
  }
}

class InstalledSkillE2ECaseInternal {
  const InstalledSkillE2ECaseInternal({
    required this.skillKey,
    required this.prompt,
    required this.outputRelativePath,
    required this.outputContent,
  });

  final String skillKey;
  final String prompt;
  final String outputRelativePath;
  final String outputContent;
}

const List<InstalledSkillE2ECaseInternal>
installedSkillE2ECasesInternal = <InstalledSkillE2ECaseInternal>[
  InstalledSkillE2ECaseInternal(
    skillKey: 'pptx',
    prompt: 'Create a concise slide outline for the quarterly review.',
    outputRelativePath: 'artifacts/pptx/result.md',
    outputContent: '# pptx\n\nCaptured slide outline for the quarterly review.',
  ),
  InstalledSkillE2ECaseInternal(
    skillKey: 'docx',
    prompt: 'Draft a short policy note with headings and bullets.',
    outputRelativePath: 'artifacts/docx/result.md',
    outputContent: '# docx\n\nCaptured policy note with headings and bullets.',
  ),
  InstalledSkillE2ECaseInternal(
    skillKey: 'xlsx',
    prompt: 'Prepare a tiny table with one formula and one formatted cell.',
    outputRelativePath: 'artifacts/xlsx/result.md',
    outputContent: '# xlsx\n\nCaptured spreadsheet result with formula notes.',
  ),
  InstalledSkillE2ECaseInternal(
    skillKey: 'pdf',
    prompt: 'Summarize a reference PDF and keep the output deterministic.',
    outputRelativePath: 'artifacts/pdf/result.md',
    outputContent: '# pdf\n\nCaptured PDF summary output.',
  ),
];

const List<String> installedSkillE2EDeferredCoverageInternal = <String>[
  'image-cog',
  'wan-image-video-generation-editting',
  'video-translator',
  'image-resizer',
];

class InstalledSkillE2EAppControllerInternal
    extends PendingSendAppControllerInternal {
  InstalledSkillE2EAppControllerInternal({
    required super.store,
    required super.sendGate,
    required this.outputRelativePath,
    required this.outputContent,
    required this.importedSkill,
    super.singleAgentSharedSkillScanRootOverrides,
    this.sessionKey = 'installed-skill-session',
  });

  final String outputRelativePath;
  final String outputContent;
  final AssistantThreadSkillEntry importedSkill;
  final String sessionKey;
  String lastPromptInternal = '';
  List<String> lastSelectedSkillLabelsInternal = const <String>[];
  String lastWorkspacePathInternal = '';

  @override
  Future<void> sendChatMessage(
    String message, {
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<CollaborationAttachment> localAttachments =
        const <CollaborationAttachment>[],
    List<String> selectedSkillLabels = const <String>[],
  }) async {
    lastPromptInternal = message;
    lastSelectedSkillLabelsInternal = List<String>.unmodifiable(
      selectedSkillLabels,
    );
    lastWorkspacePathInternal = assistantWorkspacePathForSession(
      sessionKey,
    );
    final workspacePath = lastWorkspacePathInternal.trim();
    if (workspacePath.isNotEmpty) {
      final outputFile = File('$workspacePath/$outputRelativePath');
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsString(outputContent, flush: true);
    }
    await super.sendChatMessage(
      message,
      thinking: thinking,
      attachments: attachments,
      localAttachments: localAttachments,
      selectedSkillLabels: selectedSkillLabels,
    );
  }

  @override
  String get currentSessionKey => sessionKey;
}

Future<InstalledSkillE2EAppControllerInternal>
createInstalledSkillE2EControllerInternal(
  WidgetTester tester, {
  required Directory tempDirectory,
  required Directory skillsRoot,
  required Directory workspaceRoot,
  required InstalledSkillE2ECaseInternal testCase,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = AssistantPageMemorySecureConfigStoreInternal(
    initialSettingsSnapshot: singleAgentTestSettingsInternal(
      workspacePath: workspaceRoot.path,
    ).copyWith(
      assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
      multiAgent: MultiAgentConfig.defaults().copyWith(enabled: false),
    ),
  );

  final controller = InstalledSkillE2EAppControllerInternal(
    store: store,
    sendGate: Completer<void>(),
    outputRelativePath: testCase.outputRelativePath,
    outputContent: testCase.outputContent,
    importedSkill: AssistantThreadSkillEntry(
      key: testCase.skillKey,
      label: testCase.skillKey,
      description: 'Installed skill under test',
      sourcePath: '${skillsRoot.path}/${testCase.skillKey}',
      sourceLabel: testCase.skillKey,
    ),
    singleAgentSharedSkillScanRootOverrides: <String>[skillsRoot.path],
  );
  addTearDown(controller.dispose);
  await tester.pump(const Duration(milliseconds: 100));
  final stopwatch = Stopwatch()..start();
  while (controller.initializing) {
    if (stopwatch.elapsed > const Duration(seconds: 10)) {
      fail('controller did not finish initializing before timeout');
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  controller.upsertTaskThreadInternal(
    controller.currentSessionKey,
    importedSkills: <AssistantThreadSkillEntry>[controller.importedSkill],
    selectedSkillKeys: <String>[controller.importedSkill.key],
  );
  return controller;
}

Future<InstalledSkillE2EAppControllerInternal>
createInstalledSkillE2EControllerSimpleInternal({
  required Directory tempDirectory,
  required Directory skillsRoot,
  required Directory workspaceRoot,
  required InstalledSkillE2ECaseInternal testCase,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final store = AssistantPageMemorySecureConfigStoreInternal(
    initialSettingsSnapshot: singleAgentTestSettingsInternal(
      workspacePath: workspaceRoot.path,
    ).copyWith(
      assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
      multiAgent: MultiAgentConfig.defaults().copyWith(enabled: false),
    ),
  );

  final controller = InstalledSkillE2EAppControllerInternal(
    store: store,
    sendGate: Completer<void>(),
    outputRelativePath: testCase.outputRelativePath,
    outputContent: testCase.outputContent,
    importedSkill: AssistantThreadSkillEntry(
      key: testCase.skillKey,
      label: testCase.skillKey,
      description: 'Installed skill under test',
      sourcePath: '${skillsRoot.path}/${testCase.skillKey}',
      sourceLabel: testCase.skillKey,
    ),
    singleAgentSharedSkillScanRootOverrides: <String>[skillsRoot.path],
  );
  addTearDown(controller.dispose);
  await waitForConditionInternal(() => !controller.initializing);
  return controller;
}

class CaptureSendAppControllerInternal extends AppController {
  CaptureSendAppControllerInternal({
    required SecureConfigStore store,
    super.runtimeCoordinator,
  }) : super(store: store);

  int sendCallCount = 0;
  String lastSentMessage = '';
  String lastSessionKey = '';
  String lastWorkspaceRef = '';

  @override
  Future<void> sendChatMessage(
    String message, {
    String thinking = 'off',
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    List<CollaborationAttachment> localAttachments =
        const <CollaborationAttachment>[],
    List<String> selectedSkillLabels = const <String>[],
  }) async {
    sendCallCount += 1;
    lastSentMessage = message;
    lastSessionKey = currentSessionKey;
    lastWorkspaceRef = assistantWorkspacePathForSession(currentSessionKey);
  }
}

class FakeGatewayRuntimeInternal extends GatewayRuntime {
  FakeGatewayRuntimeInternal({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

  GatewayConnectionSnapshot fakeSnapshotInternal =
      GatewayConnectionSnapshot.initial();

  @override
  bool get isConnected =>
      fakeSnapshotInternal.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => fakeSnapshotInternal;

  @override
  Stream<GatewayPushEvent> get events => const Stream<GatewayPushEvent>.empty();

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    fakeSnapshotInternal = GatewayConnectionSnapshot.initial(mode: profile.mode)
        .copyWith(
          status: RuntimeConnectionStatus.connected,
          statusText: 'Connected',
          remoteAddress: '${profile.host}:${profile.port}',
          connectAuthMode: 'none',
        );
    notifyListeners();
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    fakeSnapshotInternal = fakeSnapshotInternal.copyWith(
      status: RuntimeConnectionStatus.offline,
      statusText: 'Offline',
      remoteAddress: null,
      clearLastError: true,
      clearLastErrorCode: true,
      clearLastErrorDetailCode: true,
    );
    notifyListeners();
  }

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    switch (method) {
      case 'health':
      case 'status':
        return <String, dynamic>{'ok': true};
      case 'agents.list':
        return <String, dynamic>{'agents': const <Object>[], 'mainKey': 'main'};
      case 'sessions.list':
        return <String, dynamic>{'sessions': const <Object>[]};
      case 'chat.history':
        return <String, dynamic>{'messages': const <Object>[]};
      case 'skills.status':
        return <String, dynamic>{'skills': const <Object>[]};
      case 'channels.status':
        return <String, dynamic>{
          'channelMeta': const <Object>[],
          'channelLabels': const <String, dynamic>{},
          'channelDetailLabels': const <String, dynamic>{},
          'channelAccounts': const <String, dynamic>{},
          'channelOrder': const <Object>[],
        };
      case 'models.list':
        return <String, dynamic>{'models': const <Object>[]};
      case 'cron.list':
        return <String, dynamic>{'jobs': const <Object>[]};
      case 'device.pair.list':
        return <String, dynamic>{
          'pending': const <Object>[],
          'paired': const <Object>[],
        };
      case 'system-presence':
        return const <Object>[];
      default:
        return <String, dynamic>{};
    }
  }
}

class FakeCodexRuntimeInternal extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}
