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

      final workspacePath = controller.assistantWorkspaceRefForSession(
        controller.currentSessionKey,
      );
      expect(
        workspacePath,
        '${controller.settings.workspacePath}/.xworkmate/threads/main',
      );
      expect(
        controller.assistantWorkspaceRefKindForSession(
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

      final record =
          controller.assistantThreadRecordsInternal[controller.currentSessionKey]!;
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
        controller.assistantWorkspaceRefKindForSession(record.threadId),
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
        controller.assistantWorkspaceRefForSession('draft:artifact-thread'),
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
}
