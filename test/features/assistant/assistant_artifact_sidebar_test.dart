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
  required double artifactSyncAtMs,
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
          sessionKey: 'session-1',
          threadTitle: 'Thread',
          workspacePath: '/tmp/thread',
          workspaceKind: WorkspaceRefKind.localPath,
          artifactSyncAtMs: artifactSyncAtMs,
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
