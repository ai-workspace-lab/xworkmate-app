import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_core.dart';
import 'package:xworkmate/app/app_controller_desktop_qmd_sync.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_actions.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_sessions.dart';
import 'package:xworkmate/runtime/agent_context_client.dart';

class _FakeAgentContextClient implements AgentContextClient {
  _FakeAgentContextClient({
    this.catalog,
    this.threads,
    this.briefing,
    this.shouldThrow = false,
  });

  final QmdTaskCatalog? catalog;
  final QmdThreadPage? threads;
  final QmdThreadBriefing? briefing;
  final bool shouldThrow;

  int fetchCatalogCalls = 0;
  int listThreadsCalls = 0;
  int fetchBriefingCalls = 0;

  @override
  Future<QmdTaskCatalog> fetchCatalog({
    String? scope,
    int limit = 50,
    int offset = 0,
  }) async {
    fetchCatalogCalls++;
    if (shouldThrow) {
      throw const AgentContextException(
        statusCode: 503,
        code: 'UNAVAILABLE',
        message: 'Backend unavailable',
      );
    }
    return catalog ??
        const QmdTaskCatalog(
          pinnedTasks: <QmdPinnedTask>[],
          sharedProjects: <QmdSharedProject>[],
          recentThreads: <QmdContextThread>[],
        );
  }

  @override
  Future<QmdThreadPage> listThreads({
    String? scope,
    String state = 'live',
    int limit = 50,
    int offset = 0,
  }) async {
    listThreadsCalls++;
    if (shouldThrow) {
      throw const AgentContextException(
        statusCode: 503,
        code: 'UNAVAILABLE',
        message: 'Backend unavailable',
      );
    }
    return threads ??
        const QmdThreadPage(
          threads: <QmdContextThread>[],
          limit: 50,
          offset: 0,
          total: 0,
        );
  }

  @override
  Future<QmdThreadBriefing> fetchBriefing(
    String threadId, {
    int events = 20,
  }) async {
    fetchBriefingCalls++;
    if (shouldThrow) {
      throw const AgentContextException(
        statusCode: 503,
        code: 'UNAVAILABLE',
        message: 'Backend unavailable',
      );
    }
    return briefing ??
        QmdThreadBriefing(
          thread: QmdContextThread(
            id: threadId,
            scope: 'ai-workspace-lab/xworkmate-app',
            title: 'Fix bridge timeout',
            state: 'open',
          ),
          items: const <QmdBriefingItem>[
            QmdBriefingItem(
              kind: 'todo',
              key: 'todo-1',
              status: 'pending',
              text: 'Implement keep-alive heartbeat',
            ),
          ],
          contributors: const <QmdBriefingContributor>[
            QmdBriefingContributor(source: 'codex', sessions: 2),
          ],
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QMD Remote Task Integration & Sidebar Merge', () {
    test(
      'merges pinned tasks and remote threads into assistantSessions with source tags',
      () async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );

        final fakeClient = _FakeAgentContextClient(
          catalog: QmdTaskCatalog(
            pinnedTasks: <QmdPinnedTask>[
              QmdPinnedTask(
                id: 'pin-101',
                source: 'codex',
                title: 'Refactor bridge reconnect',
                scope: 'xworkmate-app',
                projectName: 'XWorkmate',
                updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
              ),
            ],
            sharedProjects: const <QmdSharedProject>[],
            recentThreads: <QmdContextThread>[
              QmdContextThread(
                id: 'thread-201',
                scope: 'ai-workspace-lab/claude-harness',
                title: 'Optimize token prompt compression',
                state: 'open',
                prNumber: 42,
                updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000050000),
              ),
            ],
          ),
          threads: QmdThreadPage(
            threads: <QmdContextThread>[
              QmdContextThread(
                id: 'thread-202',
                scope: 'ai-workspace-lab/qmd',
                title: 'Add lazy pgvector auto-recovery',
                state: 'open',
                updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000060000),
              ),
            ],
          ),
        );

        controller.agentContextClientOverride = fakeClient;

        await controller.refreshQmdRemoteTasksInternal();

        expect(controller.qmdRemoteSessionSummariesInternal.length, equals(3));
        expect(controller.qmdRemoteThreadRecordsInternal.length, equals(3));

        // Verify sessions appear in assistantSessions
        final sessions = controller.assistantSessions;
        final pinSession = sessions.firstWhere(
          (s) => s.key == 'qmd:pin:pin-101',
        );
        expect(
          pinSession.displayName,
          equals('[Codex] Refactor bridge reconnect'),
        );
        expect(pinSession.lastMessagePreview, contains('[QMD 钉选]'));

        final claudeSession = sessions.firstWhere(
          (s) => s.key == 'qmd:thread:thread-201',
        );
        expect(
          claudeSession.displayName,
          equals('[Claude] Optimize token prompt compression'),
        );
        expect(claudeSession.lastMessagePreview, contains('[QMD 任务] #42'));

