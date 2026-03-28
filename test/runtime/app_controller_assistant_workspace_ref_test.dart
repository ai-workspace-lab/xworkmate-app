@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

import '../test_support.dart';

void main() {
  test(
    'AppController keeps workspace refs aligned with assistant thread targets',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController(
        store: createIsolatedTestStore(enableSecureStorage: false),
      );
      addTearDown(controller.dispose);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.initializing) {
        if (DateTime.now().isAfter(deadline)) {
          fail('controller did not initialize in time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(
        controller.assistantWorkspaceRefForSession(
          controller.currentSessionKey,
        ),
        '${controller.settings.workspacePath}/.xworkmate/threads/main',
      );
      expect(
        controller.assistantWorkspaceRefKindForSession(
          controller.currentSessionKey,
        ),
        WorkspaceRefKind.remotePath,
      );

      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.remote,
      );
      expect(
        controller.assistantWorkspaceRefForSession(
          controller.currentSessionKey,
        ),
        '${controller.settings.workspacePath}/.xworkmate/threads/main',
      );
      expect(
        controller.assistantWorkspaceRefKindForSession(
          controller.currentSessionKey,
        ),
        WorkspaceRefKind.remotePath,
      );

      const draftKey = 'draft:artifact-thread';
      controller.initializeAssistantThreadContext(
        draftKey,
        title: 'Artifact Thread',
        executionTarget: AssistantExecutionTarget.singleAgent,
      );
      await controller.switchSession(draftKey);
      final draftWorkspaceRef = controller.assistantWorkspaceRefForSession(
        draftKey,
      );
      expect(
        draftWorkspaceRef,
        startsWith('${controller.settings.workspacePath}/.xworkmate/threads/'),
      );
      expect(draftWorkspaceRef, isNot(controller.settings.workspacePath));
      expect(
        controller.assistantWorkspaceRefKindForSession(draftKey),
        WorkspaceRefKind.localPath,
      );
    },
  );

  test(
    'AppController migrates draft single-agent threads off the shared workspace root',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-workspace-migrate-',
      );
      final workspaceRoot = Directory('${tempDirectory.path}/workspace');
      await workspaceRoot.create(recursive: true);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        SettingsSnapshot.defaults().copyWith(workspacePath: workspaceRoot.path),
      );
      await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'draft:artifact-thread',
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 1,
          title: 'Artifact Thread',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          workspaceRef: workspaceRoot.path,
          workspaceRefKind: WorkspaceRefKind.localPath,
        ),
      ]);

      final controller = AppController(store: store);
      addTearDown(controller.dispose);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.initializing) {
        if (DateTime.now().isAfter(deadline)) {
          fail('controller did not initialize in time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final migratedWorkspace = controller.assistantWorkspaceRefForSession(
        'draft:artifact-thread',
      );
      expect(
        migratedWorkspace,
        '${workspaceRoot.path}/.xworkmate/threads/draft-artifact-thread',
      );
      expect(Directory(migratedWorkspace).existsSync(), isTrue);
    },
  );

  test(
    'AppController preserves recorded workspace refs when switching threads',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-workspace-ref-',
      );
      final mainWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-main-thread-',
      );
      final taskWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-task-thread-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
        if (await mainWorkspace.exists()) {
          await mainWorkspace.delete(recursive: true);
        }
        if (await taskWorkspace.exists()) {
          await taskWorkspace.delete(recursive: true);
        }
      });
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'main',
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 1,
          title: 'Main',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          workspaceRef: mainWorkspace.path,
          workspaceRefKind: WorkspaceRefKind.localPath,
        ),
        AssistantThreadRecord(
          sessionKey: 'draft:artifact-thread',
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 2,
          title: 'Artifact Thread',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          workspaceRef: taskWorkspace.path,
          workspaceRefKind: WorkspaceRefKind.localPath,
        ),
      ]);

      final controller = AppController(store: store);
      addTearDown(controller.dispose);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.initializing) {
        if (DateTime.now().isAfter(deadline)) {
          fail('controller did not initialize in time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(
        controller.assistantWorkspaceRefForSession('main'),
        mainWorkspace.path,
      );
      expect(
        controller.assistantWorkspaceRefForSession('draft:artifact-thread'),
        taskWorkspace.path,
      );

      await controller.switchSession('draft:artifact-thread');
      expect(
        controller.assistantWorkspaceRefForSession('draft:artifact-thread'),
        taskWorkspace.path,
      );

      await controller.switchSession('main');
      expect(
        controller.assistantWorkspaceRefForSession('main'),
        mainWorkspace.path,
      );
    },
  );

  test(
    'AppController rebinds default thread workspaces after bootstrap updates the workspace root',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-workspace-bootstrap-migrate-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(SettingsSnapshot.defaults());
      await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'draft:artifact-thread',
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 1,
          title: 'Artifact Thread',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          workspaceRef: '/opt/data/.xworkmate/threads/draft-artifact-thread',
          workspaceRefKind: WorkspaceRefKind.localPath,
        ),
      ]);

      final controller = AppController(store: store);
      addTearDown(controller.dispose);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.initializing) {
        if (DateTime.now().isAfter(deadline)) {
          fail('controller did not initialize in time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(controller.settings.workspacePath, isNot('/opt/data'));
      final migratedWorkspace = controller.assistantWorkspaceRefForSession(
        'draft:artifact-thread',
      );
      expect(
        migratedWorkspace,
        '${controller.settings.workspacePath}/.xworkmate/threads/draft-artifact-thread',
      );
      expect(Directory(migratedWorkspace).existsSync(), isTrue);
    },
  );

  test(
    'AppController migrates missing draft workspace refs to isolated thread directories',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-workspace-missing-',
      );
      final workspaceRoot = Directory('${tempDirectory.path}/workspace');
      await workspaceRoot.create(recursive: true);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.db',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        SettingsSnapshot.defaults().copyWith(workspacePath: workspaceRoot.path),
      );
      await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'draft:missing-ref-thread',
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 1,
          title: 'Missing Ref Thread',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          workspaceRef: '${workspaceRoot.path}/.xworkmate/threads/missing-dir',
          workspaceRefKind: WorkspaceRefKind.localPath,
        ),
      ]);

      final controller = AppController(store: store);
      addTearDown(controller.dispose);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.initializing) {
        if (DateTime.now().isAfter(deadline)) {
          fail('controller did not initialize in time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final migratedWorkspace = controller.assistantWorkspaceRefForSession(
        'draft:missing-ref-thread',
      );
      expect(
        migratedWorkspace,
        '${workspaceRoot.path}/.xworkmate/threads/draft-missing-ref-thread',
      );
      expect(Directory(migratedWorkspace).existsSync(), isTrue);
    },
  );
}
