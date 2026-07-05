import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/app/app_controller_desktop_runtime_coordination_impl.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_binding.dart';
import 'package:xworkmate/runtime/assistant_artifacts.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test(
    'startup removes known test task pollution and preserves real history',
    () async {
      final storeRoot = await Directory.systemTemp.createTemp(
        'xworkmate-test-pollution-store-',
      );
      addTearDown(() async {
        if (await storeRoot.exists()) {
          await storeRoot.delete(recursive: true);
        }
      });

      final store = _RecordingSecureConfigStore(rootPath: storeRoot.path);
      await store.initialize();
      final pollutedSessionKey = _pollutedUnitSessionKey();
      const realSessionKey = 'real-history-session';
      await store.saveTaskThreads(<TaskThread>[
        _persistedThread(
          sessionKey: pollutedSessionKey,
          title: 'Unit test fixture',
          workspacePath:
              '${storeRoot.path}/home/.xworkmate/threads/${_pollutedUnitWorkspaceName()}',
        ),
        _persistedThread(
          sessionKey: realSessionKey,
          title: 'Real history task',
          workspacePath:
              '${storeRoot.path}/home/.xworkmate/threads/real-history-session',
        ),
      ]);
      await store.saveAppUiState(
        AppUiState.defaults().copyWith(
          assistantLastSessionKey: pollutedSessionKey,
        ),
      );

      final controller = AppController(
        store: store,
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await _waitForControllerInitialization(controller);

      expect(
        controller.taskThreadForSessionInternal(pollutedSessionKey),
        isNull,
      );
      expect(
        controller.assistantSessions.map((item) => item.key),
        allOf(contains(realSessionKey), isNot(contains(pollutedSessionKey))),
      );
      expect(controller.currentSessionKey, isNot(pollutedSessionKey));
      expect(
        controller.appUiState.assistantLastSessionKey,
        isNot(pollutedSessionKey),
      );
      expect(store.clearAssistantLocalStateCalled, isFalse);

      final persistedThreadIds = (await store.loadTaskThreads())
          .map((thread) => thread.threadId)
          .toList(growable: false);
      expect(persistedThreadIds, <String>[realSessionKey]);
      expect(
        (await store.loadAppUiState()).assistantLastSessionKey,
        isNot(pollutedSessionKey),
      );
    },
  );

  test('source tree does not contain known real draft test fixtures', () async {
    final blocked = <String>[
      _pollutedUnitSessionKey(),
      _pollutedTestSessionKey(),
      _pollutedUnitWorkspaceName(),
      _pollutedTestWorkspaceName(),
    ];
    final roots = <String>['lib', 'test', 'scripts', 'docs'];
    final violations = <String>[];
    for (final root in roots) {
      final directory = Directory(root);
      if (!await directory.exists()) {
        continue;
      }
      await for (final entity in directory.list(recursive: true)) {
        if (entity is! File) {
          continue;
        }
        final path = entity.path;
        if (path.contains('/build/') || path.contains('/.dart_tool/')) {
          continue;
        }
        String content;
        try {
          content = await entity.readAsString();
        } catch (_) {
          continue;
        }
        for (final fixture in blocked) {
          if (content.contains(fixture)) {
            violations.add('$path contains $fixture');
          }
        }
      }
    }

    expect(violations, isEmpty);
  });

  test(
    'empty environment override keeps thread workspaces out of real HOME',
    () async {
      final realHome = Platform.environment['HOME']?.trim() ?? '';
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('unit-fixture-task-a');

      expect(controller.userHomeDirectory, isNot(isEmpty));
      if (realHome.isNotEmpty) {
        expect(controller.userHomeDirectory, isNot(realHome));
      }
      expect(
        controller.localThreadWorkspacePathInternal('unit-fixture-task-a'),
        isNot(contains('$realHome/.xworkmate/threads/unit-fixture-task-a')),
      );
      expect(
        controller.localThreadWorkspaceDisplayPathInternal(
          'unit-fixture-task-a',
        ),
        '\$HOME/.xworkmate/threads/unit-fixture-task-a',
      );
    },
  );

  test('does not expose gateway chat messages from another session', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    await controller.sessionsController.switchSession('current-session');
    controller.localSessionMessagesInternal['current-session'] =
        const <GatewayChatMessage>[
          GatewayChatMessage(
            id: 'current-local',
            role: 'assistant',
            text: 'current session message',
            timestampMs: 1,
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
        ];
    controller.chatController
      ..sessionKeyInternal = 'stale-session'
      ..messagesInternal = const <GatewayChatMessage>[
        GatewayChatMessage(
          id: 'stale-gateway',
          role: 'assistant',
          text: 'stale gateway message',
          timestampMs: 2,
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      ]
      ..streamingAssistantTextInternal = 'stale streaming message';

    expect(
      controller.chatMessages.map((message) => message.text),
      contains('current session message'),
    );
    expect(
      controller.chatMessages.map((message) => message.text),
      isNot(contains('stale gateway message')),
    );
    expect(
      controller.chatMessages.map((message) => message.text),
      isNot(contains('stale streaming message')),
    );
  });

  test('switchSession resets the gateway chat session boundary', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    await controller.sessionsController.switchSession('stale-session');
    controller.chatController
      ..sessionKeyInternal = 'stale-session'
      ..messagesInternal = const <GatewayChatMessage>[
        GatewayChatMessage(
          id: 'stale-gateway',
          role: 'assistant',
          text: 'stale gateway message',
          timestampMs: 1,
          toolCallId: null,
          toolName: null,
          stopReason: null,
          pending: false,
          error: false,
        ),
      ];

    await controller.switchSession('current-session');

    expect(controller.currentSessionKey, 'current-session');
    expect(controller.chatController.sessionKey, 'current-session');
    expect(
      controller.chatMessages.map((message) => message.text),
      isNot(contains('stale gateway message')),
    );
  });

  test(
    'converges managed local thread workspaces to the user home root',
    () async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      final home = await Directory.systemTemp.createTemp(
        'xworkmate-home-thread-root-',
      );
      final oldWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-app-worktree-thread-root-',
      );
      addTearDown(() async {
        if (await home.exists()) {
          await home.delete(recursive: true);
        }
        if (await oldWorkspace.exists()) {
          await oldWorkspace.delete(recursive: true);
        }
      });
      controller.resolvedUserHomeDirectoryInternal = home.path;

      const sessionKey = 'draft-1778207741322';
      final oldThreadWorkspace = Directory(
        '${oldWorkspace.path}/.xworkmate/threads/$sessionKey',
      );
      await oldThreadWorkspace.create(recursive: true);

      controller.upsertTaskThreadInternal(
        sessionKey,
        workspaceBinding: WorkspaceBinding(
          workspaceId: sessionKey,
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: oldThreadWorkspace.path,
          displayPath: oldThreadWorkspace.path,
          writable: true,
        ),
        messages: const <GatewayChatMessage>[
          GatewayChatMessage(
            id: 'assistant-1',
            role: 'assistant',
            text: 'kept message',
            timestampMs: 1,
            toolCallId: null,
            toolName: null,
            stopReason: null,
            pending: false,
            error: false,
          ),
        ],
        lastRemoteWorkingDirectory: '/remote/thread/workspace',
        lastRemoteWorkspaceRefKind: WorkspaceRefKind.remotePath,
      );

      await controller.ensureDesktopTaskThreadBindingInternal(sessionKey);

      final expectedWorkspace = '${home.path}/.xworkmate/threads/$sessionKey';
      final thread = controller.requireTaskThreadForSessionInternal(sessionKey);
      expect(thread.workspaceBinding.workspacePath, expectedWorkspace);
      expect(
        thread.workspaceBinding.displayPath,
        '\$HOME/.xworkmate/threads/$sessionKey',
      );
      expect(Directory(expectedWorkspace).existsSync(), isTrue);
      expect(thread.lastRemoteWorkingDirectory, '/remote/thread/workspace');
      expect(thread.messages.single.text, 'kept message');
    },
  );

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
        'unit-fixture-task-a',
        workspaceBinding: WorkspaceBinding(
          workspaceId: 'unit-fixture-task-a',
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
          'unit-fixture-task-a',
        ),
        localWorkspace.path,
      );
      expect(
        resolveLocalAssistantWorkingDirectoryForSessionRuntimeInternal(
          controller,
          'unit-fixture-task-a',
        ),
        localWorkspace.path,
      );
      expect(
        assistantRemoteWorkingDirectoryHintForSessionRuntimeInternal(
          controller,
          'unit-fixture-task-a',
        ),
        remoteWorkspace.path,
      );
    },
  );

  test('runtime session keys do not resolve to app task workspaces', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    final home = await Directory.systemTemp.createTemp(
      'xworkmate-runtime-key-workspace-',
    );
    addTearDown(() async {
      if (await home.exists()) {
        await home.delete(recursive: true);
      }
    });
    controller.resolvedUserHomeDirectoryInternal = home.path;

    controller.initializeAssistantThreadContext(
      'draft:test-workspace-task',
      executionTarget: AssistantExecutionTarget.gateway,
      messageViewMode: AssistantMessageViewMode.rendered,
    );

    expect(controller.localThreadWorkspacePathInternal('session-1'), isEmpty);
    expect(
      controller.localThreadWorkspaceDisplayPathInternal('session-1'),
      isEmpty,
    );
    expect(controller.assistantWorkspacePathForSession('session-1'), isEmpty);
    expect(
      controller.assistantWorkspacePathForSession('draft:test-workspace-task'),
      endsWith('/.xworkmate/threads/draft-test-workspace-task'),
    );
  });

  test(
    'mobile target selection keeps a complete remote workspace when local home is unavailable',
    () async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
        initialGatewayProviderCatalog: <SingleAgentProvider>[
          SingleAgentProvider.openclaw.copyWith(
            supportedTargets: const <AssistantExecutionTarget>[
              AssistantExecutionTarget.gateway,
            ],
          ),
        ],
        initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
          AssistantExecutionTarget.agent,
          AssistantExecutionTarget.gateway,
        ],
      );
      addTearDown(controller.dispose);
      controller.resolvedUserHomeDirectoryInternal = '';

      await controller.ensureActiveAssistantThreadInternal();
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.gateway,
      );

      final record = controller.taskThreadForSessionInternal(
        controller.currentSessionKey,
      );
      expect(controller.currentAssistantExecutionTarget.isGateway, isTrue);
      expect(record?.workspaceBinding.isComplete, isTrue);
      expect(record?.workspaceBinding.workspaceKind, WorkspaceKind.remoteFs);
      expect(
        record?.workspaceBinding.workspacePath,
        contains('/threads/${controller.currentSessionKey}'),
      );
      expect(
        controller.assistantWorkingDirectoryForSessionInternal(
          controller.currentSessionKey,
        ),
        record?.workspaceBinding.workspacePath,
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
      'unit-fixture-task-a',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-a',
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
      'unit-fixture-task-a',
      result,
    );

    final artifact = File('${localWorkspace.path}/notes/hello.txt');
    expect(await artifact.readAsString(), 'artifact body');
    await controller.persistGoTaskArtifactsForSessionInternal(
      'unit-fixture-task-a',
      result,
    );
    final versionedArtifact = File('${localWorkspace.path}/notes/hello.v2.txt');
    expect(await versionedArtifact.readAsString(), 'artifact body');
    final snapshot = await controller.loadAssistantArtifactSnapshot(
      sessionKey: 'unit-fixture-task-a',
    );
    expect(snapshot.resultEntries.map((entry) => entry.relativePath), <String>[
      'notes/hello.v2.txt',
    ]);
    expect(snapshot.fileEntries.map((entry) => entry.relativePath), <String>[
      'notes/hello.v2.txt',
    ]);
    expect(
      controller
          .requireTaskThreadForSessionInternal('unit-fixture-task-a')
          .lastArtifactSyncStatus,
      'synced',
    );
  });

  test('keeps task artifacts scoped to the current run', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-isolated-artifact-workspace-',
    );
    addTearDown(() async {
      if (await localWorkspace.exists()) {
        await localWorkspace.delete(recursive: true);
      }
    });
    final staleArtifact = File('${localWorkspace.path}/old-task-report.md');
    await staleArtifact.writeAsString('stale task output');

    controller.upsertTaskThreadInternal(
      'unit-fixture-task-a',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-a',
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localWorkspace.path,
        displayPath: localWorkspace.path,
        writable: true,
      ),
    );

    final result = GoTaskServiceResult(
      success: true,
      message: 'hello',
      turnId: 'turn-2',
      raw: <String, dynamic>{
        'artifacts': <Map<String, dynamic>>[
          <String, dynamic>{
            'relativePath': 'current-task-report.md',
            'content': 'current task output',
            'contentType': 'text/markdown',
          },
        ],
      },
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );

    await controller.persistGoTaskArtifactsForSessionInternal(
      'unit-fixture-task-a',
      result,
    );

    final snapshot = await controller.loadAssistantArtifactSnapshot(
      sessionKey: 'unit-fixture-task-a',
    );
    final currentRelativePaths = snapshot.resultEntries
        .map((entry) => entry.relativePath)
        .toList(growable: false);
    expect(currentRelativePaths, <String>['current-task-report.md']);
    expect(snapshot.fileEntries.map((entry) => entry.relativePath), <String>[
      'current-task-report.md',
    ]);

    final stalePreview = await controller.loadAssistantArtifactPreview(
      AssistantArtifactEntry(
        id: '${localWorkspace.path}::old-task-report.md',
        label: 'old-task-report.md',
        relativePath: 'old-task-report.md',
        kind: AssistantArtifactEntryKind.file,
        mimeType: 'text/markdown',
        previewable: true,
        workspacePath: localWorkspace.path,
      ),
      sessionKey: 'unit-fixture-task-a',
    );
    expect(stalePreview.kind, AssistantArtifactPreviewKind.empty);
    expect(stalePreview.content, isEmpty);
  });

  test('syncs existing workspace directory artifacts recursively', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-recursive-artifact-workspace-',
    );
    addTearDown(() async {
      if (await localWorkspace.exists()) {
        await localWorkspace.delete(recursive: true);
      }
    });
    await Directory(
      '${localWorkspace.path}/assets/images/chapters',
    ).create(recursive: true);
    await File(
      '${localWorkspace.path}/assets/images/cover.png',
    ).writeAsBytes(<int>[1, 2, 3]);
    await File(
      '${localWorkspace.path}/assets/images/chapters/chapter-1.png',
    ).writeAsBytes(<int>[4, 5, 6]);
    await File(
      '${localWorkspace.path}/chapters/codex-chapter-breakdown.md',
    ).create(recursive: true);
    await Directory('${localWorkspace.path}/dist').create(recursive: true);
    await File(
      '${localWorkspace.path}/dist/账户与身份安全演进史-GPT混排最终版.pdf',
    ).writeAsBytes(<int>[7, 8, 9]);

    controller.upsertTaskThreadInternal(
      'unit-fixture-task-a',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-a',
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localWorkspace.path,
        displayPath: localWorkspace.path,
        writable: true,
      ),
    );

    final result = GoTaskServiceResult(
      success: true,
      message: 'generated files',
      turnId: 'turn-recursive',
      raw: <String, dynamic>{
        'artifacts': <Map<String, dynamic>>[
          <String, dynamic>{'relativePath': 'assets/images/'},
          <String, dynamic>{
            'relativePath': 'chapters/codex-chapter-breakdown.md',
          },
        ],
      },
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );

    await controller.persistGoTaskArtifactsForSessionInternal(
      'unit-fixture-task-a',
      result,
    );

    final thread = controller.requireTaskThreadForSessionInternal(
      'unit-fixture-task-a',
    );
    expect(thread.lastArtifactSyncStatus, 'synced');
    expect(thread.lastTaskArtifactRelativePaths, <String>[
      'assets/images/chapters/chapter-1.png',
      'assets/images/cover.png',
      'chapters/codex-chapter-breakdown.md',
    ]);
    final snapshot = await controller.loadAssistantArtifactSnapshot(
      sessionKey: 'unit-fixture-task-a',
    );
    expect(
      snapshot.resultEntries.map((entry) => entry.relativePath),
      containsAll(<String>[
        'assets/images/chapters/chapter-1.png',
        'assets/images/cover.png',
        'chapters/codex-chapter-breakdown.md',
      ]),
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
        'unit-fixture-task-a',
        workspaceBinding: WorkspaceBinding(
          workspaceId: 'unit-fixture-task-a',
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

      final clientFactory = _proxiedClientFactory(server.port);
      await HttpOverrides.runZoned(() async {
        await controller.persistGoTaskArtifactsForSessionInternal(
          'unit-fixture-task-a',
          result,
        );
      }, createHttpClient: clientFactory);

      final artifact = File('${localWorkspace.path}/reports/download.txt');
      expect(await artifact.readAsString(), 'downloaded artifact body');
      expect(observedAuthorization, 'Bearer bridge-token');
      final snapshot = await controller.loadAssistantArtifactSnapshot(
        sessionKey: 'unit-fixture-task-a',
      );
      expect(
        snapshot.fileEntries.map((entry) => entry.relativePath),
        contains('reports/download.txt'),
      );
      expect(
        controller
            .requireTaskThreadForSessionInternal('unit-fixture-task-a')
            .lastArtifactSyncStatus,
        'synced',
      );
    },
  );

  test(
    'syncs bridge OpenClaw download URL artifacts into the draft task workspace',
    () async {
      String observedAuthorization = '';
      String observedRelativePath = '';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        observedAuthorization =
            request.headers.value(HttpHeaders.authorizationHeader) ?? '';
        observedRelativePath =
            request.uri.queryParameters['relativePath']?.trim() ?? '';
        expect(request.uri.path, '/artifacts/openclaw/download');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..add(<int>[0x41, 0x52, 0x54, 0x49, 0x46, 0x41, 0x43, 0x54]);
        await request.response.close();
      });

      final controller = AppController(
        environmentOverride: const <String, String>{
          'BRIDGE_AUTH_TOKEN': 'bridge-token',
        },
      );
      addTearDown(controller.dispose);

      final baseWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-app-task-workspace-',
      );
      addTearDown(() async {
        if (await baseWorkspace.exists()) {
          await baseWorkspace.delete(recursive: true);
        }
      });

      const sessionKey = 'draft-1777962850788';
      final taskWorkspace = Directory(
        '${baseWorkspace.path}/.xworkmate/threads/$sessionKey',
      );
      controller.upsertTaskThreadInternal(
        sessionKey,
        workspaceBinding: WorkspaceBinding(
          workspaceId: sessionKey,
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: taskWorkspace.path,
          displayPath: taskWorkspace.path,
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
              'relativePath': 'exports/openclaw.bin',
              'downloadUrl':
                  'http://xworkmate-bridge.svc.plus:${server.port}/artifacts/openclaw/download'
                  '?sessionKey=$sessionKey&runId=run-1&relativePath=exports%2Fopenclaw.bin'
                  '&expires=9999999999&sig=test-signature',
              'contentType': 'application/octet-stream',
              'sizeBytes': 8,
              'sha256':
                  '7fbd7ef36fdd97293aa5b3bcd597146101d3ea9a12b271ed0c88bdca25b63d12',
            },
          ],
        },
        errorMessage: '',
        resolvedModel: '',
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      final clientFactory = _proxiedClientFactory(server.port);
      await HttpOverrides.runZoned(() async {
        await controller.persistGoTaskArtifactsForSessionInternal(
          sessionKey,
          result,
        );
      }, createHttpClient: clientFactory);

      final artifact = File('${taskWorkspace.path}/exports/openclaw.bin');
      expect(await artifact.readAsBytes(), <int>[
        0x41,
        0x52,
        0x54,
        0x49,
        0x46,
        0x41,
        0x43,
        0x54,
      ]);
      expect(observedAuthorization, 'Bearer bridge-token');
      expect(observedRelativePath, 'exports/openclaw.bin');

      final thread = controller.requireTaskThreadForSessionInternal(sessionKey);
      expect(thread.workspaceBinding.workspacePath, taskWorkspace.path);
      expect(thread.lastArtifactSyncStatus, 'synced');
      expect(thread.lastArtifactSyncAtMs, greaterThan(0));

      final snapshot = await controller.loadAssistantArtifactSnapshot(
        sessionKey: sessionKey,
      );
      expect(
        snapshot.fileEntries.map((entry) => entry.relativePath),
        contains('exports/openclaw.bin'),
      );
    },
  );

  test(
    'refreshing an empty artifact snapshot backfills OpenClaw task artifacts from the remote workspace hint',
    () async {
      late OpenClawTaskAssociation observedAssociation;
      final goTaskClient = _ArtifactBackfillGoTaskServiceClient(
        onGetTask: (association) {
          observedAssociation = association;
        },
      );
      final controller = AppController(
        environmentOverride: const <String, String>{},
        goTaskServiceClient: goTaskClient,
      );
      addTearDown(controller.dispose);

      final taskWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-remote-backfill-workspace-',
      );
      addTearDown(() async {
        if (await taskWorkspace.exists()) {
          await taskWorkspace.delete(recursive: true);
        }
      });

      const sessionKey = 'draft-sample-sync';
      controller.upsertTaskThreadInternal(
        sessionKey,
        workspaceBinding: WorkspaceBinding(
          workspaceId: sessionKey,
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: taskWorkspace.path,
          displayPath: taskWorkspace.path,
          writable: true,
        ),
        lastRemoteWorkingDirectory:
            '/home/ubuntu/.openclaw/workspace/tasks/'
            'agent_main_draft_sample-sync/turn-sample',
        lastArtifactSyncStatus: 'no-artifacts',
        lastTaskArtifactRelativePaths: const <String>[],
      );

      final snapshot = await controller.loadAssistantArtifactSnapshot(
        sessionKey: sessionKey,
      );

      expect(observedAssociation.appThreadKey, 'draft:sample-sync');
      expect(
        observedAssociation.openclawSessionKey,
        'agent:main:draft:sample-sync',
      );
      expect(observedAssociation.runId, 'turn-sample');
      expect(
        snapshot.fileEntries.map((entry) => entry.relativePath),
        contains('ai-news-report.md'),
      );
      expect(
        await File('${taskWorkspace.path}/ai-news-report.md').readAsString(),
        '# AI news\n',
      );
      final thread = controller.requireTaskThreadForSessionInternal(sessionKey);
      expect(thread.lastArtifactSyncStatus, 'synced');
      expect(thread.openClawTaskAssociation?.runId, 'turn-sample');
    },
  );

  test(
    'refreshing an empty artifact snapshot backfills completed OpenClaw task artifacts from recorded association',
    () async {
      late OpenClawTaskAssociation observedAssociation;
      final goTaskClient = _ArtifactBackfillGoTaskServiceClient(
        onGetTask: (association) {
          observedAssociation = association;
        },
      );
      final controller = AppController(
        environmentOverride: const <String, String>{},
        goTaskServiceClient: goTaskClient,
      );
      addTearDown(controller.dispose);

      final taskWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-completed-association-backfill-',
      );
      addTearDown(() async {
        if (await taskWorkspace.exists()) {
          await taskWorkspace.delete(recursive: true);
        }
      });

      const sessionKey = 'draft-completed-sync';
      const runId = 'turn-completed';
      const openClawSessionKey = 'agent:main:draft:completed-sync';
      final completedResult = GoTaskServiceResult(
        success: true,
        message: 'completed without inline artifacts',
        turnId: runId,
        raw: <String, dynamic>{
          'success': true,
          'status': 'completed',
          'sessionId': sessionKey,
          'threadId': sessionKey,
          'turnId': runId,
          'runId': runId,
          'artifactScope': 'tasks/$openClawSessionKey/$runId',
          'artifactDirectory':
              '/home/ubuntu/.openclaw/workspace/tasks/$openClawSessionKey/$runId',
          'gatewayProviderId': 'openclaw',
          'appThreadKey': 'draft:completed-sync',
          'openclawSessionKey': openClawSessionKey,
        },
        errorMessage: '',
        resolvedModel: '',
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      controller.upsertTaskThreadInternal(
        sessionKey,
        workspaceBinding: WorkspaceBinding(
          workspaceId: sessionKey,
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: taskWorkspace.path,
          displayPath: taskWorkspace.path,
          writable: true,
        ),
        openClawTaskAssociation: completedResult.openClawTaskAssociation,
        lastRemoteWorkingDirectory: taskWorkspace.path,
        lastArtifactSyncStatus: 'no-artifacts',
        lastTaskArtifactRelativePaths: const <String>[],
      );

      final snapshot = await controller.loadAssistantArtifactSnapshot(
        sessionKey: sessionKey,
      );

      expect(observedAssociation.runId, runId);
      expect(observedAssociation.openclawSessionKey, openClawSessionKey);
      expect(
        snapshot.fileEntries.map((entry) => entry.relativePath),
        contains('ai-news-report.md'),
      );
      final thread = controller.requireTaskThreadForSessionInternal(sessionKey);
      expect(thread.lastArtifactSyncStatus, 'synced');
      expect(thread.openClawTaskAssociation?.status, 'completed');
    },
  );

  test(
    'refreshing a partial artifact snapshot keeps backfilling OpenClaw task artifacts',
    () async {
      var getTaskCount = 0;
      late OpenClawTaskAssociation observedAssociation;
      final goTaskClient = _ArtifactBackfillGoTaskServiceClient(
        onGetTask: (association) {
          getTaskCount += 1;
          observedAssociation = association;
        },
      );
      final controller = AppController(
        environmentOverride: const <String, String>{},
        goTaskServiceClient: goTaskClient,
      );
      addTearDown(controller.dispose);

      final taskWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-partial-association-backfill-',
      );
      addTearDown(() async {
        if (await taskWorkspace.exists()) {
          await taskWorkspace.delete(recursive: true);
        }
      });
      await Directory(
        '${taskWorkspace.path}/assets/images',
      ).create(recursive: true);
      await File(
        '${taskWorkspace.path}/assets/images/09-AI-Agent.v32.png',
      ).writeAsBytes(<int>[1, 2, 3]);

      const sessionKey = 'draft-partial-sync';
      const runId = 'turn-partial';
      const openClawSessionKey = 'agent:main:draft:partial-sync';
      controller.upsertTaskThreadInternal(
        sessionKey,
        workspaceBinding: WorkspaceBinding(
          workspaceId: sessionKey,
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: taskWorkspace.path,
          displayPath: taskWorkspace.path,
          writable: true,
        ),
        openClawTaskAssociation: const OpenClawTaskAssociation(
          sessionId: sessionKey,
          threadId: sessionKey,
          turnId: runId,
          runId: runId,
          artifactScope: 'tasks/$openClawSessionKey/$runId',
          artifactDirectory:
              '/home/ubuntu/.openclaw/workspace/tasks/$openClawSessionKey/$runId',
          gatewayProviderId: 'openclaw',
          startedAtMs: 1,
          status: 'completed',
          appThreadKey: 'draft:partial-sync',
          openclawSessionKey: openClawSessionKey,
        ),
        lastArtifactSyncStatus: 'partial',
        lastTaskArtifactRelativePaths: const <String>[
          'assets/images/09-AI-Agent.v32.png',
        ],
      );

      final snapshot = await controller.loadAssistantArtifactSnapshot(
        sessionKey: sessionKey,
      );

      expect(getTaskCount, 1);
      expect(observedAssociation.runId, runId);
      expect(
        snapshot.fileEntries.map((entry) => entry.relativePath),
        containsAll(<String>[
          'assets/images/09-AI-Agent.v32.png',
          'ai-news-report.md',
        ]),
      );
      expect(
        await File('${taskWorkspace.path}/ai-news-report.md').readAsString(),
        '# AI news\n',
      );
      final thread = controller.requireTaskThreadForSessionInternal(sessionKey);
      expect(thread.lastArtifactSyncStatus, 'synced');
      expect(thread.openClawTaskAssociation?.status, 'completed');
    },
  );

  test(
    'resumes bridge artifact downloads after a weak network disconnect',
    () async {
      final body = <int>[0x41, 0x52, 0x54, 0x49, 0x46, 0x41, 0x43, 0x54];
      final observedRanges = <String>[];
      var requestCount = 0;
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((socket) async {
        requestCount += 1;
        final requestBytes = <int>[];
        await for (final chunk in socket) {
          requestBytes.addAll(chunk);
          if (String.fromCharCodes(requestBytes).contains('\r\n\r\n')) {
            break;
          }
        }
        final rawRequest = String.fromCharCodes(requestBytes);
        final rangeLine = rawRequest
            .split('\r\n')
            .firstWhere(
              (line) => line.toLowerCase().startsWith('range:'),
              orElse: () => '',
            );
        observedRanges.add(
          rangeLine.replaceFirst(RegExp('^[Rr]ange:\\s*'), ''),
        );
        if (requestCount == 1) {
          socket.add(
            'HTTP/1.1 200 OK\r\n'
                    'Content-Type: application/octet-stream\r\n'
                    'Content-Length: 8\r\n'
                    '\r\n'
                .codeUnits,
          );
          socket.add(body.take(4).toList());
          await socket.flush();
          socket.destroy();
          return;
        }
        expect(rangeLine.toLowerCase(), 'range: bytes=4-');
        socket.add(
          'HTTP/1.1 206 Partial Content\r\n'
                  'Content-Type: application/octet-stream\r\n'
                  'Content-Range: bytes 4-7/8\r\n'
                  'Content-Length: 4\r\n'
                  '\r\n'
              .codeUnits,
        );
        socket.add(body.skip(4).toList());
        await socket.flush();
        await socket.close();
      });

      final controller = AppController(
        environmentOverride: const <String, String>{
          'BRIDGE_AUTH_TOKEN': 'bridge-token',
        },
      );
      addTearDown(controller.dispose);

      final localWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-resume-artifact-workspace-',
      );
      addTearDown(() async {
        if (await localWorkspace.exists()) {
          await localWorkspace.delete(recursive: true);
        }
      });
      controller.upsertTaskThreadInternal(
        'unit-fixture-task-a',
        workspaceBinding: WorkspaceBinding(
          workspaceId: 'unit-fixture-task-a',
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
              'relativePath': 'reports/resume.bin',
              'downloadUrl':
                  'http://xworkmate-bridge.svc.plus:${server.port}/artifacts/openclaw/download'
                  '?sessionKey=unit-fixture-task-a&runId=run-1&relativePath=reports%2Fresume.bin'
                  '&expires=9999999999&sig=test-signature',
              'contentType': 'application/octet-stream',
              'sizeBytes': body.length,
              'sha256': crypto.sha256.convert(body).toString(),
            },
          ],
        },
        errorMessage: '',
        resolvedModel: '',
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      final clientFactory = _proxiedClientFactory(server.port);
      await HttpOverrides.runZoned(() async {
        await controller.persistGoTaskArtifactsForSessionInternal(
          'unit-fixture-task-a',
          result,
        );
      }, createHttpClient: clientFactory);

      expect(requestCount, 2);
      expect(observedRanges, <String>['', 'bytes=4-']);
      expect(
        await File('${localWorkspace.path}/reports/resume.bin').readAsBytes(),
        body,
      );
      for (
        var attempt = 0;
        attempt < 1000 &&
            controller
                    .requireTaskThreadForSessionInternal('unit-fixture-task-a')
                    .lastArtifactSyncStatus !=
                'synced';
        attempt += 1
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        controller
            .requireTaskThreadForSessionInternal('unit-fixture-task-a')
            .lastArtifactSyncStatus,
        'synced',
      );
    },
  );

  test(
    'retries bridge artifact downloads up to five weak network attempts',
    () async {
      const body = 'download after retries';
      var requestCount = 0;
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((socket) async {
        requestCount += 1;
        final requestBytes = <int>[];
        await for (final chunk in socket) {
          requestBytes.addAll(chunk);
          if (String.fromCharCodes(requestBytes).contains('\r\n\r\n')) {
            break;
          }
        }
        if (requestCount < 5) {
          socket.destroy();
          return;
        }
        socket.add(
          'HTTP/1.1 200 OK\r\n'
                  'Content-Type: text/plain\r\n'
                  'Content-Length: ${body.length}\r\n'
                  '\r\n'
              .codeUnits,
        );
        socket.add(body.codeUnits);
        await socket.flush();
        await socket.close();
      });

      final controller = AppController(
        environmentOverride: const <String, String>{
          'BRIDGE_AUTH_TOKEN': 'bridge-token',
        },
      );
      addTearDown(controller.dispose);

      final localWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-retry-artifact-workspace-',
      );
      addTearDown(() async {
        if (await localWorkspace.exists()) {
          await localWorkspace.delete(recursive: true);
        }
      });
      controller.upsertTaskThreadInternal(
        'unit-fixture-task-a',
        workspaceBinding: WorkspaceBinding(
          workspaceId: 'unit-fixture-task-a',
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
              'relativePath': 'reports/retry.txt',
              'downloadUrl':
                  'http://xworkmate-bridge.svc.plus:${server.port}/retry.txt',
              'contentType': 'text/plain',
            },
          ],
        },
        errorMessage: '',
        resolvedModel: '',
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      final clientFactory = _proxiedClientFactory(server.port);
      await HttpOverrides.runZoned(() async {
        await controller.persistGoTaskArtifactsForSessionInternal(
          'unit-fixture-task-a',
          result,
        );
      }, createHttpClient: clientFactory);

      expect(requestCount, 5);
      expect(
        await File('${localWorkspace.path}/reports/retry.txt').readAsString(),
        body,
      );
      expect(
        controller
            .requireTaskThreadForSessionInternal('unit-fixture-task-a')
            .lastArtifactSyncStatus,
        'synced',
      );
    },
  );

  test('keeps syncing later artifacts when one download fails', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path.endsWith('/failed.txt')) {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('download ok');
      await request.response.close();
    });

    final controller = AppController(
      environmentOverride: const <String, String>{
        'BRIDGE_AUTH_TOKEN': 'bridge-token',
      },
    );
    addTearDown(controller.dispose);
    await _waitForControllerInitialization(controller);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-partial-artifact-workspace-',
    );
    addTearDown(() async {
      if (await localWorkspace.exists()) {
        await localWorkspace.delete(recursive: true);
      }
    });
    controller.upsertTaskThreadInternal(
      'unit-fixture-task-a',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-a',
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
            'relativePath': 'reports/inline.txt',
            'content': 'inline ok',
            'contentType': 'text/plain',
          },
          <String, dynamic>{
            'relativePath': 'reports/failed.txt',
            'downloadUrl':
                'http://xworkmate-bridge.svc.plus:${server.port}/failed.txt',
            'contentType': 'text/plain',
          },
          <String, dynamic>{
            'relativePath': 'reports/download.txt',
            'downloadUrl':
                'http://xworkmate-bridge.svc.plus:${server.port}/download.txt',
            'contentType': 'text/plain',
          },
        ],
      },
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );

    final clientFactory = _proxiedClientFactory(server.port);
    await HttpOverrides.runZoned(() async {
      await controller.persistGoTaskArtifactsForSessionInternal(
        'unit-fixture-task-a',
        result,
      );
    }, createHttpClient: clientFactory);

    expect(
      await File('${localWorkspace.path}/reports/inline.txt').readAsString(),
      'inline ok',
    );
    expect(
      await File('${localWorkspace.path}/reports/download.txt').readAsString(),
      'download ok',
    );
    expect(
      await File('${localWorkspace.path}/reports/failed.txt').exists(),
      isFalse,
    );
    final snapshot = await controller.loadAssistantArtifactSnapshot(
      sessionKey: 'unit-fixture-task-a',
    );
    expect(
      snapshot.fileEntries.map((entry) => entry.relativePath),
      containsAll(<String>['reports/inline.txt', 'reports/download.txt']),
    );
    expect(
      controller
          .requireTaskThreadForSessionInternal('unit-fixture-task-a')
          .lastArtifactSyncStatus,
      'partial',
    );
  });

  test('drops artifacts when size or sha256 validation fails', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('bad body');
      await request.response.close();
    });

    final controller = AppController(
      environmentOverride: const <String, String>{
        'BRIDGE_AUTH_TOKEN': 'bridge-token',
      },
    );
    addTearDown(controller.dispose);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-invalid-artifact-workspace-',
    );
    addTearDown(() async {
      if (await localWorkspace.exists()) {
        await localWorkspace.delete(recursive: true);
      }
    });
    controller.upsertTaskThreadInternal(
      'unit-fixture-task-a',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-a',
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
            'relativePath': 'reports/invalid.txt',
            'downloadUrl':
                'http://xworkmate-bridge.svc.plus:${server.port}/invalid.txt',
            'contentType': 'text/plain',
            'sizeBytes': 8,
            'sha256':
                '0000000000000000000000000000000000000000000000000000000000000000',
          },
        ],
      },
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );

    final clientFactory = _proxiedClientFactory(server.port);
    await HttpOverrides.runZoned(() async {
      await controller.persistGoTaskArtifactsForSessionInternal(
        'unit-fixture-task-a',
        result,
      );
    }, createHttpClient: clientFactory);

    expect(
      await File('${localWorkspace.path}/reports/invalid.txt').exists(),
      isFalse,
    );
    final leftovers = await localWorkspace
        .list(recursive: true)
        .where((entity) => entity.path.contains('.xworkmate-sync-'))
        .toList();
    expect(leftovers, isEmpty);
    expect(
      controller
          .requireTaskThreadForSessionInternal('unit-fixture-task-a')
          .lastArtifactSyncStatus,
      'download-failed',
    );
  });

  test(
    'records OpenClaw guard status without creating pseudo artifact files',
    () async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      final localWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-openclaw-guard-workspace-',
      );
      addTearDown(() async {
        if (await localWorkspace.exists()) {
          await localWorkspace.delete(recursive: true);
        }
      });
      controller.upsertTaskThreadInternal(
        'unit-fixture-task-a',
        workspaceBinding: WorkspaceBinding(
          workspaceId: 'unit-fixture-task-a',
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: localWorkspace.path,
          displayPath: localWorkspace.path,
          writable: true,
        ),
      );

      const result = GoTaskServiceResult(
        success: true,
        message:
            '未检测到 OpenClaw 本轮导出的实际文件。已阻止口头下载声明进入 artifacts 面板；请重新执行并要求 OpenClaw 在 workspace 中真实生成文件。',
        turnId: 'turn-1',
        raw: <String, dynamic>{'code': 'OPENCLAW_NO_EXPORTED_ARTIFACTS'},
        errorMessage: '',
        resolvedModel: '',
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      await controller.persistGoTaskArtifactsForSessionInternal(
        'unit-fixture-task-a',
        result,
      );

      expect(await localWorkspace.list(recursive: true).toList(), isEmpty);
      final thread = controller.requireTaskThreadForSessionInternal(
        'unit-fixture-task-a',
      );
      expect(thread.lastArtifactSyncStatus, 'no-artifacts');
      expect(thread.lastArtifactSyncAtMs, greaterThan(0));
    },
  );

  test('rejects artifacts matched by artifact-ignore policy', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-openclaw-placeholder-pdf-',
    );
    addTearDown(() async {
      if (await localWorkspace.exists()) {
        await localWorkspace.delete(recursive: true);
      }
    });
    controller.upsertTaskThreadInternal(
      'unit-fixture-task-a',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-a',
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localWorkspace.path,
        displayPath: localWorkspace.path,
        writable: true,
      ),
    );
    await File('${localWorkspace.path}/artifact-ignore.md').writeAsString(
      '```artifact-reject\n'
      'path=exports/final.pdf\n'
      'contentType=application/pdf\n'
      'contains=XWorkmate Task Artifact\n'
      'contains=Required extensions: pdf\n'
      'contains=TaskThread workspace context:\n'
      '```\n',
    );

    final placeholderBytes = utf8.encode(
      '%PDF-1.3\n'
      'BT /F1 14 Tf (XWorkmate Task Artifact) Tj '
      '(Required extensions: pdf) Tj '
      '(TaskThread workspace context:) Tj ET',
    );
    final result = GoTaskServiceResult(
      success: true,
      message:
          'OpenClaw final artifacts were written to the current task artifact scope: pdf.',
      turnId: 'turn-1',
      raw: <String, dynamic>{
        'artifactWarnings': <String>['agent.wait request timeout'],
        'artifacts': <Map<String, dynamic>>[
          <String, dynamic>{
            'relativePath': 'exports/final.pdf',
            'contentType': 'application/pdf',
            'encoding': 'base64',
            'content': base64Encode(placeholderBytes),
            'sizeBytes': placeholderBytes.length,
            'sha256': crypto.sha256.convert(placeholderBytes).toString(),
          },
        ],
      },
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );

    await controller.persistGoTaskArtifactsForSessionInternal(
      'unit-fixture-task-a',
      result,
    );

    expect(
      await File('${localWorkspace.path}/exports/final.pdf').exists(),
      isFalse,
    );
    final thread = controller.requireTaskThreadForSessionInternal(
      'unit-fixture-task-a',
    );
    expect(thread.lastArtifactSyncStatus, 'no-artifacts');
    expect(thread.lastTaskArtifactRelativePaths, isEmpty);
  });

  test(
    'keeps polling OpenClaw export after required artifact download fails',
    () async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      final localWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-openclaw-required-download-failed-',
      );
      addTearDown(() async {
        if (await localWorkspace.exists()) {
          await localWorkspace.delete(recursive: true);
        }
      });
      controller.upsertTaskThreadInternal(
        'unit-fixture-task-a',
        workspaceBinding: WorkspaceBinding(
          workspaceId: 'unit-fixture-task-a',
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: localWorkspace.path,
          displayPath: localWorkspace.path,
          writable: true,
        ),
        openClawTaskAssociation: const OpenClawTaskAssociation(
          sessionId: 'unit-fixture-task-a',
          threadId: 'unit-fixture-task-a',
          turnId: 'turn-1',
          runId: 'turn-1',
          artifactScope: 'tasks/agent_main_unit_fixture/turn-1',
          artifactDirectory: '/remote/tasks/agent_main_unit_fixture/turn-1',
          gatewayProviderId: 'openclaw',
          startedAtMs: 1,
          status: 'completed',
          appThreadKey: 'unit-fixture-task-a',
          openclawSessionKey: 'agent:main:unit-fixture',
          requiresArtifactExport: true,
        ),
      );

      final bytes = utf8.encode('# Final\n');
      final result = GoTaskServiceResult(
        success: true,
        message: 'done',
        turnId: 'turn-1',
        raw: <String, dynamic>{
          'artifacts': <Map<String, dynamic>>[
            <String, dynamic>{
              'relativePath': 'exports/final.md',
              'contentType': 'text/markdown',
              'encoding': 'base64',
              'content': base64Encode(bytes),
              'sizeBytes': bytes.length,
              'sha256': '0' * 64,
            },
          ],
        },
        errorMessage: '',
        resolvedModel: '',
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      await controller.persistGoTaskArtifactsForSessionInternal(
        'unit-fixture-task-a',
        result,
      );

      final thread = controller.requireTaskThreadForSessionInternal(
        'unit-fixture-task-a',
      );
      expect(thread.lastArtifactSyncStatus, 'syncing');
      expect(thread.lifecycleState.lastResultCode, 'running');
      expect(thread.openClawTaskAssociation?.status, 'syncing-artifacts');
      expect(thread.lastTaskArtifactRelativePaths, isEmpty);
    },
  );

  test('loads global and selected skill artifact-ignore policies', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-skill-artifact-policy-',
    );
    addTearDown(() async {
      if (await localWorkspace.exists()) {
        await localWorkspace.delete(recursive: true);
      }
    });
    await Directory(
      '${localWorkspace.path}/skills/video-production/it-infra-evolution-video-v2',
    ).create(recursive: true);
    await File('${localWorkspace.path}/artifact-ignore.md').writeAsString(
      '```artifact-ignore\n'
      'tmp/\n'
      '```\n',
    );
    await File(
      '${localWorkspace.path}/skills/video-production/it-infra-evolution-video-v2/artifact-ignore.md',
    ).writeAsString(
      '```artifact-ignore\n'
      'renders/tmp/\n'
      '```\n',
    );
    final startedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await Directory('${localWorkspace.path}/tmp').create();
    // `snapshots/` is ignored by the video skill policy only, while `tmp/`
    // is treated as global workspace noise for every task.
    await Directory('${localWorkspace.path}/snapshots').create();
    await Directory('${localWorkspace.path}/renders').create();
    await File('${localWorkspace.path}/tmp/build.log').writeAsString('log');
    await File(
      '${localWorkspace.path}/snapshots/scratch.png',
    ).writeAsBytes(<int>[1, 2, 3]);
    await File(
      '${localWorkspace.path}/renders/final.mp4',
    ).writeAsBytes(<int>[4, 5, 6]);

    controller.upsertTaskThreadInternal(
      'unit-fixture-task-a',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-a',
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localWorkspace.path,
        displayPath: localWorkspace.path,
        writable: true,
      ),
      selectedSkillKeys: const <String>[
        'video-production/it-infra-evolution-video-v2',
      ],
      lifecycleStatus: 'running',
      lastRunAtMs: startedAtMs,
      lastResultCode: 'running',
    );

    const result = GoTaskServiceResult(
      success: true,
      message: 'done',
      turnId: 'turn-1',
      raw: <String, dynamic>{},
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );

    await controller.persistGoTaskArtifactsForSessionInternal(
      'unit-fixture-task-a',
      result,
    );

    final thread = controller.requireTaskThreadForSessionInternal(
      'unit-fixture-task-a',
    );
    expect(thread.lastArtifactSyncStatus, 'synced');
    expect(thread.lastTaskArtifactRelativePaths, <String>['renders/final.mp4']);

    controller.upsertTaskThreadInternal(
      'unit-fixture-task-b',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-b',
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localWorkspace.path,
        displayPath: localWorkspace.path,
        writable: true,
      ),
      selectedSkillKeys: const <String>[],
      lifecycleStatus: 'running',
      lastRunAtMs: startedAtMs,
      lastResultCode: 'running',
    );
    await controller.persistGoTaskArtifactsForSessionInternal(
      'unit-fixture-task-b',
      result,
    );
    final unselectedSkillThread = controller
        .requireTaskThreadForSessionInternal('unit-fixture-task-b');
    expect(unselectedSkillThread.lastTaskArtifactRelativePaths, <String>[
      'renders/final.mp4',
      'snapshots/scratch.png',
    ]);
  });

  test('uses default artifact-ignore policy for video skill outputs', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-video-default-artifact-policy-',
    );
    addTearDown(() async {
      if (await localWorkspace.exists()) {
        await localWorkspace.delete(recursive: true);
      }
    });
    final startedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await Directory(
      '${localWorkspace.path}/assets/images',
    ).create(recursive: true);
    await Directory('${localWorkspace.path}/build_segments').create();
    await Directory('${localWorkspace.path}/snapshots').create();
    await Directory('${localWorkspace.path}/renders').create();
    await File(
      '${localWorkspace.path}/assets/images/01.v8.png',
    ).writeAsBytes(<int>[1]);
    await File(
      '${localWorkspace.path}/build_segments/segment-01.mp4',
    ).writeAsBytes(<int>[2]);
    await File(
      '${localWorkspace.path}/snapshots/frame-01.png',
    ).writeAsBytes(<int>[3]);
    await File(
      '${localWorkspace.path}/renders/final.mp4',
    ).writeAsBytes(<int>[4]);

    controller.upsertTaskThreadInternal(
      'unit-fixture-task-a',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-a',
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localWorkspace.path,
        displayPath: localWorkspace.path,
        writable: true,
      ),
      selectedSkillKeys: const <String>['it-infra-evolution-video-v2'],
      lifecycleStatus: 'running',
      lastRunAtMs: startedAtMs,
      lastResultCode: 'running',
    );

    const result = GoTaskServiceResult(
      success: true,
      message: 'done',
      turnId: 'turn-1',
      raw: <String, dynamic>{},
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );

    await controller.persistGoTaskArtifactsForSessionInternal(
      'unit-fixture-task-a',
      result,
    );

    final thread = controller.requireTaskThreadForSessionInternal(
      'unit-fixture-task-a',
    );
    expect(thread.lastArtifactSyncStatus, 'synced');
    expect(thread.lastTaskArtifactRelativePaths, <String>['renders/final.mp4']);
  });

  test('records ordinary empty artifact results as no artifacts', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-empty-artifacts-workspace-',
    );
    addTearDown(() async {
      if (await localWorkspace.exists()) {
        await localWorkspace.delete(recursive: true);
      }
    });
    final staleArtifact = File('${localWorkspace.path}/old-task-report.md');
    await staleArtifact.writeAsString('stale task output');
    controller.upsertTaskThreadInternal(
      'unit-fixture-task-a',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-a',
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localWorkspace.path,
        displayPath: localWorkspace.path,
        writable: true,
      ),
    );

    const result = GoTaskServiceResult(
      success: true,
      message: 'no files this time',
      turnId: 'turn-1',
      raw: <String, dynamic>{},
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );

    await controller.persistGoTaskArtifactsForSessionInternal(
      'unit-fixture-task-a',
      result,
    );

    expect(
      controller
          .requireTaskThreadForSessionInternal('unit-fixture-task-a')
          .lastArtifactSyncStatus,
      'no-artifacts',
    );
    final snapshot = await controller.loadAssistantArtifactSnapshot(
      sessionKey: 'unit-fixture-task-a',
    );
    expect(snapshot.resultEntries, isEmpty);
    expect(snapshot.fileEntries, isEmpty);
    expect(snapshot.resultMessage, 'No task artifacts recorded for this run.');
  });

  test('keeps OpenClaw task-scope empty artifact results syncing', () async {
    final controller = AppController(
      environmentOverride: const <String, String>{},
    );
    addTearDown(controller.dispose);

    final localWorkspace = await Directory.systemTemp.createTemp(
      'xworkmate-openclaw-empty-artifacts-workspace-',
    );
    addTearDown(() async {
      if (await localWorkspace.exists()) {
        await localWorkspace.delete(recursive: true);
      }
    });

    controller.upsertTaskThreadInternal(
      'unit-fixture-openclaw-empty',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-openclaw-empty',
        workspaceKind: WorkspaceKind.localFs,
        workspacePath: localWorkspace.path,
        displayPath: localWorkspace.path,
        writable: true,
      ),
      lifecycleStatus: 'running',
      lastResultCode: 'running',
      openClawTaskAssociation: const OpenClawTaskAssociation(
        sessionId: 'unit-fixture-openclaw-empty',
        threadId: 'unit-fixture-openclaw-empty',
        turnId: 'turn-empty',
        runId: 'turn-empty',
        artifactScope:
            'tasks/agent:main:unit-fixture-openclaw-empty/turn-empty',
        artifactDirectory:
            '/home/ubuntu/.openclaw/workspace/tasks/agent:main:unit-fixture-openclaw-empty/turn-empty',
        gatewayProviderId: 'openclaw',
        startedAtMs: 1,
        status: 'running',
        appThreadKey: 'unit-fixture-openclaw-empty',
        openclawSessionKey: 'agent:main:unit-fixture-openclaw-empty',
        requiresArtifactExport: true,
      ),
    );

    const result = GoTaskServiceResult(
      success: true,
      message: 'completed but export is still empty',
      turnId: 'turn-empty',
      raw: <String, dynamic>{},
      errorMessage: '',
      resolvedModel: '',
      route: GoTaskServiceRoute.externalAcpSingle,
    );

    await controller.persistGoTaskArtifactsForSessionInternal(
      'unit-fixture-openclaw-empty',
      result,
    );

    final thread = controller.requireTaskThreadForSessionInternal(
      'unit-fixture-openclaw-empty',
    );
    expect(thread.lifecycleState.status, 'running');
    expect(thread.lifecycleState.lastResultCode, 'running');
    expect(thread.lastArtifactSyncStatus, 'syncing');
    expect(thread.lastTaskArtifactRelativePaths, isEmpty);
    expect(thread.openClawTaskAssociation?.status, 'syncing-artifacts');
  });

  test(
    'records workspace files produced during an empty-artifact task run',
    () async {
      final controller = AppController(
        environmentOverride: const <String, String>{},
      );
      addTearDown(controller.dispose);

      final localWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-empty-artifact-produced-files-',
      );
      addTearDown(() async {
        if (await localWorkspace.exists()) {
          await localWorkspace.delete(recursive: true);
        }
      });
      await File(
        '${localWorkspace.path}/old-task-report.md',
      ).writeAsString('stale task output');
      final startedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await Directory('${localWorkspace.path}/renders').create();
      await Directory('${localWorkspace.path}/prompts').create();
      await File(
        '${localWorkspace.path}/renders/identity-security-evolution.mp4',
      ).writeAsBytes(<int>[1, 2, 3]);
      await File(
        '${localWorkspace.path}/prompts/DELIVERY.md',
      ).writeAsString('delivery notes');
      controller.upsertTaskThreadInternal(
        'unit-fixture-task-a',
        workspaceBinding: WorkspaceBinding(
          workspaceId: 'unit-fixture-task-a',
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
        message:
            'OpenClaw final artifacts were written to the current task artifact scope: mp4, png.',
        turnId: 'turn-1',
        raw: <String, dynamic>{},
        errorMessage: '',
        resolvedModel: '',
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      await controller.persistGoTaskArtifactsForSessionInternal(
        'unit-fixture-task-a',
        result,
      );

      final thread = controller.requireTaskThreadForSessionInternal(
        'unit-fixture-task-a',
      );
      expect(thread.lastArtifactSyncStatus, 'synced');
      expect(thread.lastTaskArtifactRelativePaths, <String>[
        'prompts/DELIVERY.md',
        'renders/identity-security-evolution.mp4',
      ]);
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
      'unit-fixture-task-a',
      workspaceBinding: WorkspaceBinding(
        workspaceId: 'unit-fixture-task-a',
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
      'unit-fixture-task-a',
      result,
    );

    expect(
      await File('${localWorkspace.path}/reports/download.txt').exists(),
      isFalse,
    );
    expect(
      controller
          .requireTaskThreadForSessionInternal('unit-fixture-task-a')
          .lastArtifactSyncStatus,
      'no-artifacts',
    );
  });

  test(
    'OpenClaw artifact polling times out when required artifacts stay missing',
    () async {
      var getTaskCount = 0;
      final staleSyncAtMs = DateTime.now()
          .subtract(
            kOpenClawArtifactSyncMaxDuration + const Duration(seconds: 1),
          )
          .millisecondsSinceEpoch
          .toDouble();
      const sessionKey = 'draft-openclaw-required-timeout';
      const runId = 'turn-required-timeout';
      const openClawSessionKey = 'agent:main:draft:openclaw-required-timeout';
      final association = OpenClawTaskAssociation(
        sessionId: sessionKey,
        threadId: sessionKey,
        turnId: runId,
        runId: runId,
        artifactScope: 'tasks/$openClawSessionKey/$runId',
        artifactDirectory:
            '/home/ubuntu/.openclaw/workspace/tasks/$openClawSessionKey/$runId',
        gatewayProviderId: 'openclaw',
        startedAtMs: staleSyncAtMs,
        status: 'syncing-artifacts',
        appThreadKey: 'draft:openclaw-required-timeout',
        openclawSessionKey: openClawSessionKey,
        requiredArtifactExtensions: const <String>['pdf'],
        requiresArtifactExport: true,
      );
      final goTaskClient = _PollingGoTaskServiceClient(
        onGetTask: (observedAssociation) {
          getTaskCount += 1;
          expect(observedAssociation.runId, runId);
          return GoTaskServiceResult(
            success: true,
            message: 'done but still missing pdf',
            turnId: runId,
            raw: <String, dynamic>{
              'success': true,
              'status': 'completed',
              'sessionId': sessionKey,
              'threadId': sessionKey,
              'turnId': runId,
              'runId': runId,
              'artifactScope': association.artifactScope,
              'artifactDirectory': association.artifactDirectory,
              'gatewayProviderId': 'openclaw',
              'appThreadKey': association.appThreadKey,
              'openclawSessionKey': openClawSessionKey,
              'requiredArtifactExtensions': <String>['pdf'],
              'requiresArtifactExport': true,
              'artifacts': <Map<String, dynamic>>[
                <String, dynamic>{
                  'relativePath': 'exports/final.md',
                  'content': '# not the final pdf\n',
                  'contentType': 'text/markdown',
                },
              ],
            },
            errorMessage: '',
            resolvedModel: '',
            route: GoTaskServiceRoute.externalAcpSingle,
          );
        },
      );
      final controller = AppController(
        environmentOverride: const <String, String>{},
        goTaskServiceClient: goTaskClient,
      );
      addTearDown(controller.dispose);

      final taskWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-required-timeout-',
      );
      addTearDown(() async {
        if (await taskWorkspace.exists()) {
          await taskWorkspace.delete(recursive: true);
        }
      });
      controller.upsertTaskThreadInternal(
        sessionKey,
        workspaceBinding: WorkspaceBinding(
          workspaceId: sessionKey,
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: taskWorkspace.path,
          displayPath: taskWorkspace.path,
          writable: true,
        ),
        lifecycleStatus: 'running',
        lastResultCode: 'running',
        lastArtifactSyncAtMs: staleSyncAtMs,
        lastArtifactSyncStatus: 'syncing',
        openClawTaskAssociation: association,
      );
      controller.aiGatewayPendingSessionKeysInternal.add(sessionKey);

      await controller
          .pollOpenClawTaskAssociationInternal(
            sessionKey: sessionKey,
            target: AssistantExecutionTarget.gateway,
            association: association,
          )
          .timeout(const Duration(seconds: 1));

      final thread = controller.requireTaskThreadForSessionInternal(sessionKey);
      expect(getTaskCount, 1);
      expect(thread.lifecycleState.status, 'ready');
      expect(
        thread.lifecycleState.lastResultCode,
        kOpenClawArtifactSyncTimeoutCode,
      );
      expect(thread.lastArtifactSyncStatus, 'partial');
      expect(thread.openClawTaskAssociation?.status, 'completed');
      expect(controller.assistantSessionHasPendingRun(sessionKey), isFalse);
      expect(
        controller.localSessionMessagesInternal[sessionKey]?.last.text,
        contains('pdf'),
      );
    },
  );

  test(
    'OpenClaw artifact sync times out when artifact downloads keep failing',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..add(<int>[1, 2, 3]);
        await request.response.close();
      });

      final staleSyncAtMs = DateTime.now()
          .subtract(
            kOpenClawArtifactSyncMaxDuration + const Duration(seconds: 1),
          )
          .millisecondsSinceEpoch
          .toDouble();
      const sessionKey = 'draft-openclaw-download-timeout';
      const runId = 'turn-download-timeout';
      const openClawSessionKey = 'agent:main:draft:openclaw-download-timeout';
      final association = OpenClawTaskAssociation(
        sessionId: sessionKey,
        threadId: sessionKey,
        turnId: runId,
        runId: runId,
        artifactScope: 'tasks/$openClawSessionKey/$runId',
        artifactDirectory:
            '/home/ubuntu/.openclaw/workspace/tasks/$openClawSessionKey/$runId',
        gatewayProviderId: 'openclaw',
        startedAtMs: staleSyncAtMs,
        status: 'syncing-artifacts',
        appThreadKey: 'draft:openclaw-download-timeout',
        openclawSessionKey: openClawSessionKey,
        requiredArtifactExtensions: const <String>['pdf'],
        requiresArtifactExport: true,
      );
      final controller = AppController(
        environmentOverride: const <String, String>{
          'BRIDGE_AUTH_TOKEN': 'bridge-token',
        },
      );
      addTearDown(controller.dispose);

      final taskWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-download-timeout-',
      );
      addTearDown(() async {
        if (await taskWorkspace.exists()) {
          await taskWorkspace.delete(recursive: true);
        }
      });
      controller.upsertTaskThreadInternal(
        sessionKey,
        workspaceBinding: WorkspaceBinding(
          workspaceId: sessionKey,
          workspaceKind: WorkspaceKind.localFs,
          workspacePath: taskWorkspace.path,
          displayPath: taskWorkspace.path,
          writable: true,
        ),
        lifecycleStatus: 'running',
        lastResultCode: 'running',
        lastArtifactSyncAtMs: staleSyncAtMs,
        lastArtifactSyncStatus: 'syncing',
        openClawTaskAssociation: association,
      );
      final result = GoTaskServiceResult(
        success: true,
        message: 'pdf exported',
        turnId: runId,
        raw: <String, dynamic>{
          'success': true,
          'status': 'completed',
          'artifacts': <Map<String, dynamic>>[
            <String, dynamic>{
              'relativePath': 'exports/final.pdf',
              'downloadUrl':
                  'http://xworkmate-bridge.svc.plus:${server.port}/final.pdf',
              'contentType': 'application/pdf',
              'sizeBytes': 99,
            },
          ],
        },
        errorMessage: '',
        resolvedModel: '',
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      final clientFactory = _proxiedClientFactory(server.port);
      await HttpOverrides.runZoned(() async {
        await controller.persistGoTaskArtifactsForSessionInternal(
          sessionKey,
          result,
          artifactSyncStartedAtMs: staleSyncAtMs,
        );
      }, createHttpClient: clientFactory);

      final thread = controller.requireTaskThreadForSessionInternal(sessionKey);
      expect(
        await File('${taskWorkspace.path}/exports/final.pdf').exists(),
        isFalse,
      );
      expect(thread.lifecycleState.status, 'ready');
      expect(
        thread.lifecycleState.lastResultCode,
        kOpenClawArtifactSyncTimeoutCode,
      );
      expect(thread.lastArtifactSyncStatus, 'partial');
      expect(thread.openClawTaskAssociation?.status, 'completed');
      expect(
        controller.localSessionMessagesInternal[sessionKey]?.last.text,
        contains('pdf'),
      );
    },
  );
}

