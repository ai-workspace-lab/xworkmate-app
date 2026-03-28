@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/assistant_artifacts.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/assistant_artifact_sidebar.dart';

void main() {
  Future<void> pumpSidebar(
    WidgetTester tester, {
    required AssistantArtifactSnapshot snapshot,
    required AssistantArtifactPreview Function(AssistantArtifactEntry entry)
    previewForEntry,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: AssistantArtifactSidebar(
              sessionKey: 'thread-1',
              threadTitle: 'Artifact Thread',
              workspaceRef: snapshot.workspaceRef,
              workspaceRefKind: snapshot.workspaceRefKind,
              onCollapse: () {},
              loadSnapshot: () async => snapshot,
              loadPreview: (entry) async => previewForEntry(entry),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AssistantArtifactSidebar renders markdown and html previews', (
    WidgetTester tester,
  ) async {
    final markdownEntry = AssistantArtifactEntry(
      id: 'md',
      label: 'README.md',
      relativePath: 'README.md',
      kind: AssistantArtifactEntryKind.file,
      mimeType: 'text/markdown',
      previewable: true,
      workspaceRef: '/tmp/thread',
    );
    final htmlEntry = AssistantArtifactEntry(
      id: 'html',
      label: 'preview.html',
      relativePath: 'preview.html',
      kind: AssistantArtifactEntryKind.file,
      mimeType: 'text/html',
      previewable: true,
      workspaceRef: '/tmp/thread',
    );
    final snapshot = AssistantArtifactSnapshot(
      workspaceRef: '/tmp/thread',
      workspaceRefKind: WorkspaceRefKind.localPath,
      resultEntries: <AssistantArtifactEntry>[markdownEntry, htmlEntry],
      fileEntries: <AssistantArtifactEntry>[markdownEntry, htmlEntry],
    );

    await pumpSidebar(
      tester,
      snapshot: snapshot,
      previewForEntry: (entry) {
        if (entry.relativePath.endsWith('.html')) {
          return const AssistantArtifactPreview(
            kind: AssistantArtifactPreviewKind.html,
            content: '<h1>HTML Preview</h1>',
          );
        }
        return const AssistantArtifactPreview(
          kind: AssistantArtifactPreviewKind.markdown,
          content: '# Markdown Preview',
        );
      },
    );

    expect(find.text('全部文件'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('结果'), findsNothing);
    expect(find.text('变更'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('assistant-artifact-entry-README.md')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('assistant-artifact-preview-markdown')),
      findsOneWidget,
    );
    expect(find.text('Markdown Preview'), findsOneWidget);

    await tester.tap(find.text('全部文件'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('assistant-artifact-entry-preview.html'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('assistant-artifact-preview-html')),
      findsOneWidget,
    );
    expect(find.text('HTML Preview'), findsOneWidget);
  });
}
