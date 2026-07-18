import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/assistant_artifacts.dart';
import 'package:xworkmate/runtime/desktop_thread_artifact_service.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'loadSnapshot hides historical workspace files when current run has no artifacts',
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
      expect(snapshot.fileEntries, isEmpty);
      expect(
        snapshot.resultMessage,
        'No task artifacts recorded for this run.',
      );
      expect(snapshot.filesMessage, isEmpty);
    },
  );

  test(
    'loadSnapshot keeps the file list scoped to current task artifacts',
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
      expect(snapshot.fileEntries.map((entry) => entry.relativePath), <String>[
        'current.md',
      ]);
    },
  );

  test(
    'loadSnapshot shows the root PDF deliverable before supporting files',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'xworkmate-pdf-artifact-order-',
      );
      addTearDown(() async {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      });
      await Directory(
        '${workspace.path}/assets/diagrams',
      ).create(recursive: true);
      await File(
        '${workspace.path}/assets/diagrams/chapter.png',
      ).writeAsBytes(<int>[1, 2, 3]);
      await File(
        '${workspace.path}/assets/安全架构演进白皮书.pdf',
      ).writeAsBytes(<int>[4, 5, 6]);
      await File(
        '${workspace.path}/安全架构演进白皮书.pdf',
      ).writeAsBytes(<int>[4, 5, 6]);

      final snapshot = await DesktopThreadArtifactService().loadSnapshot(
        workspacePath: workspace.path,
        workspaceKind: WorkspaceRefKind.localPath,
        artifactRelativePaths: const <String>[
          'assets/diagrams/chapter.png',
          'assets/安全架构演进白皮书.pdf',
          '安全架构演进白皮书.pdf',
        ],
      );

      expect(snapshot.fileEntries.map((entry) => entry.relativePath), <String>[
        '安全架构演进白皮书.pdf',
        'assets/安全架构演进白皮书.pdf',
        'assets/diagrams/chapter.png',
      ]);
      expect(snapshot.resultEntries.first.mimeType, 'application/pdf');
    },
  );

  test(
    'loadPreview rejects historical files outside current task artifacts',
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
      const historical = AssistantArtifactEntry(
        id: 'historical.md',
        label: 'historical.md',
        relativePath: 'historical.md',
        kind: AssistantArtifactEntryKind.file,
        mimeType: 'text/markdown',
        previewable: true,
        workspacePath: '',
      );

      final preview = await DesktopThreadArtifactService().loadPreview(
        entry: historical,
        workspacePath: workspace.path,
        workspaceKind: WorkspaceRefKind.localPath,
        artifactRelativePaths: const <String>[],
      );

      expect(preview.kind, AssistantArtifactPreviewKind.empty);
      expect(preview.content, isEmpty);
    },
  );

  test('loadFile returns the original binary artifact bytes', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'xworkmate-artifact-file-',
    );
    addTearDown(() async {
      if (await workspace.exists()) {
        await workspace.delete(recursive: true);
      }
    });
    final image = File('${workspace.path}/poster.png');
    await image.writeAsBytes(<int>[0, 255, 16, 32]);
    const entry = AssistantArtifactEntry(
      id: 'poster.png',
      label: 'poster.png',
      relativePath: 'poster.png',
      kind: AssistantArtifactEntryKind.file,
      mimeType: 'image/png',
      previewable: false,
      workspacePath: '',
    );

    final resolved = await DesktopThreadArtifactService().loadFile(
      entry: entry,
      workspacePath: workspace.path,
      workspaceKind: WorkspaceRefKind.localPath,
      artifactRelativePaths: const <String>['poster.png'],
    );

    expect(resolved, isNotNull);
    expect(await resolved!.readAsBytes(), <int>[0, 255, 16, 32]);
  });

  test('loadFile rejects files outside the current task artifacts', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'xworkmate-artifact-file-boundary-',
    );
    addTearDown(() async {
      if (await workspace.exists()) {
        await workspace.delete(recursive: true);
      }
    });
    await File('${workspace.path}/historical.mp4').writeAsBytes(<int>[1, 2]);
    const entry = AssistantArtifactEntry(
      id: 'historical.mp4',
      label: 'historical.mp4',
      relativePath: 'historical.mp4',
      kind: AssistantArtifactEntryKind.file,
      mimeType: 'video/mp4',
      previewable: false,
      workspacePath: '',
    );

    final resolved = await DesktopThreadArtifactService().loadFile(
      entry: entry,
      workspacePath: workspace.path,
      workspaceKind: WorkspaceRefKind.localPath,
      artifactRelativePaths: const <String>[],
    );

    expect(resolved, isNull);
  });

  test(
    'loadSnapshot identifies common document and media artifact types',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'xworkmate-artifact-mime-',
      );
      addTearDown(() async {
        if (await workspace.exists()) {
          await workspace.delete(recursive: true);
        }
      });
      const paths = <String>[
        'deck.pptx',
        'sheet.xlsx',
        'document.docx',
        'audio.m4a',
        'video.mp4',
        'archive.zip',
        'vector.svg',
      ];
      for (final path in paths) {
        await File('${workspace.path}/$path').writeAsBytes(<int>[1]);
      }

      final snapshot = await DesktopThreadArtifactService().loadSnapshot(
        workspacePath: workspace.path,
        workspaceKind: WorkspaceRefKind.localPath,
        artifactRelativePaths: paths,
      );
      final mimeTypes = <String, String>{
        for (final entry in snapshot.fileEntries)
          entry.relativePath: entry.mimeType,
      };

      expect(mimeTypes, <String, String>{
        'deck.pptx':
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'sheet.xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'document.docx':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'audio.m4a': 'audio/mp4',
        'video.mp4': 'video/mp4',
        'archive.zip': 'application/zip',
        'vector.svg': 'image/svg+xml',
      });
    },
  );

  test(
    'artifact access follows the workspace recorded by the task entry',
    () async {
      final currentWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-current-artifact-workspace-',
      );
      final staleWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-stale-artifact-workspace-',
      );
      addTearDown(() async {
        await currentWorkspace.delete(recursive: true);
        await staleWorkspace.delete(recursive: true);
      });
      await File(
        '${currentWorkspace.path}/report.md',
      ).writeAsString('# Current');
      await File('${staleWorkspace.path}/report.md').writeAsString('# Stale');
      final entry = AssistantArtifactEntry(
        id: '${currentWorkspace.path}::report.md',
        label: 'report.md',
        relativePath: 'report.md',
        kind: AssistantArtifactEntryKind.file,
        mimeType: 'text/markdown',
        previewable: true,
        workspacePath: currentWorkspace.path,
      );
      final service = DesktopThreadArtifactService();

      final preview = await service.loadPreview(
        entry: entry,
        workspacePath: staleWorkspace.path,
        workspaceKind: WorkspaceRefKind.localPath,
        artifactRelativePaths: const <String>['report.md'],
      );
      final sharedFile = await service.loadFile(
        entry: entry,
        workspacePath: staleWorkspace.path,
        workspaceKind: WorkspaceRefKind.localPath,
        artifactRelativePaths: const <String>['report.md'],
      );

      expect(preview.content, contains('Current'));
      expect(preview.content, isNot(contains('Stale')));
      expect(sharedFile?.path, '${currentWorkspace.path}/report.md');
    },
  );
}
