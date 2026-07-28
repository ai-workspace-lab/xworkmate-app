import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/workbench/workbench_projection.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('WorkbenchProjection', () {
    test('groups TaskThreads by workspace and exposes real artifacts', () {
      final now = DateTime(2026, 7, 28, 12);
      final thread = _thread(
        sessionKey: 'draft:alpha',
        title: '权限控制设计',
        workspacePath: '/workspaces/ai-workspace-lab/xworkmate-app',
        status: 'running',
        updatedAtMs: now.millisecondsSinceEpoch.toDouble(),
        artifactPaths: const ['docs/plan/permissions.xlsx'],
        attachments: const [
          TaskInputAttachmentRecord(
            name: 'review-notes.md',
            mimeType: 'text/markdown',
            sha256: 'abc123',
            type: 'file',
            uploadedAtMs: 10,
          ),
        ],
      );

      final projection = buildWorkbenchProjection(
        sessions: [_session('draft:alpha', '权限控制设计')],
        threadForSession: (key) => key == thread.threadId ? thread : null,
        now: now,
      );

      expect(projection.items, hasLength(1));
      expect(projection.items.single.state, WorkbenchItemState.running);
      expect(projection.projects.single.label, 'xworkmate-app');
      expect(projection.projects.single.artifactCount, 1);
      expect(
        projection.inbox.map((item) => item.kind),
        containsAll([
          WorkbenchInboxKind.artifact,
          WorkbenchInboxKind.attachment,
        ]),
      );
      expect(projection.artifactCount, 1);
    });

    test('uses latest user message as an inbox note when no files exist', () {
      final now = DateTime(2026, 7, 28, 12);
      final thread = _thread(
        sessionKey: 'draft:note',
        title: '会议跟进',
        workspacePath: '/workspaces/notes',
        status: 'ready',
        updatedAtMs: now.millisecondsSinceEpoch.toDouble(),
        messages: [
          GatewayChatMessage(
            id: 'message-1',
            role: 'user',
            text: '把今天的会议结论整理成三个下一步动作',
            timestampMs: now.millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
        ],
      );

      final projection = buildWorkbenchProjection(
        sessions: [_session('draft:note', '会议跟进')],
        threadForSession: (_) => thread,
        now: now,
      );

      expect(projection.inbox, hasLength(1));
      expect(projection.inbox.single.kind, WorkbenchInboxKind.note);
      expect(projection.inbox.single.title, contains('会议结论'));
      expect(projection.todos, hasLength(1));
    });

    test('builds seven-day workload from TaskThread activity timestamps', () {
      final now = DateTime(2026, 7, 28, 12);
      final yesterday = now.subtract(const Duration(days: 1));
      final thread = _thread(
        sessionKey: 'draft:trend',
        title: '趋势数据',
        workspacePath: '/workspaces/trend',
        status: 'completed',
        updatedAtMs: yesterday.millisecondsSinceEpoch.toDouble(),
        messages: [
          GatewayChatMessage(
            id: 'message-2',
            role: 'assistant',
            text: '已完成',
            timestampMs: yesterday.millisecondsSinceEpoch.toDouble(),
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
        ],
      );

      final projection = buildWorkbenchProjection(
        sessions: [_session('draft:trend', '趋势数据')],
        threadForSession: (_) => thread,
        now: now,
      );

      expect(projection.workloadSeries, hasLength(7));
      expect(projection.workloadSeries[5], greaterThanOrEqualTo(2));
      expect(projection.completedCount, 1);
    });
  });
}

GatewaySessionSummary _session(String key, String title) {
  return GatewaySessionSummary(
    key: key,
    kind: 'assistant',
    displayName: title,
    surface: 'desktop',
    subject: title,
    room: null,
    space: null,
    updatedAtMs: 1,
    sessionId: key,
    systemSent: false,
    abortedLastRun: false,
    thinkingLevel: null,
    verboseLevel: null,
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    model: null,
    contextTokens: 0,
    derivedTitle: title,
    lastMessagePreview: '',
  );
}

TaskThread _thread({
  required String sessionKey,
  required String title,
  required String workspacePath,
  required String status,
  required double updatedAtMs,
  List<String> artifactPaths = const [],
  List<TaskInputAttachmentRecord> attachments = const [],
  List<GatewayChatMessage> messages = const [],
}) {
  return TaskThread(
    threadId: sessionKey,
    title: title,
    workspaceBinding: WorkspaceBinding(
      workspaceId: sessionKey,
      workspaceKind: WorkspaceKind.localFs,
      workspacePath: workspacePath,
      displayPath: workspacePath,
      writable: true,
    ),
    lifecycleState: ThreadLifecycleState(
      archived: false,
      status: status,
      lastRunAtMs: updatedAtMs,
      lastResultCode: null,
    ),
    updatedAtMs: updatedAtMs,
    messages: messages,
    lastTaskArtifactRelativePaths: artifactPaths,
    taskInputAttachments: attachments,
  );
}
