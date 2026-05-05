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
}

Widget _buildTestApp({
  required double artifactSyncAtMs,
  required Future<AssistantArtifactSnapshot> Function() loadSnapshot,
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
          loadPreview: (_) async => const AssistantArtifactPreview.empty(),
        ),
      ),
    ),
  );
}
