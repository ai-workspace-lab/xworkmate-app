import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/desktop_thread_artifact_sync.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';

void main() {
  group('syncInlineArtifactsToLocalWorkspace', () {
    test('writes inline artifacts into the local workspace', () async {
      final root = Directory.systemTemp.createTempSync(
        'xworkmate-artifact-sync-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final result = await syncInlineArtifactsToLocalWorkspace(
        root: root,
        artifacts: const <GoTaskServiceArtifact>[
          GoTaskServiceArtifact(
            relativePath: 'reports/weekly.docx',
            label: 'weekly.docx',
            contentType:
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            encoding: 'utf8',
            content: 'docx-bytes-placeholder',
            downloadUrl: '',
            sizeBytes: null,
            sha256: '',
          ),
        ],
      );

      expect(result.wroteArtifact, isTrue);
      expect(result.writtenFiles, hasLength(1));
      final file = File(result.writtenFiles.single);
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), 'docx-bytes-placeholder');
    });

    test(
      'sanitizes parent traversal and preserves nested relative paths',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'xworkmate-artifact-sanitize-',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });

        final result = await syncInlineArtifactsToLocalWorkspace(
          root: root,
          artifacts: const <GoTaskServiceArtifact>[
            GoTaskServiceArtifact(
              relativePath: '../unsafe/../../slides/demo.pptx',
              label: 'demo.pptx',
              contentType:
                  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
              encoding: 'utf8',
              content: 'pptx-bytes-placeholder',
              downloadUrl: '',
              sizeBytes: null,
              sha256: '',
            ),
          ],
        );

        expect(
          result.writtenFiles.single,
          endsWith('/unsafe/slides/demo.pptx'),
        );
        expect(File('${root.path}/demo.pptx').existsSync(), isFalse);
      },
    );

    test('creates versioned files when the target path already exists', () async {
      final root = Directory.systemTemp.createTempSync(
        'xworkmate-artifact-version-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final original = File('${root.path}/table.xlsx');
      await original.writeAsString('v1');

      final first = await syncInlineArtifactsToLocalWorkspace(
        root: root,
        artifacts: const <GoTaskServiceArtifact>[
          GoTaskServiceArtifact(
            relativePath: 'table.xlsx',
            label: 'table.xlsx',
            contentType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            encoding: 'utf8',
            content: 'v2',
            downloadUrl: '',
            sizeBytes: null,
            sha256: '',
          ),
        ],
      );
      final second = await syncInlineArtifactsToLocalWorkspace(
        root: root,
        artifacts: const <GoTaskServiceArtifact>[
          GoTaskServiceArtifact(
            relativePath: 'table.xlsx',
            label: 'table.xlsx',
            contentType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            encoding: 'utf8',
            content: 'v3',
            downloadUrl: '',
            sizeBytes: null,
            sha256: '',
          ),
        ],
      );

      expect(first.writtenFiles.single, endsWith('/table.v2.xlsx'));
      expect(second.writtenFiles.single, endsWith('/table.v3.xlsx'));
      expect(await File(first.writtenFiles.single).readAsString(), 'v2');
      expect(await File(second.writtenFiles.single).readAsString(), 'v3');
    });

    test('decodes base64 inline content for binary-like artifacts', () async {
      final root = Directory.systemTemp.createTempSync(
        'xworkmate-artifact-base64-',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final payload = base64Encode(<int>[1, 2, 3, 4, 5]);
      final result = await syncInlineArtifactsToLocalWorkspace(
        root: root,
        artifacts: <GoTaskServiceArtifact>[
          GoTaskServiceArtifact(
            relativePath: 'images/resized.png',
            label: 'resized.png',
            contentType: 'image/png',
            encoding: 'base64',
            content: payload,
            downloadUrl: '',
            sizeBytes: 5,
            sha256: '',
          ),
        ],
      );

      expect(await File(result.writtenFiles.single).readAsBytes(), <int>[
        1,
        2,
        3,
        4,
        5,
      ]);
    });
  });
}
