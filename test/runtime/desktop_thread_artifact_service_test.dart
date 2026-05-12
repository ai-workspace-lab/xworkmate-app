import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/desktop_thread_artifact_service.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'loadSnapshot exposes all local workspace files when current run has no artifacts',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'xworkmate-artifact-snapshot-',
      );
      addTearDown(() async {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      });
      await File('${workspace.path}/historical.md').writeAsString('old');

      final snapshot = await DesktopThreadArtifactService().loadSnapshot(
        workspacePath: workspace.path,
        workspaceKind: WorkspaceRefKind.localPath,
        artifactRelativePaths: const <String>[],
      );

      expect(snapshot.resultEntries, isEmpty);
      expect(
        snapshot.fileEntries.map((entry) => entry.relativePath),
        contains('historical.md'),
      );
      expect(
        snapshot.resultMessage,
        'No task artifacts recorded for this run.',
      );
      expect(snapshot.filesMessage, isEmpty);
    },
  );

  test(
    'loadSnapshot keeps current task artifacts separate from all files',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'xworkmate-artifact-snapshot-',
      );
      addTearDown(() async {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      });
      await File('${workspace.path}/historical.md').writeAsString('old');
      await File('${workspace.path}/current.md').writeAsString('new');

      final snapshot = await DesktopThreadArtifactService().loadSnapshot(
        workspacePath: workspace.path,
        workspaceKind: WorkspaceRefKind.localPath,
        artifactRelativePaths: const <String>['current.md'],
      );

      expect(
        snapshot.resultEntries.map((entry) => entry.relativePath),
        <String>['current.md'],
      );
      expect(
        snapshot.fileEntries.map((entry) => entry.relativePath),
        containsAll(<String>['current.md', 'historical.md']),
      );
    },
  );

  test(
    'loadPreview allows user-selected historical files in the thread workspace',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'xworkmate-artifact-preview-',
      );
      addTearDown(() async {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      });
      await File('${workspace.path}/historical.md').writeAsString('# Old\n');
      final snapshot = await DesktopThreadArtifactService().loadSnapshot(
        workspacePath: workspace.path,
        workspaceKind: WorkspaceRefKind.localPath,
        artifactRelativePaths: const <String>[],
      );
      final historical = snapshot.fileEntries.singleWhere(
        (entry) => entry.relativePath == 'historical.md',
      );

      final preview = await DesktopThreadArtifactService().loadPreview(
        entry: historical,
        workspacePath: workspace.path,
        workspaceKind: WorkspaceRefKind.localPath,
        artifactRelativePaths: const <String>[],
      );

      expect(preview.content, '# Old\n');
    },
  );
}
