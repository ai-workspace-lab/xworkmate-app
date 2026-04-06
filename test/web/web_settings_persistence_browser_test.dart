@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xworkmate/app/app_controller_web.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/web/web_session_repository.dart';
import 'package:xworkmate/web/web_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'web controller persists single-agent and relay configuration',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final remoteRecords = <TaskThread>[];

      final controller = AppController(
        store: WebStore(),
        remoteSessionRepositoryBuilder: (config, clientId, accessToken) =>
            MemoryRemoteSessionRepositoryInternal(remoteRecords),
      );
      await waitForReadyInternal(controller);

      await controller.saveAiGatewayConfiguration(
        name: 'Single Agent',
        baseUrl: 'https://api.example.com/v1',
        provider: 'openai-compatible',
        apiKey: 'sk-test-web',
        defaultModel: '',
      );
      await controller.saveRelayConfiguration(
        host: 'relay.example.com',
        port: 443,
        tls: true,
        token: 'relay-token',
        password: 'relay-password',
      );
      await controller.saveWebSessionPersistenceConfiguration(
        mode: WebSessionPersistenceMode.remote,
        remoteBaseUrl: 'https://xworkmate.svc.plus/api/web-sessions',
        apiToken: 'session-token',
      );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.remote,
      );
      await controller.createConversation(
        target: AssistantExecutionTarget.singleAgent,
      );

      final reloaded = AppController(
        store: WebStore(),
        remoteSessionRepositoryBuilder: (config, clientId, accessToken) =>
            MemoryRemoteSessionRepositoryInternal(remoteRecords),
      );
      await waitForReadyInternal(reloaded);

      expect(reloaded.settings.aiGateway.baseUrl, 'https://api.example.com/v1');
      expect(reloaded.settings.defaultProvider, 'openai-compatible');
      expect(
        reloaded.settings.primaryRemoteGatewayProfile.host,
        'relay.example.com',
      );
      expect(reloaded.settings.primaryRemoteGatewayProfile.port, 443);
      expect(
        reloaded.settings.webSessionPersistence.mode,
        WebSessionPersistenceMode.remote,
      );
      expect(
        reloaded.settings.webSessionPersistence.remoteBaseUrl,
        'https://xworkmate.svc.plus/api/web-sessions',
      );
      expect(
        reloaded.settings.assistantExecutionTarget,
        AssistantExecutionTarget.remote,
      );
      expect(reloaded.storedAiGatewayApiKeyMask, isNotNull);
      expect(reloaded.storedRelayTokenMask, isNotNull);
      expect(controller.storedWebSessionApiTokenMask, isNotNull);
      expect(reloaded.storedWebSessionApiTokenMask, isNull);
      expect(remoteRecords, isNotEmpty);
      expect(reloaded.conversations, isNotEmpty);

      controller.dispose();
      reloaded.dispose();
    },
  );

  test('web controller rejects insecure remote session api urls', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final controller = AppController(store: WebStore());
    await waitForReadyInternal(controller);

    await controller.saveWebSessionPersistenceConfiguration(
      mode: WebSessionPersistenceMode.remote,
      remoteBaseUrl: 'http://xworkmate.svc.plus/api/web-sessions',
      apiToken: 'session-token',
    );

    expect(controller.usesRemoteSessionPersistence, isFalse);
    expect(controller.sessionPersistenceStatusMessage, contains('HTTPS'));
    expect(
      controller.settings.webSessionPersistence.mode,
      WebSessionPersistenceMode.browser,
    );
    expect(controller.settings.webSessionPersistence.remoteBaseUrl, isEmpty);
    expect(controller.storedWebSessionApiTokenMask, isNull);

    controller.dispose();
  });

  test(
    'empty remote session api does not import stale browser cache',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = WebStore();
      final remoteRecords = <TaskThread>[];

      await store.initialize();
      await store.saveSettingsSnapshot(
        SettingsSnapshot.defaults().copyWith(
          webSessionPersistence: const WebSessionPersistenceConfig(
            mode: WebSessionPersistenceMode.remote,
            remoteBaseUrl: 'https://xworkmate.svc.plus/api/web-sessions',
          ),
        ),
      );
      await store.saveTaskThreads(<TaskThread>[
        TaskThread(
          threadId: 'direct:stale-browser-cache',
          workspaceBinding: const WorkspaceBinding(
            workspaceId: 'direct:stale-browser-cache',
            workspaceKind: WorkspaceKind.remoteFs,
            workspacePath:
                '/owners/remote/user/direct/threads/direct:stale-browser-cache',
            displayPath:
                '/owners/remote/user/direct/threads/direct:stale-browser-cache',
            writable: true,
          ),
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 1,
          title: 'stale browser cache',
          archived: false,
          executionBinding: const ExecutionBinding(
            executionMode: ThreadExecutionMode.localAgent,
            executorId: 'auto',
            providerId: 'auto',
            endpointId: '',
          ),
          messageViewMode: AssistantMessageViewMode.rendered,
        ),
      ]);

      final controller = AppController(
        store: store,
        remoteSessionRepositoryBuilder: (config, clientId, accessToken) =>
            MemoryRemoteSessionRepositoryInternal(remoteRecords),
      );
      await waitForReadyInternal(controller);

      expect(remoteRecords, isEmpty);
      expect(
        controller.sessionPersistenceStatusMessage,
        anyOf(
          contains('不会自动导入远端'),
          contains('will not be imported automatically'),
        ),
      );
      expect(
        controller.conversations.single.title,
        isNot('stale browser cache'),
      );

      controller.dispose();
    },
  );
}

class MemoryRemoteSessionRepositoryInternal implements WebSessionRepository {
  MemoryRemoteSessionRepositoryInternal(this.recordsInternal);

  final List<TaskThread> recordsInternal;

  @override
  Future<List<TaskThread>> loadThreadRecords() async {
    return List<TaskThread>.from(recordsInternal, growable: false);
  }

  @override
  Future<void> saveThreadRecords(List<TaskThread> records) async {
    recordsInternal
      ..clear()
      ..addAll(records);
  }
}

Future<void> waitForReadyInternal(
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
