@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

import '../test_support.dart';

Future<void> waitForControllerInternal(AppController controller) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (controller.initializing) {
    if (DateTime.now().isAfter(deadline)) {
      fail('controller did not initialize in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test(
    'AppController binds single-agent threads to local workspace directories',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController(
        store: createIsolatedTestStore(enableSecureStorage: false),
      );
      addTearDown(controller.dispose);

      await waitForControllerInternal(controller);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      final workspacePath = controller.assistantWorkspacePathForSession(
        controller.currentSessionKey,
      );
      expect(
        workspacePath,
        '${controller.settings.workspacePath}/.xworkmate/threads/main',
      );
      expect(
        controller.assistantWorkspaceKindForSession(
          controller.currentSessionKey,
        ),
        WorkspaceRefKind.localPath,
      );
    },
  );

  test(
    'AppController binds gateway threads to owner-scoped remote workspace paths',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppController(
        store: createIsolatedTestStore(enableSecureStorage: false),
      );
      addTearDown(controller.dispose);

      await waitForControllerInternal(controller);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.remote,
      );

      final record = controller
          .assistantThreadRecordsInternal[controller.currentSessionKey]!;
      expect(record.ownerScope.realm, ThreadRealm.local);
      expect(record.ownerScope.subjectType, ThreadSubjectType.user);
      expect(record.ownerScope.subjectId, isNotEmpty);
      expect(
        record.workspacePath,
        '/owners/${record.ownerScope.realm.name}/${record.ownerScope.subjectType.name}/${record.ownerScope.subjectId}/threads/${record.threadId}',
      );
      expect(record.displayPath, record.workspacePath);
      expect(record.workspaceKind, WorkspaceKind.remoteFs);
      expect(
        controller.assistantWorkspaceKindForSession(record.threadId),
        WorkspaceRefKind.remotePath,
      );
    },
  );

  test(
    'AppController preserves recorded task workspace bindings across thread switches',
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
      await store.saveTaskThreads(<TaskThread>[
        TaskThread(
          threadId: 'main',
          title: 'Main',
          ownerScope: const ThreadOwnerScope(
            realm: ThreadRealm.local,
            subjectType: ThreadSubjectType.user,
            subjectId: 'device-main',
            displayName: 'device-main',
          ),
          workspaceBinding: WorkspaceBinding(
            workspaceId: 'main',
            workspaceKind: WorkspaceKind.localFs,
            workspacePath: mainWorkspace.path,
            displayPath: mainWorkspace.path,
            writable: true,
          ),
          executionBinding: const ExecutionBinding(
            executionMode: ThreadExecutionMode.localAgent,
            executorId: 'auto',
            providerId: 'auto',
            endpointId: '',
          ),
          contextState: const ThreadContextState(
            messages: <GatewayChatMessage>[],
            selectedModelId: '',
            selectedSkillKeys: <String>[],
            importedSkills: <AssistantThreadSkillEntry>[],
            permissionLevel: AssistantPermissionLevel.defaultAccess,
            messageViewMode: AssistantMessageViewMode.rendered,
            latestResolvedRuntimeModel: '',
          ),
          lifecycleState: const ThreadLifecycleState(
            archived: false,
            status: 'ready',
            lastRunAtMs: null,
            lastResultCode: null,
          ),
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        TaskThread(
          threadId: 'draft:artifact-thread',
          title: 'Artifact Thread',
          ownerScope: const ThreadOwnerScope(
            realm: ThreadRealm.local,
            subjectType: ThreadSubjectType.user,
            subjectId: 'device-task',
            displayName: 'device-task',
          ),
          workspaceBinding: WorkspaceBinding(
            workspaceId: 'draft:artifact-thread',
            workspaceKind: WorkspaceKind.localFs,
            workspacePath: taskWorkspace.path,
            displayPath: taskWorkspace.path,
            writable: true,
          ),
          executionBinding: const ExecutionBinding(
            executionMode: ThreadExecutionMode.localAgent,
            executorId: 'auto',
            providerId: 'auto',
            endpointId: '',
          ),
          contextState: const ThreadContextState(
            messages: <GatewayChatMessage>[],
            selectedModelId: '',
            selectedSkillKeys: <String>[],
            importedSkills: <AssistantThreadSkillEntry>[],
            permissionLevel: AssistantPermissionLevel.defaultAccess,
            messageViewMode: AssistantMessageViewMode.rendered,
            latestResolvedRuntimeModel: '',
          ),
          lifecycleState: const ThreadLifecycleState(
            archived: false,
            status: 'ready',
            lastRunAtMs: null,
            lastResultCode: null,
          ),
          createdAtMs: 2,
          updatedAtMs: 2,
        ),
      ]);

      final controller = AppController(store: store);
      addTearDown(controller.dispose);
      await waitForControllerInternal(controller);

      expect(
        controller.assistantWorkspacePathForSession('main'),
        mainWorkspace.path,
      );
      expect(
        controller.assistantWorkspacePathForSession('draft:artifact-thread'),
        taskWorkspace.path,
      );

      await controller.switchSession('draft:artifact-thread');
      expect(
        controller.assistantWorkspacePathForSession('draft:artifact-thread'),
        taskWorkspace.path,
      );

      await controller.switchSession('main');
      expect(
        controller.assistantWorkspacePathForSession('main'),
        mainWorkspace.path,
      );
    },
  );

  test(
    'AppController keeps recorded single-agent bindings instead of migrating legacy paths',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-workspace-restore-',
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
      await store.saveTaskThreads(<TaskThread>[
        TaskThread(
          threadId: 'draft:artifact-thread',
          title: 'Artifact Thread',
          ownerScope: const ThreadOwnerScope(
            realm: ThreadRealm.local,
            subjectType: ThreadSubjectType.user,
            subjectId: 'device-task',
            displayName: 'device-task',
          ),
          workspaceBinding: WorkspaceBinding(
            workspaceId: 'draft:artifact-thread',
            workspaceKind: WorkspaceKind.localFs,
            workspacePath: workspaceRoot.path,
            displayPath: workspaceRoot.path,
            writable: true,
          ),
          executionBinding: const ExecutionBinding(
            executionMode: ThreadExecutionMode.localAgent,
            executorId: 'auto',
            providerId: 'auto',
            endpointId: '',
          ),
          contextState: const ThreadContextState(
            messages: <GatewayChatMessage>[],
            selectedModelId: '',
            selectedSkillKeys: <String>[],
            importedSkills: <AssistantThreadSkillEntry>[],
            permissionLevel: AssistantPermissionLevel.defaultAccess,
            messageViewMode: AssistantMessageViewMode.rendered,
            latestResolvedRuntimeModel: '',
          ),
          lifecycleState: const ThreadLifecycleState(
            archived: false,
            status: 'ready',
            lastRunAtMs: null,
            lastResultCode: null,
          ),
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ]);

      final controller = AppController(store: store);
      addTearDown(controller.dispose);
      await waitForControllerInternal(controller);

      expect(
        controller.assistantWorkspacePathForSession('draft:artifact-thread'),
        workspaceRoot.path,
      );
      expect(
        controller
            .assistantThreadRecordsInternal['draft:artifact-thread']
            ?.lifecycleState
            .status,
        'ready',
      );
    },
  );

  test(
    'AppController recreates recorded local thread directories during restore',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-workspace-restore-create-',
      );
      final workspaceRoot = Directory('${tempDirectory.path}/workspace');
      await workspaceRoot.create(recursive: true);
      final missingThreadWorkspace = Directory(
        '${workspaceRoot.path}/.xworkmate/threads/draft-restored-thread',
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
      await store.saveSettingsSnapshot(
        SettingsSnapshot.defaults().copyWith(workspacePath: workspaceRoot.path),
      );
      await store.saveTaskThreads(<TaskThread>[
        TaskThread(
          threadId: 'draft:restored-thread',
          title: 'Restored Thread',
          ownerScope: const ThreadOwnerScope(
            realm: ThreadRealm.local,
            subjectType: ThreadSubjectType.user,
            subjectId: 'device-task',
            displayName: 'device-task',
          ),
          workspaceBinding: WorkspaceBinding(
            workspaceId: 'draft:restored-thread',
            workspaceKind: WorkspaceKind.localFs,
            workspacePath: missingThreadWorkspace.path,
            displayPath: '/stale/display/path',
            writable: true,
          ),
          executionBinding: const ExecutionBinding(
            executionMode: ThreadExecutionMode.localAgent,
            executorId: 'auto',
            providerId: 'auto',
            endpointId: '',
          ),
          contextState: const ThreadContextState(
            messages: <GatewayChatMessage>[],
            selectedModelId: '',
            selectedSkillKeys: <String>[],
            importedSkills: <AssistantThreadSkillEntry>[],
            permissionLevel: AssistantPermissionLevel.defaultAccess,
            messageViewMode: AssistantMessageViewMode.rendered,
            latestResolvedRuntimeModel: '',
          ),
          lifecycleState: const ThreadLifecycleState(
            archived: false,
            status: 'ready',
            lastRunAtMs: null,
            lastResultCode: null,
          ),
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ]);

      final controller = AppController(store: store);
      addTearDown(controller.dispose);
      await waitForControllerInternal(controller);

      expect(await missingThreadWorkspace.exists(), isTrue);
      expect(
        controller.assistantWorkspacePathForSession('draft:restored-thread'),
        missingThreadWorkspace.path,
      );
      expect(
        controller.assistantWorkspaceDisplayPathForSession(
          'draft:restored-thread',
        ),
        missingThreadWorkspace.path,
      );
    },
  );

  test(
    'AppController creates the local thread workspace immediately when initializing a new task thread',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-workspace-new-thread-',
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

      final controller = AppController(store: store);
      addTearDown(controller.dispose);
      await waitForControllerInternal(controller);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      controller.initializeAssistantThreadContext(
        'draft:created-thread',
        title: 'Created Thread',
        executionTarget: AssistantExecutionTarget.singleAgent,
      );

      final threadWorkspace = Directory(
        '${workspaceRoot.path}/.xworkmate/threads/draft-created-thread',
      );
      expect(await threadWorkspace.exists(), isTrue);
      expect(
        controller.assistantWorkspacePathForSession('draft:created-thread'),
        threadWorkspace.path,
      );
      expect(
        controller.assistantWorkspaceDisplayPathForSession(
          'draft:created-thread',
        ),
        threadWorkspace.path,
      );
    },
  );

  test(
    'AppController rebinds the current single-agent thread after configuring a workspace root',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-workspace-configure-root-',
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
        SettingsSnapshot.defaults().copyWith(workspacePath: ''),
      );
      final controller = AppController(store: store);
      addTearDown(controller.dispose);
      await waitForControllerInternal(controller);
      final existingMain = controller
          .assistantThreadRecordsInternal[controller.currentSessionKey]!;
      controller.assistantThreadRecordsInternal[controller.currentSessionKey] =
          existingMain.copyWith(
            workspaceBinding: const WorkspaceBinding(
              workspaceId: 'main',
              workspaceKind: WorkspaceKind.localFs,
              workspacePath: '',
              displayPath: '',
              writable: true,
            ),
            lifecycleState: existingMain.lifecycleState.copyWith(
              status: 'needs_workspace',
            ),
            executionTarget: AssistantExecutionTarget.singleAgent,
          );
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      controller.assistantThreadRecordsInternal[controller
          .currentSessionKey] = controller
          .assistantThreadRecordsInternal[controller.currentSessionKey]!
          .copyWith(
            workspaceBinding: const WorkspaceBinding(
              workspaceId: 'main',
              workspaceKind: WorkspaceKind.localFs,
              workspacePath: '',
              displayPath: '',
              writable: true,
            ),
            lifecycleState: controller
                .assistantThreadRecordsInternal[controller.currentSessionKey]!
                .lifecycleState
                .copyWith(status: 'needs_workspace'),
          );

      expect(
        controller.assistantWorkspacePathForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );
      expect(
        controller
            .assistantThreadRecordsInternal[controller.currentSessionKey]
            ?.lifecycleState
            .status,
        'needs_workspace',
      );

      await controller.saveSettings(
        controller.settings.copyWith(workspacePath: workspaceRoot.path),
      );

      expect(
        controller.assistantWorkspacePathForSession(
          controller.currentSessionKey,
        ),
        '${workspaceRoot.path}/.xworkmate/threads/main',
      );
      expect(
        controller
            .assistantThreadRecordsInternal[controller.currentSessionKey]
            ?.displayPath,
        '${workspaceRoot.path}/.xworkmate/threads/main',
      );
      expect(
        controller
            .assistantThreadRecordsInternal[controller.currentSessionKey]
            ?.lifecycleState
            .status,
        'ready',
      );
    },
  );

  test(
    'AppController keeps single-agent threads unbound when the workspace root cannot create thread directories',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-workspace-invalid-root-',
      );
      final invalidRootFile = File('${tempDirectory.path}/workspace-root-file');
      await invalidRootFile.writeAsString('not-a-directory');
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
        SettingsSnapshot.defaults().copyWith(
          workspacePath: invalidRootFile.path,
        ),
      );

      final controller = AppController(store: store);
      addTearDown(controller.dispose);
      await waitForControllerInternal(controller);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      controller.initializeAssistantThreadContext(
        'draft:invalid-root',
        title: 'Invalid Root',
        executionTarget: AssistantExecutionTarget.singleAgent,
      );

      final expectedThreadWorkspace = Directory(
        '${invalidRootFile.path}/.xworkmate/threads/draft-invalid-root',
      );
      expect(await expectedThreadWorkspace.exists(), isFalse);
      expect(
        controller.assistantWorkspacePathForSession('draft:invalid-root'),
        isEmpty,
      );
      expect(
        controller
            .assistantThreadRecordsInternal['draft:invalid-root']
            ?.lifecycleState
            .status,
        'needs_workspace',
      );
    },
  );
}
