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

Future<AppController> createControllerWithThreadRecordsInternal({
  WidgetTester? tester,
  required List<TaskThread> records,
  bool useFakeGatewayRuntime = false,
  List<String>? singleAgentSharedSkillScanRootOverrides,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final tempDirectory = await Directory.systemTemp.createTemp(
    'xworkmate-assistant-page-tests-',
  );
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '${tempDirectory.path}/settings.db',
    fallbackDirectoryPathResolver: () async => tempDirectory.path,
    defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
  );
  addTearDown(() async {
    if (await tempDirectory.exists()) {
      try {
        await tempDirectory.delete(recursive: true);
      } catch (_) {}
    }
  });
  final defaults = SettingsSnapshot.defaults();
  await store.saveSettingsSnapshot(
    defaults.copyWith(
      gatewayProfiles: replaceGatewayProfileAt(
        replaceGatewayProfileAt(
          defaults.gatewayProfiles,
          kGatewayLocalProfileIndex,
          defaults.primaryLocalGatewayProfile.copyWith(
            host: '127.0.0.1',
            port: 9,
            tls: false,
          ),
        ),
        kGatewayRemoteProfileIndex,
        defaults.primaryRemoteGatewayProfile.copyWith(
          host: '127.0.0.1',
          port: 9,
          tls: false,
        ),
      ),
      aiGateway: defaults.aiGateway.copyWith(
        baseUrl: 'http://127.0.0.1:11434/v1',
        availableModels: const <String>['qwen2.5-coder:latest'],
        selectedModels: const <String>['qwen2.5-coder:latest'],
      ),
      assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
      defaultModel: 'qwen2.5-coder:latest',
      workspacePath: tempDirectory.path,
    ),
  );
  await store.saveTaskThreads(records);
  final controller = AppController(
    store: store,
    runtimeCoordinator: useFakeGatewayRuntime
        ? RuntimeCoordinator(
            gateway: FakeGatewayRuntimeInternal(store: store),
            codex: FakeCodexRuntimeInternal(),
          )
        : null,
    singleAgentSharedSkillScanRootOverrides:
        singleAgentSharedSkillScanRootOverrides,
  );
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
    List<String>? singleAgentSharedSkillScanRootOverrides,
  }) : super(
         store: store,
         runtimeCoordinator: RuntimeCoordinator(
           gateway: FakeGatewayRuntimeInternal(store: store),
           codex: FakeCodexRuntimeInternal(),
         ),
         singleAgentSharedSkillScanRootOverrides:
             singleAgentSharedSkillScanRootOverrides,
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
  print('installed-skill ${testCase.skillKey}: helper creating store');
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '${tempDirectory.path}/settings.db',
    fallbackDirectoryPathResolver: () async => tempDirectory.path,
    defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
  );
  await store.initialize();
  await store.saveSettingsSnapshot(
    singleAgentTestSettingsInternal(workspacePath: workspaceRoot.path).copyWith(
      assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
      multiAgent: MultiAgentConfig.defaults().copyWith(enabled: false),
    ),
  );
  print('installed-skill ${testCase.skillKey}: helper creating controller');

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
  print('installed-skill ${testCase.skillKey}: helper controller created');
  addTearDown(controller.dispose);
  print('installed-skill ${testCase.skillKey}: helper pumping once');
  await tester.pump(const Duration(milliseconds: 100));
  print('installed-skill ${testCase.skillKey}: helper pumped once');
  final stopwatch = Stopwatch()..start();
  while (controller.initializing) {
    print(
      'installed-skill ${testCase.skillKey}: helper waiting ${stopwatch.elapsedMilliseconds}ms',
    );
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
  print('installed-skill ${testCase.skillKey}: helper initialized');
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
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '${tempDirectory.path}/settings.db',
    fallbackDirectoryPathResolver: () async => tempDirectory.path,
    defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
  );
  await store.initialize();
  await store.saveSettingsSnapshot(
    singleAgentTestSettingsInternal(workspacePath: workspaceRoot.path).copyWith(
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
