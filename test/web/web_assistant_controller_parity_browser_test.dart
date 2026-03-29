@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xworkmate/app/app_controller_web.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/web/web_acp_client.dart';
import 'package:xworkmate/web/web_relay_gateway_client.dart';
import 'package:xworkmate/web/web_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'thread-scoped assistant context persists across reload on web',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final fakeRelay = _FakeRelayGatewayClient(WebStore());
      final fakeAcp = _FakeAcpClient();
      final controller = AppController(
        store: WebStore(),
        relayClient: fakeRelay,
        acpClient: fakeAcp,
      );
      await _waitForReady(controller);

      await controller.saveRelayConfiguration(
        profileIndex: kGatewayLocalProfileIndex,
        host: '',
        port: 18789,
        tls: false,
        token: '',
        password: '',
      );
      await controller.saveRelayConfiguration(
        profileIndex: kGatewayRemoteProfileIndex,
        host: '',
        port: 443,
        tls: true,
        token: '',
        password: '',
      );

      final threadSingle = controller.currentSessionKey;
      await controller.setSingleAgentProvider(SingleAgentProvider.opencode);
      await controller.setAssistantMessageViewMode(
        AssistantMessageViewMode.raw,
      );
      await controller.selectAssistantModelForSession(
        threadSingle,
        'single-model',
      );
      await controller.saveAssistantTaskTitle(threadSingle, 'Thread Single');

      await controller.createConversation(
        target: AssistantExecutionTarget.local,
      );
      final threadLocal = controller.currentSessionKey;
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.local,
      );
      await controller.selectAssistantModelForSession(
        threadLocal,
        'local-model',
      );
      await controller.saveAssistantTaskTitle(threadLocal, 'Thread Local');

      await controller.createConversation(
        target: AssistantExecutionTarget.remote,
      );
      final threadRemote = controller.currentSessionKey;
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.remote,
      );
      await controller.setAssistantMessageViewMode(
        AssistantMessageViewMode.raw,
      );
      await controller.selectAssistantModelForSession(
        threadRemote,
        'remote-model',
      );
      await controller.saveAssistantTaskTitle(threadRemote, 'Thread Remote');
      await controller.saveAssistantTaskArchived(threadRemote, true);

      expect(
        controller.assistantExecutionTargetForSession(threadSingle),
        AssistantExecutionTarget.singleAgent,
      );
      expect(
        controller.assistantWorkspacePathForSession(threadSingle),
        controller.threadRecordsInternal[threadSingle]!.workspacePath,
      );
      expect(
        controller.assistantWorkspaceKindForSession(threadSingle),
        WorkspaceRefKind.remotePath,
      );
      expect(
        controller.singleAgentProviderForSession(threadSingle),
        SingleAgentProvider.opencode,
      );
      expect(
        controller.assistantMessageViewModeForSession(threadSingle),
        AssistantMessageViewMode.raw,
      );
      expect(controller.assistantModelForSession(threadSingle), 'single-model');

      expect(controller.assistantModelForSession(threadLocal), 'local-model');
      expect(
        controller.assistantWorkspacePathForSession(threadLocal),
        controller.threadRecordsInternal[threadLocal]!.workspacePath,
      );
      expect(
        controller.assistantWorkspaceKindForSession(threadLocal),
        WorkspaceRefKind.remotePath,
      );

      expect(controller.isAssistantTaskArchived(threadRemote), isTrue);
      expect(
        controller.conversations.where(
          (item) => item.sessionKey == threadRemote,
        ),
        isEmpty,
      );

      controller.dispose();

      final reloaded = AppController(
        store: WebStore(),
        relayClient: _FakeRelayGatewayClient(WebStore()),
        acpClient: fakeAcp,
      );
      await _waitForReady(reloaded);

      expect(
        reloaded.assistantExecutionTargetForSession(threadSingle),
        AssistantExecutionTarget.singleAgent,
      );
      expect(
        reloaded.assistantWorkspacePathForSession(threadSingle),
        reloaded.threadRecordsInternal[threadSingle]!.workspacePath,
      );
      expect(
        reloaded.assistantWorkspaceKindForSession(threadSingle),
        WorkspaceRefKind.remotePath,
      );
      expect(
        reloaded.singleAgentProviderForSession(threadSingle),
        SingleAgentProvider.opencode,
      );
      expect(
        reloaded.assistantMessageViewModeForSession(threadSingle),
        AssistantMessageViewMode.raw,
      );
      expect(reloaded.assistantModelForSession(threadSingle), 'single-model');
      expect(reloaded.assistantModelForSession(threadLocal), 'local-model');
      expect(
        reloaded.assistantWorkspacePathForSession(threadRemote),
        reloaded.threadRecordsInternal[threadRemote]!.workspacePath,
      );
      expect(
        reloaded.assistantWorkspaceKindForSession(threadRemote),
        WorkspaceRefKind.remotePath,
      );
      expect(reloaded.isAssistantTaskArchived(threadRemote), isTrue);

      reloaded.dispose();
    },
  );

  test(
    'gateway Save does not connect but Apply connects current target profile',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final fakeRelay = _FakeRelayGatewayClient(WebStore());
      final controller = AppController(
        store: WebStore(),
        relayClient: fakeRelay,
        acpClient: _FakeAcpClient(),
      );
      await _waitForReady(controller);

      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.remote,
      );
      fakeRelay.connectCalls = 0;

      await controller.saveRelayConfiguration(
        profileIndex: kGatewayRemoteProfileIndex,
        host: 'remote.example.com',
        port: 443,
        tls: true,
        token: 'remote-token',
        password: '',
      );
      expect(fakeRelay.connectCalls, 0);

      await controller.applyRelayConfiguration(
        profileIndex: kGatewayRemoteProfileIndex,
        host: 'remote.example.com',
        port: 443,
        tls: true,
        token: 'remote-token',
        password: '',
      );

      expect(fakeRelay.connectCalls, greaterThanOrEqualTo(1));
      expect(fakeRelay.lastConnectMode, RuntimeConnectionMode.remote);

      controller.dispose();
    },
  );

  test(
    'single-agent skills refresh per provider while relay modes keep relay skills',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final fakeRelay = _FakeRelayGatewayClient(WebStore())
        ..skills = <Map<String, dynamic>>[
          <String, dynamic>{
            'skillKey': 'relay-skill',
            'name': 'Relay Skill',
            'description': 'Relay-owned skill',
            'source': 'gateway',
          },
        ];
      final fakeAcp = _FakeAcpClient(
        skillCatalog: <String, List<Map<String, dynamic>>>{
          'opencode': <Map<String, dynamic>>[
            <String, dynamic>{
              'skillKey': 'codex-skill',
              'name': 'OpenCode Skill',
              'description': 'OpenCode-owned skill',
              'source': 'opencode',
            },
          ],
          'claude': <Map<String, dynamic>>[
            <String, dynamic>{
              'skillKey': 'claude-skill',
              'name': 'Claude Skill',
              'description': 'Claude-owned skill',
              'source': 'claude',
            },
          ],
        },
      );
      final controller = AppController(
        store: WebStore(),
        relayClient: fakeRelay,
        acpClient: fakeAcp,
      );
      await _waitForReady(controller);
      addTearDown(controller.dispose);

      await controller.saveRelayConfiguration(
        profileIndex: kGatewayRemoteProfileIndex,
        host: 'remote.example.com',
        port: 443,
        tls: true,
        token: '',
        password: '',
      );
      await controller.saveSettingsDraft(
        controller.settingsDraft.copyWith(
          externalAcpEndpoints: normalizeExternalAcpEndpoints(
            profiles: <ExternalAcpEndpointProfile>[
              ...controller.settingsDraft.externalAcpEndpoints,
              const ExternalAcpEndpointProfile(
                providerKey: 'claude',
                label: 'Claude',
                badge: 'Cl',
                endpoint: 'wss://claude.example.com/acp',
                enabled: true,
              ),
            ],
          ),
        ),
      );
      await controller.applySettingsDraft();

      final claudeProvider = controller.singleAgentProviderOptions.singleWhere(
        (item) => item.label == 'Claude',
      );
      fakeAcp._skillCatalog[claudeProvider.providerId] = <Map<String, dynamic>>[
        <String, dynamic>{
          'skillKey': 'claude-skill',
          'name': 'Claude Skill',
          'description': 'Claude-owned skill',
          'source': 'claude',
        },
      ];

      await controller.setSingleAgentProvider(SingleAgentProvider.opencode);
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((item) => item.label),
        contains('OpenCode Skill'),
      );
      await controller.toggleAssistantSkillForSession(
        controller.currentSessionKey,
        'codex-skill',
      );
      expect(
        controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        ),
        hasLength(1),
      );

      await controller.setSingleAgentProvider(claudeProvider);
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((item) => item.label),
        contains('Claude Skill'),
      );
      expect(
        controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );

      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.remote,
      );
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((item) => item.label),
        contains('Relay Skill'),
      );
    },
  );

  test(
    'single-agent clears stale skills when ACP skills.status is unsupported',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final fakeAcp = _FakeAcpClient(
        skillCatalog: <String, List<Map<String, dynamic>>>{
          'opencode': <Map<String, dynamic>>[
            <String, dynamic>{
              'skillKey': 'codex-skill',
              'name': 'OpenCode Skill',
              'description': 'OpenCode-owned skill',
              'source': 'opencode',
            },
          ],
        },
      );
      final controller = AppController(
        store: WebStore(),
        relayClient: _FakeRelayGatewayClient(WebStore()),
        acpClient: fakeAcp,
      );
      await _waitForReady(controller);
      addTearDown(controller.dispose);

      await controller.saveRelayConfiguration(
        profileIndex: kGatewayRemoteProfileIndex,
        host: 'remote.example.com',
        port: 443,
        tls: true,
        token: '',
        password: '',
      );
      await controller.setSingleAgentProvider(SingleAgentProvider.opencode);
      await controller.toggleAssistantSkillForSession(
        controller.currentSessionKey,
        'codex-skill',
      );
      expect(
        controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        ),
        isNotEmpty,
      );
      expect(
        controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        ),
        hasLength(1),
      );

      fakeAcp.supportsSkillStatus = false;
      await controller.skillsController.refresh();

      expect(
        controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );
      expect(
        controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );
    },
  );
}

