import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'empty-artifact fallback records only final files, not temp/process noise',
    () async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      final localWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-artifact-noise-isolation-',
      );
      addTearDown(() async {
        if (await localWorkspace.exists()) {
          await localWorkspace.delete(recursive: true);
        }
      });

      final startedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Final deliverables produced during the run.
      await Directory('${localWorkspace.path}/renders').create();
      await File(
        '${localWorkspace.path}/renders/final-report.mp4',
      ).writeAsBytes(<int>[1, 2, 3]);
      await File(
        '${localWorkspace.path}/report.md',
      ).writeAsString('final report');

      // Temp/process noise produced during the same run.
      await Directory('${localWorkspace.path}/tmp').create();
      await File(
        '${localWorkspace.path}/tmp/scratch.bin',
      ).writeAsBytes(<int>[9]);
      await Directory('${localWorkspace.path}/.cache').create();
      await File(
        '${localWorkspace.path}/.cache/index.json',
      ).writeAsString('{}');
      await Directory('${localWorkspace.path}/logs').create();
      await File(
        '${localWorkspace.path}/logs/run.txt',
      ).writeAsString('log line');
      await File(
        '${localWorkspace.path}/draft.tmp',
      ).writeAsString('in progress');
      await File(
        '${localWorkspace.path}/render.log',
      ).writeAsString('render output');
      await File(
        '${localWorkspace.path}/report.md~',
      ).writeAsString('editor backup');
      await File('${localWorkspace.path}/.DS_Store').writeAsBytes(<int>[0]);

      controller.upsertTaskThreadInternal(
        'unit-fixture-noise-isolation',
        workspaceBinding: WorkspaceBinding(
          workspaceId: 'unit-fixture-noise-isolation',
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: localWorkspace.path,
          displayPath: localWorkspace.path,
          writable: true,
        ),
        lifecycleStatus: 'running',
        lastRunAtMs: startedAtMs,
        lastResultCode: 'running',
      );

      const result = GoTaskServiceResult(
        success: true,
        message: 'task completed',
        turnId: 'turn-noise-1',
        raw: <String, dynamic>{},
        errorMessage: '',
        resolvedModel: '',
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      await controller.persistGoTaskArtifactsForSessionInternal(
        'unit-fixture-noise-isolation',
        result,
      );

      final thread = controller.requireTaskThreadForSessionInternal(
        'unit-fixture-noise-isolation',
      );
      expect(thread.lastArtifactSyncStatus, 'synced');
      expect(thread.lastTaskArtifactRelativePaths, <String>[
        'renders/final-report.mp4',
        'report.md',
      ]);
    },
  );
}