HttpClient Function(SecurityContext?) _proxiedClientFactory(int port) {
  final clients = List<HttpClient>.generate(
    16,
    (_) => HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$port',
  );
  var index = 0;
  return (_) => clients[index++];
}

String _pollutedUnitSessionKey() =>
    'draft'
    ':unit-task-a';
String _pollutedTestSessionKey() =>
    'draft'
    ':test-task-a';
String _pollutedUnitWorkspaceName() =>
    'draft'
    '-unit-task-a';
String _pollutedTestWorkspaceName() =>
    'draft'
    '-test-task-a';

TaskThread _persistedThread({
  required String sessionKey,
  required String title,
  required String workspacePath,
}) {
  return TaskThread(
    threadId: sessionKey,
    title: title,
    workspaceBinding: WorkspaceBinding(
      workspaceId: sessionKey,
      workspaceKind: WorkspaceKind.localFs,
      workspacePath: workspacePath,
      displayPath: workspacePath,
      writable: true,
    ),
    executionBinding: const ExecutionBinding(
      executionMode: ThreadExecutionMode.gateway,
      executorId: 'openclaw',
      providerId: 'openclaw',
      endpointId: '',
    ),
  );
}

class _RecordingSecureConfigStore extends SecureConfigStore {
  _RecordingSecureConfigStore({required String rootPath})
    : super(
        secretRootPathResolver: () async => '$rootPath/secrets',
        appDataRootPathResolver: () async => '$rootPath/app-data',
        supportRootPathResolver: () async => '$rootPath/support',
        enableSecureStorage: false,
      );

