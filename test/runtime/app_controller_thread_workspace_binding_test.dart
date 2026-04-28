import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_controller_desktop_runtime_coordination_impl.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'keeps local workspace binding separate from remote execution workspace',
    () {
      final controller = AppController();
      addTearDown(controller.dispose);

      final localWorkspace = Directory.systemTemp.createTempSync(
        'xworkmate-local-workspace-',
      );
      final remoteWorkspace = Directory.systemTemp.createTempSync(
        'xworkmate-remote-workspace-',
      );
      addTearDown(() {
        localWorkspace.deleteSync(recursive: true);
        remoteWorkspace.deleteSync(recursive: true);
      });

      controller.upsertTaskThreadInternal(
        'session-1',
        workspaceBinding: WorkspaceBinding(
          workspaceId: 'session-1',
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: localWorkspace.path,
          displayPath: localWorkspace.path,
          writable: true,
        ),
        lastRemoteWorkingDirectory: remoteWorkspace.path,
        lastRemoteWorkspaceRefKind: WorkspaceRefKind.remotePath,
      );

      expect(
        assistantWorkingDirectoryForSessionRuntimeInternal(
          controller,
          'session-1',
        ),
        remoteWorkspace.path,
      );
      expect(
        resolveLocalAssistantWorkingDirectoryForSessionRuntimeInternal(
          controller,
          'session-1',
        ),
        localWorkspace.path,
      );
    },
  );

  test('writes inline ACP artifacts into the local thread workspace', () async {
    final controller = AppController();
    addTearDown(controller.dispose);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-artifact-workspace-',
    );
    addTearDown(() async {
      if (await localWorkspace.exists()) {
        await localWorkspace.delete(recursive: true);
      }
    });

    controller.upsertTaskThreadInternal(
      'session-1',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'session-1',
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localWorkspace.path,
        displayPath: localWorkspace.path,
        writable: true,
      ),
    );

    final result = GoTaskServiceResult(
      success: true,
      message: 'hello',
      turnId: 'turn-1',
      raw: <String, dynamic>{
        'artifacts': <Map<String, dynamic>>[
          <String, dynamic>{
            'relativePath': 'notes/hello.txt',
            'content': 'artifact body',
            'contentType': 'text/plain',
          },
        ],
      },
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );

    await controller.persistGoTaskArtifactsForSessionInternal(
      'session-1',
      result,
    );

    final artifact = File('${localWorkspace.path}/notes/hello.txt');
    expect(await artifact.readAsString(), 'artifact body');
    expect(
      controller
          .requireTaskThreadForSessionInternal('session-1')
          .lastArtifactSyncStatus,
      'synced',
    );
  });
}