class _FakeRelayGatewayClient extends WebRelayGatewayClient {
  _FakeRelayGatewayClient(
    super.store, {
    GatewayConnectionSnapshot? initialSnapshot,
  }) : _snapshot =
           initialSnapshot ??
           GatewayConnectionSnapshot.initial(
             mode: RuntimeConnectionMode.remote,
           );

  final StreamController<GatewayPushEvent> _eventsController =
      StreamController<GatewayPushEvent>.broadcast();
  GatewayConnectionSnapshot _snapshot;

  int connectCalls = 0;
  RuntimeConnectionMode? lastConnectMode;
  List<Map<String, dynamic>> skills = <Map<String, dynamic>>[];

  @override
  Stream<GatewayPushEvent> get events => _eventsController.stream;

  @override
  GatewayConnectionSnapshot get snapshot => _snapshot;

  @override
  Future<void> connect({
    required GatewayConnectionProfile profile,
    required String authToken,
    required String authPassword,
  }) async {
    connectCalls += 1;
    lastConnectMode = profile.mode;
    _snapshot = GatewayConnectionSnapshot.initial(mode: profile.mode).copyWith(
      status: RuntimeConnectionStatus.connected,
      statusText: 'Connected',
      remoteAddress: '${profile.host}:${profile.port}',
    );
  }

