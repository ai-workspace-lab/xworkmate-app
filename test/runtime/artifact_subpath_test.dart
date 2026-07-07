import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/desktop_thread_artifact_service.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/assistant_artifacts.dart';

void main() {
  group('DesktopThreadArtifactService subpath matches', () {
    late Directory tempDir;
    late DesktopThreadArtifactService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('xworkmate-subpath-test-');
      service = DesktopThreadArtifactService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('recursively collects files for directory artifact paths', () async {
      final subDir = Directory('${tempDir.path}/tasks/run_123');
      await subDir.create(recursive: true);
      final file1 = File('${subDir.path}/01.md');
      await file1.writeAsString('file 1');
      final file2 = File('${subDir.path}/02.txt');
      await file2.writeAsString('file 2');

      final collected = await service.collectTaskArtifactFilesInternal(
        tempDir,
        tempDir.path,
        ['tasks/run_123'],
      );

      expect(collected.length, 2);
      final paths = collected.map((f) => f.path).toList();
      expect(paths, contains(file1.path));
      expect(paths, contains(file2.path));
    });

    test('previews files matching a directory task artifact subpath', () async {
      final subDir = Directory('${tempDir.path}/tasks/run_123');
      await subDir.create(recursive: true);
      final file = File('${subDir.path}/01.md');
      await file.writeAsString('markdown content');

      final entry = AssistantArtifactEntry(
        id: '${tempDir.path}::tasks/run_123/01.md',
        label: '01.md',
        relativePath: 'tasks/run_123/01.md',
        kind: AssistantArtifactEntryKind.file,
        mimeType: 'text/markdown',
        previewable: true,
        workspacePath: tempDir.path,
      );

      final preview = await service.loadPreview(
        entry: entry,
        workspacePath: tempDir.path,
        workspaceKind: WorkspaceRefKind.localPath,
        artifactRelativePaths: ['tasks/run_123'],
      );

      expect(preview.kind, AssistantArtifactPreviewKind.markdown);
      expect(preview.content, contains('markdown content'));
    });
  });
}
