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
import 'secure_config_store_suite_compatibility.dart';
import 'secure_config_store_suite_fixtures.dart';

void registerSecureConfigStoreSuiteLifecycleTestsInternal() {
  group('Assistant state lifecycle', () {
    test(
      'SecureConfigStore persists assistant thread records and archived task keys',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-assistant-threads-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);

        final snapshot = SettingsSnapshot.defaults().copyWith(
          assistantArchivedTaskKeys: const <String>['main'],
          assistantCustomTaskTitles: const <String, String>{'main': '研发任务'},
          assistantLastSessionKey: 'main',
        );
        final records = <TaskThread>[
          TaskThread(
            threadId: 'main',
            workspaceBinding: const WorkspaceBinding(
              workspaceId: 'main',
              workspaceKind: WorkspaceKind.remoteFs,
              workspacePath: '/owners/remote/user/main/threads/main',
              displayPath: '/owners/remote/user/main/threads/main',
              writable: true,
            ),
            title: '研发任务',
            archived: true,
            executionTarget: AssistantExecutionTarget.remote,
            messageViewMode: AssistantMessageViewMode.raw,
            importedSkills: <AssistantThreadSkillEntry>[
              AssistantThreadSkillEntry(
                key: '/tmp/imported-skill',
                label: 'Imported Skill',
                description: 'confirmed import',
                sourcePath: '/tmp/imported-skill',
                sourceLabel: 'custom/imported',
              ),
            ],
            selectedSkillKeys: <String>['/tmp/imported-skill'],
            assistantModelId: 'gpt-5.4-mini',
            singleAgentProvider: SingleAgentProvider.claude,
            gatewayEntryState: 'single-agent',
            updatedAtMs: 1700000000000,
            messages: <GatewayChatMessage>[
              GatewayChatMessage(
                id: 'user-1',
                role: 'user',
                text: '第一条消息',
                timestampMs: 1700000000000,
                toolCallId: null,
                toolName: null,
                stopReason: null,
                pending: false,
                error: false,
              ),
              GatewayChatMessage(
                id: 'assistant-1',
                role: 'assistant',
                text: '第一条回复',
                timestampMs: 1700000001000,
                toolCallId: null,
                toolName: null,
                stopReason: null,
                pending: false,
                error: false,
              ),
            ],
          ),
        ];

        await store.saveSettingsSnapshot(snapshot);
        await store.saveTaskThreads(records);

        final reloadedSnapshot = await store.loadSettingsSnapshot();
        final reloadedRecords = await store.loadTaskThreads();

        expect(reloadedSnapshot.assistantArchivedTaskKeys, const <String>[
          'main',
        ]);
        expect(reloadedSnapshot.assistantLastSessionKey, 'main');
        expect(reloadedSnapshot.assistantCustomTaskTitles['main'], '研发任务');
        expect(reloadedRecords, hasLength(1));
        expect(reloadedRecords.first.sessionKey, 'main');
        expect(reloadedRecords.first.archived, isTrue);
        expect(reloadedRecords.first.title, '研发任务');
        expect(
          reloadedRecords.first.executionTarget,
          AssistantExecutionTarget.remote,
        );
        expect(
          reloadedRecords.first.messageViewMode,
          AssistantMessageViewMode.raw,
        );
        expect(reloadedRecords.first.importedSkills, hasLength(1));
        expect(reloadedRecords.first.selectedSkillKeys, const <String>[
          '/tmp/imported-skill',
        ]);
        expect(reloadedRecords.first.assistantModelId, 'gpt-5.4-mini');
        expect(
          reloadedRecords.first.singleAgentProvider,
          SingleAgentProvider.claude,
        );
        expect(reloadedRecords.first.gatewayEntryState, 'single-agent');
        expect(reloadedRecords.first.messages, hasLength(2));
        expect(reloadedRecords.first.messages.last.text, '第一条回复');
      },
    );

    test(
      'SecureConfigStore restart keeps database state and legacy session files untouched',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-durable-restore-',
        );
        final databasePath = '${tempDirectory.path}/settings.sqlite3';
        final store = SecureConfigStore(
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final snapshot = SettingsSnapshot.defaults().copyWith(
          accountUsername: 'backup-user',
          assistantLastSessionKey: 'draft:backup-1',
        );
        final records = <TaskThread>[
          TaskThread(
            threadId: 'draft:backup-1',
            workspaceBinding: const WorkspaceBinding(
              workspaceId: 'draft:backup-1',
              workspaceKind: WorkspaceKind.localFs,
              workspacePath: '/tmp/draft-backup-1',
              displayPath: '/tmp/draft-backup-1',
              writable: true,
            ),
            title: '备份线程',
            archived: false,
            executionTarget: AssistantExecutionTarget.singleAgent,
            messageViewMode: AssistantMessageViewMode.rendered,
            updatedAtMs: 1700000000000,
            messages: <GatewayChatMessage>[
              GatewayChatMessage(
                id: 'assistant-1',
                role: 'assistant',
                text: 'backup message',
                timestampMs: 1700000001000,
                toolCallId: null,
                toolName: null,
                stopReason: null,
                pending: false,
                error: false,
              ),
            ],
          ),
        ];

        await store.saveSettingsSnapshot(snapshot);
        await store.saveTaskThreads(records);
        final settingsFile = File(
          '${tempDirectory.path}/settings-snapshot.json',
        );
        final threadsFile = File(
          '${tempDirectory.path}/assistant-threads.json',
        );
        await settingsFile.writeAsString(
          'legacy-settings-snapshot',
          flush: true,
        );
        await threadsFile.writeAsString(
          'legacy-assistant-threads',
          flush: true,
        );

        final recoveredStore = SecureConfigStore(
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final recoveredSnapshot = await recoveredStore.loadSettingsSnapshot();
        final recoveredRecords = await recoveredStore
            .loadTaskThreads();

        expect(recoveredSnapshot.accountUsername, 'backup-user');
        expect(recoveredSnapshot.assistantLastSessionKey, 'draft:backup-1');
        expect(recoveredRecords, hasLength(1));
        expect(recoveredRecords.first.sessionKey, 'draft:backup-1');
        expect(recoveredRecords.first.messages.single.text, 'backup message');
        expect(await settingsFile.readAsString(), 'legacy-settings-snapshot');
        expect(await threadsFile.readAsString(), 'legacy-assistant-threads');
      },
    );

    test(
      'SecureConfigStore clears assistant local state without deleting secure refs',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-clear-local-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);
        final snapshot = SettingsSnapshot.defaults().copyWith(
          accountUsername: 'clear-me',
          assistantLastSessionKey: 'draft:clear-1',
        );
        final records = <TaskThread>[
          TaskThread(
            threadId: 'draft:clear-1',
            workspaceBinding: const WorkspaceBinding(
              workspaceId: 'draft:clear-1',
              workspaceKind: WorkspaceKind.remoteFs,
              workspacePath: '/owners/remote/user/clear/threads/draft:clear-1',
              displayPath:
                  '/owners/remote/user/clear/threads/draft:clear-1',
              writable: true,
            ),
            title: '清理线程',
            archived: false,
            executionTarget: AssistantExecutionTarget.local,
            messageViewMode: AssistantMessageViewMode.rendered,
            updatedAtMs: 1700000000000,
            messages: <GatewayChatMessage>[],
          ),
        ];

        await store.saveSettingsSnapshot(snapshot);
        await store.saveTaskThreads(records);
        await store.saveGatewayToken('token-secret');

        await store.clearAssistantLocalState();

        final clearedSnapshot = await store.loadSettingsSnapshot();
        final clearedRecords = await store.loadTaskThreads();
        final settingsFiles = await store.resolvedSettingsFiles();

        expect(
          clearedSnapshot.accountUsername,
          'clear-me',
        );
        expect(clearedSnapshot.assistantLastSessionKey, isEmpty);
        expect(clearedRecords, isEmpty);
        expect(await store.loadGatewayToken(), 'token-secret');
        expect(settingsFiles, isNotEmpty);
        for (final file in settingsFiles) {
          expect(await file.exists(), isTrue);
        }

        store.dispose();
        final reloadedStore = createStoreFromTempDirectoryInternal(tempDirectory);
        final reloadedSnapshot = await reloadedStore.loadSettingsSnapshot();
        final reloadedRecords = await reloadedStore.loadTaskThreads();
        expect(reloadedSnapshot.accountUsername, 'clear-me');
        expect(reloadedSnapshot.assistantLastSessionKey, isEmpty);
        expect(reloadedRecords, isEmpty);
        expect(await reloadedStore.loadGatewayToken(), 'token-secret');
        reloadedStore.dispose();
      },
    );

    test(
      'SecureConfigStore dispose closes sqlite handle and allows reopening the same database path',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-dispose-',
        );
        final databasePath = '${tempDirectory.path}/settings.sqlite3';
        final firstStore = SecureConfigStore(
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final snapshot = SettingsSnapshot.defaults().copyWith(
          accountUsername: 'dispose-user',
        );

        await firstStore.saveSettingsSnapshot(snapshot);
        firstStore.dispose();
        firstStore.dispose();

        final secondStore = SecureConfigStore(
          databasePathResolver: () async => databasePath,
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
        final reloadedSnapshot = await secondStore.loadSettingsSnapshot();

        expect(reloadedSnapshot.accountUsername, 'dispose-user');
      },
    );
  });
}