  bool clearAssistantLocalStateCalled = false;

  @override
  Future<void> clearAssistantLocalState() async {
    clearAssistantLocalStateCalled = true;
    await super.clearAssistantLocalState();
  }
}

class _ArtifactBackfillGoTaskServiceClient implements GoTaskServiceClient {
  _ArtifactBackfillGoTaskServiceClient({required this.onGetTask});

  final void Function(OpenClawTaskAssociation association) onGetTask;

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    throw UnimplementedError('executeTask is not used by this test');
  }

  @override
  Future<GoTaskServiceResult> getTask({
    required AssistantExecutionTarget target,
    required OpenClawTaskAssociation association,
    required GoTaskServiceRoute route,
  }) async {
    onGetTask(association);
    return GoTaskServiceResult(
      success: true,
      message: 'done',
      turnId: association.turnId,
      raw: <String, dynamic>{
        'success': true,
        'status': 'completed',
        'runId': association.runId,
        'remoteWorkingDirectory': association.artifactDirectory,
        'remoteWorkspaceRefKind': 'remotePath',
        'artifacts': <Map<String, dynamic>>[
          <String, dynamic>{
            'relativePath': 'ai-news-report.md',
            'content': '# AI news\n',
            'contentType': 'text/markdown',
          },
        ],
      },
      errorMessage: '',
      resolvedModel: '',
      route: route,
    );
  }

  @override
  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
    OpenClawTaskAssociation? association,
  }) async {}

  @override
  Future<void> dispose() async {}
}

class _PollingGoTaskServiceClient implements GoTaskServiceClient {
  _PollingGoTaskServiceClient({required this.onGetTask});

  final GoTaskServiceResult Function(OpenClawTaskAssociation association)
  onGetTask;

  @override
  Future<GoTaskServiceResult> executeTask(
    GoTaskServiceRequest request, {
    required void Function(GoTaskServiceUpdate update) onUpdate,
  }) async {
    throw UnimplementedError('executeTask is not used by this test');
  }

  @override
  Future<GoTaskServiceResult> getTask({
    required AssistantExecutionTarget target,
    required OpenClawTaskAssociation association,
    required GoTaskServiceRoute route,
  }) async {
    return onGetTask(association);
  }

  @override
  Future<void> cancelTask({
    required GoTaskServiceRoute route,
    required AssistantExecutionTarget target,
    required String sessionId,
    required String threadId,
    OpenClawTaskAssociation? association,
  }) async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _waitForControllerInitialization(AppController controller) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (controller.initializing && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(controller.initializing, isFalse);
}
