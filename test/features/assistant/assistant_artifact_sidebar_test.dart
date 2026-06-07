import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/assistant_artifacts.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/assistant_artifact_sidebar.dart';

void main() {
  testWidgets('refreshes snapshot when artifact sync timestamp changes', (
    tester,
  ) async {
    var loadCount = 0;
    Future<AssistantArtifactSnapshot> loadSnapshot() async {
      loadCount += 1;
      return AssistantArtifactSnapshot(
        workspacePath: '/tmp/thread',
        workspaceKind: WorkspaceRefKind.localPath,
        fileEntries: <AssistantArtifactEntry>[
          AssistantArtifactEntry(
            id: 'entry-$loadCount',
            label: 'artifact-$loadCount.txt',
            relativePath: 'artifact-$loadCount.txt',
            kind: AssistantArtifactEntryKind.file,
            mimeType: 'text/plain',
            previewable: true,
            workspacePath: '/tmp/thread',
          ),
        ],
      );
    }

    await tester.pumpWidget(
      _buildTestApp(artifactSyncAtMs: 1, loadSnapshot: loadSnapshot),
    );
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    expect(find.text('artifact-1.txt'), findsAtLeastNWidgets(1));

    await tester.pumpWidget(
      _buildTestApp(artifactSyncAtMs: 2, loadSnapshot: loadSnapshot),
    );
    await tester.pumpAndSettle();

    expect(loadCount, 2);
    expect(find.text('artifact-2.txt'), findsAtLeastNWidgets(1));
  });

  testWidgets(
    'clears stale artifacts and ignores late snapshot after task switch',
    (tester) async {
      final firstSnapshot = Completer<AssistantArtifactSnapshot>();
      var sessionKey = 'task-a';
      var workspacePath = '/tmp/task-a';

      Future<AssistantArtifactSnapshot> loadSnapshot() {
        final capturedSessionKey = sessionKey;
        if (capturedSessionKey == 'task-a') {
          return firstSnapshot.future;
        }
        return Future<AssistantArtifactSnapshot>.value(
          AssistantArtifactSnapshot(
            workspacePath: '/tmp/task-b',
            workspaceKind: WorkspaceRefKind.localPath,
            fileEntries: const <AssistantArtifactEntry>[
              AssistantArtifactEntry(
                id: 'task-b-entry',
                label: 'task-b.md',
                relativePath: 'task-b.md',
                kind: AssistantArtifactEntryKind.file,
                mimeType: 'text/markdown',
                previewable: true,
                workspacePath: '/tmp/task-b',
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(
        _buildTestApp(
          sessionKey: sessionKey,
          workspacePath: workspacePath,
          artifactSyncAtMs: 1,
          loadSnapshot: loadSnapshot,
        ),
      );
      await tester.pump();

      sessionKey = 'task-b';
      workspacePath = '/tmp/task-b';
      await tester.pumpWidget(
        _buildTestApp(
          sessionKey: sessionKey,
          workspacePath: workspacePath,
          artifactSyncAtMs: 1,
          loadSnapshot: loadSnapshot,
        ),
      );
      await tester.pump();

      expect(find.text('task-a.md'), findsNothing);

      firstSnapshot.complete(
        AssistantArtifactSnapshot(
          workspacePath: '/tmp/task-a',
          workspaceKind: WorkspaceRefKind.localPath,
          fileEntries: const <AssistantArtifactEntry>[
            AssistantArtifactEntry(
              id: 'task-a-entry',
              label: 'task-a.md',
              relativePath: 'task-a.md',
              kind: AssistantArtifactEntryKind.file,
              mimeType: 'text/markdown',
              previewable: true,
              workspacePath: '/tmp/task-a',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('task-a.md'), findsNothing);
      expect(find.text('task-b.md'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('keeps polling partial artifact snapshots', (tester) async {
    var loadCount = 0;

    await tester.pumpWidget(
      _buildTestApp(
        artifactSyncAtMs: 1,
        artifactSyncStatus: 'partial',
        loadSnapshot: () async {
          loadCount += 1;
          return AssistantArtifactSnapshot(
            workspacePath: '/tmp/thread',
            workspaceKind: WorkspaceRefKind.localPath,
            fileEntries: <AssistantArtifactEntry>[
              AssistantArtifactEntry(
                id: 'entry-$loadCount',
                label: 'artifact-$loadCount.txt',
                relativePath: 'artifact-$loadCount.txt',
                kind: AssistantArtifactEntryKind.file,
                mimeType: 'text/plain',
                previewable: true,
                workspacePath: '/tmp/thread',
              ),
            ],
          );
        },
      ),
    );
    await tester.pump();

    expect(loadCount, 1);

    await tester.pump(const Duration(milliseconds: 3100));
    await tester.pump();

    expect(loadCount, greaterThanOrEqualTo(2));
    expect(find.text('artifact-2.txt'), findsAtLeastNWidgets(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explains OpenClaw runs with no exported artifacts', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        artifactSyncAtMs: 1,
        artifactSyncStatus: 'failed',
        loadSnapshot: () async => const AssistantArtifactSnapshot(
          workspacePath: '/tmp/thread',
          workspaceKind: WorkspaceRefKind.localPath,
          filesMessage: 'No files found in the recorded working directory.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('本轮没有检测到实际生成的文件。请重新执行，并要求 OpenClaw 在当前 workspace 中创建文件。'),
      findsOneWidget,
    );
    expect(find.textContaining('口头下载声明'), findsNothing);
    expect(find.textContaining('已阻止'), findsNothing);
    expect(find.textContaining('artifacts 面板'), findsNothing);
  });

  testWidgets('keeps the ordinary empty directory message', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        artifactSyncAtMs: 1,
        loadSnapshot: () async => const AssistantArtifactSnapshot(
          workspacePath: '/tmp/thread',
          workspaceKind: WorkspaceRefKind.localPath,
          filesMessage: 'No files found in the recorded working directory.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No files found in the recorded working directory.'),
      findsOneWidget,
    );
    expect(
      find.text('本轮没有检测到实际生成的文件。请重新执行，并要求 OpenClaw 在当前 workspace 中创建文件。'),
      findsNothing,
    );
  });

  testWidgets('keeps binary artifacts out of preview flow', (tester) async {
    var previewLoadCount = 0;

    await tester.pumpWidget(
      _buildTestApp(
        artifactSyncAtMs: 1,
        loadSnapshot: () async => AssistantArtifactSnapshot(
          workspacePath: '/tmp/thread',
          workspaceKind: WorkspaceRefKind.localPath,
          fileEntries: <AssistantArtifactEntry>[
            const AssistantArtifactEntry(
              id: 'pdf',
              label: 'report.pdf',
              relativePath: 'report.pdf',
              kind: AssistantArtifactEntryKind.file,
              mimeType: 'application/pdf',
              previewable: false,
              workspacePath: '/tmp/thread',
            ),
            const AssistantArtifactEntry(
              id: 'md',
              label: 'notes.md',
              relativePath: 'notes.md',
              kind: AssistantArtifactEntryKind.file,
              mimeType: 'text/markdown',
              previewable: true,
              workspacePath: '/tmp/thread',
            ),
          ],
        ),
        loadPreview: (_) async {
          previewLoadCount += 1;
          return const AssistantArtifactPreview(
            kind: AssistantArtifactPreviewKind.markdown,
            content: '# Notes',
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-artifact-entry-report.pdf')),
    );
    await tester.pumpAndSettle();

    expect(previewLoadCount, 0);
    expect(
      find.byKey(const Key('assistant-artifact-preview-markdown')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-artifact-entry-notes.md')),
    );
    await tester.pumpAndSettle();

    expect(previewLoadCount, 1);
    expect(
      find.byKey(const Key('assistant-artifact-preview-markdown')),
      findsOneWidget,
    );
  });

  testWidgets('opens the selected artifact location from the file list', (
    tester,
  ) async {
    AssistantArtifactEntry? openedEntry;

    await tester.pumpWidget(
      _buildTestApp(
        artifactSyncAtMs: 1,
        loadSnapshot: () async => const AssistantArtifactSnapshot(
          workspacePath: '/tmp/thread',
          workspaceKind: WorkspaceRefKind.localPath,
          fileEntries: <AssistantArtifactEntry>[
            AssistantArtifactEntry(
              id: 'pdf',
              label: 'report.pdf',
              relativePath: 'reports/report.pdf',
              kind: AssistantArtifactEntryKind.file,
              mimeType: 'application/pdf',
              previewable: false,
              workspacePath: '/tmp/thread',
            ),
          ],
        ),
        onOpenEntryLocation: (entry) async {
          openedEntry = entry;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'assistant-artifact-open-location-reports/report.pdf',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(openedEntry?.relativePath, 'reports/report.pdf');
  });
}

Widget _buildTestApp({
  String sessionKey = 'unit-fixture-task-a',
  String workspacePath = '/tmp/thread',
  required double artifactSyncAtMs,
  String artifactSyncStatus = '',
  required Future<AssistantArtifactSnapshot> Function() loadSnapshot,
  Future<AssistantArtifactPreview> Function(AssistantArtifactEntry entry)?
  loadPreview,
  Future<void> Function(AssistantArtifactEntry entry)? onOpenEntryLocation,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Material(
      child: SizedBox(
        width: 460,
        height: 640,
        child: AssistantArtifactSidebar(
          sessionKey: sessionKey,
          threadTitle: 'Thread',
          workspacePath: workspacePath,
          workspaceKind: WorkspaceRefKind.localPath,
          artifactSyncAtMs: artifactSyncAtMs,
          artifactSyncStatus: artifactSyncStatus,
          taskContextMessageCount: 2,
          taskContextSelectedSkillKeys: const <String>['openclaw'],
          taskContextRemoteWorkingDirectory:
              '/home/ubuntu/.openclaw/workspace/tasks/unit/run',
          taskContextOpenClawRunId: 'run',
          taskContextOpenClawStatus: 'syncing-artifacts',
          onCollapse: () {},
          loadSnapshot: loadSnapshot,
          loadPreview:
              loadPreview ??
              (_) async => const AssistantArtifactPreview.empty(),
          onOpenEntryLocation: onOpenEntryLocation,
        ),
      ),
    ),
  );
}
