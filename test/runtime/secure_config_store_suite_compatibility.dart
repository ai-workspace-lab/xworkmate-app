// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'secure_config_store_suite_core.dart';
import 'secure_config_store_suite_settings.dart';
import 'secure_config_store_suite_secrets.dart';
import 'secure_config_store_suite_lifecycle.dart';
import 'secure_config_store_suite_fixtures.dart';

void registerSecureConfigStoreSuiteCompatibilityTestsInternal() {
  group('Compatibility', () {
    test(
      'SecureConfigStore ignores legacy local-state files and keeps them untouched',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-local-state-',
        );
        final settingsFile = File(
          '${tempDirectory.path}/settings-snapshot.json',
        );
        final threadsFile = File(
          '${tempDirectory.path}/assistant-threads.json',
        );
        await settingsFile.writeAsString('{"accountUsername":"local-user"}');
        await threadsFile.writeAsString('[]');

        final firstStore = SecureConfigStore(
          databasePathResolver: () async =>
              '${tempDirectory.path}/settings.sqlite3',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );

        final loadedSnapshot = await firstStore.loadSettingsSnapshot();
        final loadedThreads = await firstStore.loadTaskThreads();

        expect(
          loadedSnapshot.accountUsername,
          SettingsSnapshot.defaults().accountUsername,
        );
        expect(loadedThreads, isEmpty);
        expect(await settingsFile.exists(), isTrue);
        expect(await threadsFile.exists(), isTrue);
      },
    );

    test(
      'SecureConfigStore ignores legacy shared-preferences assistant state and only reads sqlite',
      () async {
        final legacySnapshot = SettingsSnapshot.defaults().copyWith(
          accountUsername: 'legacy-user',
          assistantLastSessionKey: 'draft:legacy-1',
        );
        final legacyRecords = <TaskThread>[
          TaskThread(
            threadId: 'draft:legacy-1',
            workspaceBinding: const WorkspaceBinding(
              workspaceId: 'draft:legacy-1',
              workspaceKind: WorkspaceKind.remoteFs,
              workspacePath: '/owners/remote/user/legacy/threads/draft:legacy-1',
              displayPath:
                  '/owners/remote/user/legacy/threads/draft:legacy-1',
              writable: true,
            ),
            title: 'Legacy thread',
            archived: false,
            executionTarget: AssistantExecutionTarget.local,
            messageViewMode: AssistantMessageViewMode.rendered,
            messages: <GatewayChatMessage>[
              GatewayChatMessage(
                id: 'assistant-1',
                role: 'assistant',
                text: 'legacy message',
                timestampMs: 1700000001000,
                toolCallId: null,
                toolName: null,
                stopReason: null,
                pending: false,
                error: false,
              ),
            ],
            updatedAtMs: 1700000000000,
          ),
        ];
        SharedPreferences.setMockInitialValues(<String, Object>{
          'xworkmate.settings.snapshot': legacySnapshot.toJsonString(),
          'xworkmate.assistant.threads': jsonEncode(
            legacyRecords.map((item) => item.toJson()).toList(growable: false),
          ),
        });
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-legacy-migrate-',
          resetSharedPreferences: false,
        );
        final databasePath = '${tempDirectory.path}/settings.sqlite3';

        final store = SecureConfigStore(
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final loadedSnapshot = await store.loadSettingsSnapshot();
        final loadedThreads = await store.loadTaskThreads();

        expect(
          loadedSnapshot.accountUsername,
          SettingsSnapshot.defaults().accountUsername,
        );
        expect(loadedSnapshot.assistantLastSessionKey, isEmpty);
        expect(loadedThreads, isEmpty);

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('xworkmate.settings.snapshot'),
          legacySnapshot.toJsonString(),
        );
        expect(
          prefs.getString('xworkmate.assistant.threads'),
          jsonEncode(
            legacyRecords.map((item) => item.toJson()).toList(growable: false),
          ),
        );
      },
    );

    test(
      'SecureConfigStore ignores stray local-state files when sqlite has no assistant state',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-ignore-stray-files-',
        );
        final databasePath = '${tempDirectory.path}/settings.sqlite3';
        await File(
          '${tempDirectory.path}/settings-snapshot.json',
        ).writeAsString('{"accountUsername":"locked-user"}', flush: true);
        await File(
          '${tempDirectory.path}/assistant-threads.json',
        ).writeAsString('[{"sessionKey":"ignored-thread"}]', flush: true);

        final store = SecureConfigStore(
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final loadedSnapshot = await store.loadSettingsSnapshot();
        final loadedThreads = await store.loadTaskThreads();

        expect(
          loadedSnapshot.accountUsername,
          SettingsSnapshot.defaults().accountUsername,
        );
        expect(loadedThreads, isEmpty);
      },
    );

    test('SettingsSnapshot encodes and decodes assistantLastSessionKey', () {
      final snapshot = SettingsSnapshot.defaults().copyWith(
        assistantLastSessionKey: 'draft:session-1',
      );

      final decoded = SettingsSnapshot.fromJsonString(snapshot.toJsonString());

      expect(decoded.assistantLastSessionKey, 'draft:session-1');
    });

    test('SettingsSnapshot encodes and decodes authorizedSkillDirectories', () {
      final snapshot = SettingsSnapshot.defaults().copyWith(
        authorizedSkillDirectories: const <AuthorizedSkillDirectory>[
          AuthorizedSkillDirectory(path: '/etc/skills'),
          AuthorizedSkillDirectory(
            path: '/Users/test/.agents/skills',
            bookmark: 'bookmark-data',
          ),
        ],
      );

      final decoded = SettingsSnapshot.fromJsonString(snapshot.toJsonString());

      expect(
        decoded.authorizedSkillDirectories.map((item) => item.path),
        const <String>['/Users/test/.agents/skills', '/etc/skills'],
      );
      expect(
        decoded.authorizedSkillDirectories.first.bookmark,
        'bookmark-data',
      );
    });

    test(
      'SettingsSnapshot keeps compatibility with legacy target json values',
      () {
        final decoded = SettingsSnapshot.fromJson(<String, dynamic>{
          ...SettingsSnapshot.defaults().toJson(),
          'assistantExecutionTarget': 'aiGatewayOnly',
        });

        expect(
          decoded.assistantExecutionTarget,
          AssistantExecutionTarget.singleAgent,
        );
      },
    );

    test('TaskThread round-trips structured bindings', () {
      final record = TaskThread(
        threadId: 'thread-1',
        title: 'Thread 1',
        ownerScope: const ThreadOwnerScope(
          realm: ThreadRealm.remote,
          subjectType: ThreadSubjectType.user,
          subjectId: 'user-1',
          displayName: 'User 1',
        ),
        workspaceBinding: const WorkspaceBinding(
          workspaceId: 'workspace-1',
          workspaceKind: WorkspaceKind.remoteFs,
          workspacePath: '/owners/remote/user/user-1/threads/thread-1',
          displayPath: '/owners/remote/user/user-1/threads/thread-1',
          writable: true,
        ),
        executionBinding: const ExecutionBinding(
          executionMode: ThreadExecutionMode.gatewayRemote,
          executorId: 'gateway',
          providerId: 'gateway',
          endpointId: 'remote',
        ),
        contextState: const ThreadContextState(
          messages: <GatewayChatMessage>[],
          selectedModelId: 'gpt-5.4',
          selectedSkillKeys: <String>['skill.a'],
          importedSkills: <AssistantThreadSkillEntry>[],
          permissionLevel: AssistantPermissionLevel.defaultAccess,
          messageViewMode: AssistantMessageViewMode.rendered,
          latestResolvedRuntimeModel: 'gpt-5.4',
        ),
        lifecycleState: const ThreadLifecycleState(
          archived: false,
          status: 'ready',
          lastRunAtMs: 1700000000000,
          lastResultCode: 'ok',
        ),
        createdAtMs: 1700000000000,
        updatedAtMs: 1700000001000,
      );

      final decoded = TaskThread.fromJson(record.toJson());

      expect(decoded.threadId, 'thread-1');
      expect(decoded.ownerScope.subjectId, 'user-1');
      expect(
        decoded.workspaceBinding.workspacePath,
        '/owners/remote/user/user-1/threads/thread-1',
      );
      expect(decoded.workspaceBinding.workspaceKind, WorkspaceKind.remoteFs);
      expect(
        decoded.executionBinding.executionMode,
        ThreadExecutionMode.gatewayRemote,
      );
      expect(decoded.contextState.selectedModelId, 'gpt-5.4');
      expect(decoded.lifecycleState.status, 'ready');
    });

    test('TaskThread rejects persisted records without a complete binding', () {
      expect(
        () => TaskThread.fromJson(<String, dynamic>{
          'schemaVersion': taskThreadSchemaVersion,
          'threadId': 'thread-legacy',
          'title': 'Needs Workspace',
          'ownerScope': const <String, Object?>{
            'realm': 'local',
            'subjectType': 'user',
            'subjectId': 'device-1',
            'displayName': 'device-1',
          },
          'workspaceBinding': const <String, Object?>{
            'workspaceId': 'thread-legacy',
            'workspaceKind': 'localFs',
            'workspacePath': '',
            'displayPath': '',
            'writable': true,
          },
          'executionBinding': const <String, Object?>{
            'executionMode': 'localAgent',
            'executorId': 'auto',
            'providerId': 'auto',
            'endpointId': '',
          },
          'contextState': const <String, Object?>{
            'messages': <Object>[],
            'selectedModelId': '',
            'selectedSkillKeys': <Object>[],
            'importedSkills': <Object>[],
            'permissionLevel': 'defaultAccess',
            'messageViewMode': 'rendered',
            'latestResolvedRuntimeModel': '',
          },
          'lifecycleState': const <String, Object?>{
            'archived': false,
            'status': 'needs_workspace',
            'lastRunAtMs': null,
            'lastResultCode': null,
          },
          'createdAtMs': 1700000000000,
          'updatedAtMs': 1700000000000,
        }),
        throwsFormatException,
      );
    });
  });
}