  @override
  Future<void> disconnect() async {
    _snapshot = _snapshot.copyWith(
      status: RuntimeConnectionStatus.offline,
      statusText: 'Offline',
      clearRemoteAddress: true,
    );
  }

  @override
  Future<List<GatewaySessionSummary>> listSessions({int limit = 50}) async {
    return const <GatewaySessionSummary>[];
  }

  @override
  Future<List<GatewayChatMessage>> loadHistory(
    String sessionKey, {
    int limit = 120,
  }) async {
    return const <GatewayChatMessage>[];
  }

  @override
  Future<String> sendChat({
    required String sessionKey,
    required String message,
    required String thinking,
    List<GatewayChatAttachmentPayload> attachments =
        const <GatewayChatAttachmentPayload>[],
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    return 'fake-run';
  }

  @override
  Future<List<GatewayModelSummary>> listModels() async {
    return const <GatewayModelSummary>[];
  }

  @override
  Future<dynamic> request(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (method == 'skills.status') {
      return <String, dynamic>{'skills': skills};
    }
    return const <String, dynamic>{};
  }

  @override
  Future<void> dispose() async {
    await _eventsController.close();
  }
}

class _FakeAcpClient extends WebAcpClient {
  _FakeAcpClient({Map<String, List<Map<String, dynamic>>>? skillCatalog})
    : _skillCatalog = skillCatalog ?? <String, List<Map<String, dynamic>>>{};

  bool supportsSkillStatus = true;
  final Map<String, List<Map<String, dynamic>>> _skillCatalog;

  @override
  Future<WebAcpCapabilities> loadCapabilities({required Uri endpoint}) async {
    return WebAcpCapabilities(
      singleAgent: true,
      multiAgent: true,
      providers: <SingleAgentProvider>{
        SingleAgentProvider.opencode,
        SingleAgentProvider.claude,
        SingleAgentProvider.gemini,
      },
      raw: <String, dynamic>{},
    );
  }

  @override
  Future<void> cancelSession({
    required Uri endpoint,
    required String sessionId,
    required String threadId,
  }) async {}

  @override
  Future<Map<String, dynamic>> request({
    required Uri endpoint,
    required String method,
    required Map<String, dynamic> params,
    void Function(Map<String, dynamic> notification)? onNotification,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (method == 'skills.status') {
      if (!supportsSkillStatus) {
        throw const WebAcpException(
          'unknown method: skills.status',
          code: '-32601',
        );
      }
      final provider =
          params['provider']?.toString().trim().toLowerCase() ?? 'auto';
      final skills =
          _skillCatalog[provider] ??
          _skillCatalog['auto'] ??
          const <Map<String, dynamic>>[];
      return <String, dynamic>{
        'result': <String, dynamic>{'skills': skills},
      };
    }
    return <String, dynamic>{
      'result': <String, dynamic>{
        'output': 'ok',
        'summary': 'ok',
        'model': params['model']?.toString() ?? 'fake-model',
      },
    };
  }
}

Future<void> _waitForReady(
  AppController controller, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (controller.initializing) {
    if (DateTime.now().isAfter(deadline)) {
      fail('controller did not initialize before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
