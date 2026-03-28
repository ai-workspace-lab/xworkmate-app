@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/assistant_artifacts.dart';
import 'package:xworkmate/runtime/desktop_thread_artifact_service.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  final service = DesktopThreadArtifactService();

  test(
    'DesktopThreadArtifactService lists files and previews markdown/html',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'xworkmate-artifact-service-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final markdownFile = File('${root.path}/README.md');
      final htmlFile = File('${root.path}/preview.html');
      final binaryFile = File('${root.path}/archive.bin');
      await markdownFile.writeAsString('# Demo\n\nartifact preview');
      await htmlFile.writeAsString(
        '<html><body><h1>Preview</h1><script>alert(1)</script></body></html>',
      );
      await binaryFile.writeAsBytes(const <int>[1, 2, 3, 4]);

      final snapshot = await service.loadSnapshot(
        workspaceRef: root.path,
        workspaceRefKind: WorkspaceRefKind.localPath,
      );

      expect(
        snapshot.fileEntries.map((item) => item.relativePath),
        containsAll(<String>['README.md', 'preview.html', 'archive.bin']),
      );

      final markdownEntry = snapshot.fileEntries.firstWhere(
        (item) => item.relativePath == 'README.md',
      );
      final htmlEntry = snapshot.fileEntries.firstWhere(
        (item) => item.relativePath == 'preview.html',
      );
      final binaryEntry = snapshot.fileEntries.firstWhere(
        (item) => item.relativePath == 'archive.bin',
      );

      final markdownPreview = await service.loadPreview(
        entry: markdownEntry,
        workspaceRef: root.path,
        workspaceRefKind: WorkspaceRefKind.localPath,
      );
      expect(markdownPreview.kind, AssistantArtifactPreviewKind.markdown);
      expect(markdownPreview.content, contains('artifact preview'));

      final htmlPreview = await service.loadPreview(
        entry: htmlEntry,
        workspaceRef: root.path,
        workspaceRefKind: WorkspaceRefKind.localPath,
      );
      expect(htmlPreview.kind, AssistantArtifactPreviewKind.html);
      expect(htmlPreview.content, contains('<h1>Preview</h1>'));
      expect(htmlPreview.content, isNot(contains('<script>')));

      final binaryPreview = await service.loadPreview(
        entry: binaryEntry,
        workspaceRef: root.path,
        workspaceRefKind: WorkspaceRefKind.localPath,
      );
      expect(binaryPreview.kind, AssistantArtifactPreviewKind.unsupported);
    },
  );

  test(
    'DesktopThreadArtifactService reports git changes for the active subtree',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'xworkmate-artifact-git-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final workspace = Directory('${root.path}/workspace');
      await workspace.create(recursive: true);
      await Process.run('git', <String>['init', root.path]);
      await File('${workspace.path}/result.md').writeAsString('# Result');
      await File('${root.path}/outside.txt').writeAsString('ignore me');

      final snapshot = await service.loadSnapshot(
        workspaceRef: workspace.path,
        workspaceRefKind: WorkspaceRefKind.localPath,
      );

      expect(snapshot.changes, isNotEmpty);
      expect(snapshot.changes.first.path, 'result.md');
      expect(snapshot.changes.first.displayLabel, 'Untracked');
      expect(
        snapshot.resultEntries.map((item) => item.relativePath),
        contains('result.md'),
      );
      expect(
        snapshot.resultEntries.map((item) => item.relativePath),
        isNot(contains('outside.txt')),
      );
    },
  );

  test(
    'DesktopThreadArtifactService reports remote workspaces as non-browsable',
    () async {
      final snapshot = await service.loadSnapshot(
        workspaceRef: '/opt/data/.xworkmate/threads/draft-remote-thread',
        workspaceRefKind: WorkspaceRefKind.remotePath,
      );

      expect(snapshot.resultEntries, isEmpty);
      expect(snapshot.fileEntries, isEmpty);
      expect(snapshot.resultMessage, contains('recorded on a remote agent'));
    },
  );
}
