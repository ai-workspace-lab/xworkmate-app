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
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
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
        localWorkspace.path,
      );
      expect(
        resolveLocalAssistantWorkingDirectoryForSessionRuntimeInternal(
          controller,
          'session-1',
        ),
        localWorkspace.path,
      );
      expect(
        assistantRemoteWorkingDirectoryHintForSessionRuntimeInternal(
          controller,
          'session-1',
        ),
        remoteWorkspace.path,
      );
    },
  );

  test('writes inline ACP artifacts into the local thread workspace', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
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
    await controller.persistGoTaskArtifactsForSessionInternal(
      'session-1',
      result,
    );
    final versionedArtifact = File('${localWorkspace.path}/notes/hello.v2.txt');
    expect(await versionedArtifact.readAsString(), 'artifact body');
    final snapshot = await controller.loadAssistantArtifactSnapshot(
      sessionKey: 'session-1',
    );
    expect(
      snapshot.fileEntries.map((entry) => entry.relativePath),
      contains('notes/hello.txt'),
    );
    expect(
      snapshot.fileEntries.map((entry) => entry.relativePath),
      contains('notes/hello.v2.txt'),
    );
    expect(
      controller
          .requireTaskThreadForSessionInternal('session-1')
          .lastArtifactSyncStatus,
      'synced',
    );
  });

  test(
    'downloads bridge URL artifacts into the local thread workspace',
    () async {
      String observedAuthorization = '';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        observedAuthorization =
            request.headers.value(HttpHeaders.authorizationHeader) ?? '';
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.text
          ..write('downloaded artifact body');
        await request.response.close();
      });

      final controller = AppController(
        environmentOverride: const <String, String>{
          'BRIDGE_AUTH_TOKEN': 'bridge-token',
        },
      );
      addTearDown(controller.dispose);

      final localWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-download-artifact-workspace-',
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
              'relativePath': 'reports/download.txt',
              'downloadUrl':
                  'http://xworkmate-bridge.svc.plus:${server.port}/artifact/download.txt',
              'contentType': 'text/plain',
            },
          ],
        },
        errorMessage: '',
        resolvedModel: '',
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      final proxyClient = HttpClient()
        ..findProxy = (_) => 'PROXY 127.0.0.1:${server.port}';
      await HttpOverrides.runZoned(() async {
        await controller.persistGoTaskArtifactsForSessionInternal(
          'session-1',
          result,
        );
      }, createHttpClient: (_) => proxyClient);

      final artifact = File('${localWorkspace.path}/reports/download.txt');
      expect(await artifact.readAsString(), 'downloaded artifact body');
      expect(observedAuthorization, 'Bearer bridge-token');
      final snapshot = await controller.loadAssistantArtifactSnapshot(
        sessionKey: 'session-1',
      );
      expect(
        snapshot.fileEntries.map((entry) => entry.relativePath),
        contains('reports/download.txt'),
      );
      expect(
        controller
            .requireTaskThreadForSessionInternal('session-1')
            .lastArtifactSyncStatus,
        'synced',
      );
    },
  );

  test('skips download URL artifacts outside the bridge host', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{
        'BRIDGE_AUTH_TOKEN': 'bridge-token',
      },
    );
    addTearDown(controller.dispose);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-skipped-download-artifact-workspace-',
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
            'relativePath': 'reports/download.txt',
            'downloadUrl': 'https://example.invalid/artifact/download.txt',
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

    expect(
      await File('${localWorkspace.path}/reports/download.txt').exists(),
      isFalse,
    );
    expect(
      controller
          .requireTaskThreadForSessionInternal('session-1')
          .lastArtifactSyncStatus,
      'no-inline-content',
    );
  });
}