        final qmdSession = sessions.firstWhere(
          (s) => s.key == 'qmd:thread:thread-202',
        );
        expect(
          qmdSession.displayName,
          equals('[QMD] Add lazy pgvector auto-recovery'),
        );
        await controller.switchSession('qmd:thread:thread-202');
        expect(
          controller.assistantSessions
              .firstWhere((s) => s.key == 'qmd:thread:thread-202')
              .displayName,
          equals('[QMD] Add lazy pgvector auto-recovery'),
        );

        // Verify taskThreadForSessionInternal returns in-memory TaskThread
        final threadRecord = controller.taskThreadForSessionInternal(
          'qmd:thread:thread-201',
        );
        expect(threadRecord, isNotNull);
        expect(threadRecord!.lifecycleState.status, equals('active'));
        expect(threadRecord.workspaceBinding.workspaceId, equals('qmd'));

        // Verify taskThreadRepositoryInternal does NOT contain QMD tasks (no disk pollution)
        expect(
          controller.taskThreadRepositoryInternal.taskThreadForSession(
            'qmd:pin:pin-101',
          ),
          isNull,
        );
        expect(
          controller.taskThreadRepositoryInternal.taskThreadForSession(
            'qmd:thread:thread-201',
          ),
          isNull,
        );
      },
    );

    test(
      'switchSession for QMD thread loads rich briefing into localSessionMessagesInternal',
      () async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );

        final fakeClient = _FakeAgentContextClient(
          briefing: QmdThreadBriefing(
            thread: const QmdContextThread(
              id: 'thread-99',
              scope: 'ai-workspace-lab/xworkmate-app',
              title: 'Fix bridge timeout',
              state: 'open',
              headBranch: 'fix/bridge-timeout',
              prNumber: 99,
            ),
            items: const <QmdBriefingItem>[
              QmdBriefingItem(
                kind: 'decision',
                key: 'dec-1',
                status: 'done',
                text: 'Use 10s timeout with linear backoff',
                detail: 'Prevents stalling on cold restarts',
                sources: <String>['codex'],
              ),
            ],
            contributors: const <QmdBriefingContributor>[
              QmdBriefingContributor(source: 'codex', sessions: 3),
            ],
          ),
        );

        controller.agentContextClientOverride = fakeClient;

        await controller.switchSession('qmd:thread:thread-99');

        expect(controller.currentSessionKey, equals('qmd:thread:thread-99'));
        final messages =
            controller.localSessionMessagesInternal['qmd:thread:thread-99'];
        expect(messages, isNotNull);
        expect(messages!.length, equals(1));
        final text = messages.first.text;
        expect(text, contains('# 📋 任务简报: Fix bridge timeout'));
        expect(text, contains('Use 10s timeout with linear backoff'));
        expect(text, contains('Prevents stalling on cold restarts'));
        expect(text, contains('**codex**: 3 会话'));
        expect(text, contains('历史来源保持只读'));
      },
    );

    test(
      'QMD continuation creates a writable draft without changing the remote source',
      () async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );

        controller.agentContextClientOverride = _FakeAgentContextClient();
        await controller.switchSession('qmd:thread:thread-readonly');
        final source = controller
            .localSessionMessagesInternal['qmd:thread:thread-readonly']!
            .first
            .text;
        final key = await controller.createQmdContinuationInternal(
          'qmd:thread:thread-readonly',
        );
        expect(key, startsWith('draft:'));
        expect(controller.currentSessionKey, key);
        expect(
          controller
              .taskThreadForSessionInternal(key)!
              .workspaceBinding
              .writable,
          isTrue,
        );
        expect(
          controller.localSessionMessagesInternal[key]!.first.text,
          contains('qmd:thread:thread-readonly'),
        );
        expect(
          controller
              .localSessionMessagesInternal['qmd:thread:thread-readonly']!
              .first
              .text,
          source,
        );
      },
    );

    test(
      'QMD continuation refuses stale context after a refresh failure',
      () async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );
        controller.agentContextClientOverride = _FakeAgentContextClient();
        const sourceKey = 'qmd:thread:stale-source';
        await controller.switchSession(sourceKey);
        final before = controller.localSessionMessagesInternal.keys.toSet();
        controller.agentContextClientOverride = _FakeAgentContextClient(
          shouldThrow: true,
        );
        await expectLater(
          controller.createQmdContinuationInternal(sourceKey),
          throwsA(isA<AgentContextException>()),
        );
        expect(controller.currentSessionKey, sourceKey);
        expect(controller.localSessionMessagesInternal.keys.toSet(), before);
      },
    );

    test(
      'handles network exceptions gracefully during background refresh without breaking controller',
      () async {
        final controller = AppController(
          environmentOverride: const <String, String>{},
        );

        final failingClient = _FakeAgentContextClient(shouldThrow: true);
        controller.agentContextClientOverride = failingClient;

        // Should complete without throwing
        await expectLater(
          controller.refreshQmdRemoteTasksInternal(),
          completes,
        );
        expect(controller.qmdRemoteSessionSummariesInternal.isEmpty, isTrue);
      },
    );
  });
}
