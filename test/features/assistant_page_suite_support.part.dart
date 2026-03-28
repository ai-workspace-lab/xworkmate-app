part of 'assistant_page_suite.dart';

void _registerAssistantPageSuiteSupportTests() {
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

Future<AppController> _createControllerWithThreadRecords({
  WidgetTester? tester,
  required List<AssistantThreadRecord> records,
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
  await store.saveAssistantThreadRecords(records);
  final controller = AppController(
    store: store,
    runtimeCoordinator: useFakeGatewayRuntime
        ? RuntimeCoordinator(
            gateway: _FakeGatewayRuntime(store: store),
            codex: _FakeCodexRuntime(),
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

Future<void> _writeSkill(
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

Future<void> _pumpForUiSync(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _waitForCondition(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _PendingSendAppController extends AppController {
  _PendingSendAppController({
    required SecureConfigStore store,
    required this.sendGate,
  }) : super(
         store: store,
         runtimeCoordinator: RuntimeCoordinator(
           gateway: _FakeGatewayRuntime(store: store),
           codex: _FakeCodexRuntime(),
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

class _FakeGatewayRuntime extends GatewayRuntime {
  _FakeGatewayRuntime({required super.store})
    : super(identityStore: DeviceIdentityStore(store));

  GatewayConnectionSnapshot _snapshot = GatewayConnectionSnapshot.initial();

  @override
  bool get isConnected => _snapshot.status == RuntimeConnectionStatus.connected;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Stream<GatewayPushEvent> get events => const Stream<GatewayPushEvent>.empty();

  @override
  Future<void> connectProfile(
    GatewayConnectionProfile profile, {
    int? profileIndex,
    String authTokenOverride = '',
    String authPasswordOverride = '',
  }) async {
    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connected,
      statusText: 'Connected',
      remoteAddress: '${profile.host}:${profile.port}',
      connectAuthMode: 'none',
    );
    notifyListeners();
  }

  @override
  Future<void> disconnect({bool clearDesiredProfile = true}) async {
    _snapshot = _snapshot.copyWith(
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

class _FakeCodexRuntime extends CodexRuntime {
  @override
  Future<String?> findCodexBinary() async => null;

  @override
  Future<void> stop() async {}
}
