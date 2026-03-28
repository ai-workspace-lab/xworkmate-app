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
        final loadedThreads = await firstStore.loadAssistantThreadRecords();

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
        const legacyRecords = <AssistantThreadRecord>[
          AssistantThreadRecord(
            sessionKey: 'draft:legacy-1',
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
        final loadedThreads = await store.loadAssistantThreadRecords();

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
        final loadedThreads = await store.loadAssistantThreadRecords();

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

    test(
      'AssistantThreadRecord keeps compatibility with legacy json payloads',
      () {
        final decoded = AssistantThreadRecord.fromJson(<String, dynamic>{
          'sessionKey': 'legacy-thread',
          'messages': const <Object>[],
          'updatedAtMs': 1700000000000,
          'title': 'Legacy',
          'archived': false,
          'executionTarget': 'aiGatewayOnly',
          'messageViewMode': 'rendered',
          'discoveredSkills': const <Object>[
            <String, Object?>{
              'key': '/tmp/legacy-discovered-skill',
              'label': 'Legacy Discovered Skill',
            },
          ],
          'singleAgentProvider': 'gemini',
          'gatewayEntryState': 'ai-gateway-only',
        });

        expect(decoded.executionTarget, AssistantExecutionTarget.singleAgent);
        expect(decoded.importedSkills, isEmpty);
        expect(decoded.selectedSkillKeys, isEmpty);
        expect(decoded.assistantModelId, isEmpty);
        expect(decoded.singleAgentProvider, SingleAgentProvider.gemini);
        expect(decoded.gatewayEntryState, 'single-agent');
        expect(decoded.workspaceRef, isEmpty);
        expect(decoded.workspaceRefKind, WorkspaceRefKind.localPath);
      },
    );

    test('AssistantThreadRecord round-trips workspaceRef fields', () {
      const record = AssistantThreadRecord(
        sessionKey: 'thread-1',
        messages: <GatewayChatMessage>[],
        updatedAtMs: 1700000000000,
        title: 'Thread 1',
        archived: false,
        executionTarget: AssistantExecutionTarget.remote,
        messageViewMode: AssistantMessageViewMode.rendered,
        workspaceRef: 'object://thread/thread-1',
        workspaceRefKind: WorkspaceRefKind.objectStore,
      );

      final decoded = AssistantThreadRecord.fromJson(record.toJson());

      expect(decoded.workspaceRef, 'object://thread/thread-1');
      expect(decoded.workspaceRefKind, WorkspaceRefKind.objectStore);
    });

    test(
      'AssistantThreadRecord infers objectStore kind from legacy workspace ref',
      () {
        final decoded = AssistantThreadRecord.fromJson(<String, dynamic>{
          'sessionKey': 'thread-legacy',
          'messages': const <Object>[],
          'updatedAtMs': 1700000000000,
          'title': 'Legacy Object Thread',
          'archived': false,
          'executionTarget': 'remote',
          'messageViewMode': 'rendered',
          'workspaceRef': 'object://thread/thread-legacy',
        });

        expect(decoded.workspaceRefKind, WorkspaceRefKind.objectStore);
      },
    );
  });
}
