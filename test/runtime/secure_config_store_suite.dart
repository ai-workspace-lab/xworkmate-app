@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'SecureConfigStore persists settings and secure refs in test runners',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final databasePath = '${tempDirectory.path}/settings.sqlite3';
      final store = SecureConfigStore(
        databasePathResolver: () async => databasePath,
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );

      final snapshot = SettingsSnapshot.defaults().copyWith(
        accountUsername: 'tester',
        accountWorkspace: 'QA',
        codeAgentRuntimeMode: CodeAgentRuntimeMode.externalCli,
        codexCliPath: '/opt/homebrew/bin/codex',
        assistantNavigationDestinations: const <WorkspaceDestination>[
          WorkspaceDestination.aiGateway,
          WorkspaceDestination.secrets,
        ],
        gateway: GatewayConnectionProfile.defaults().copyWith(
          host: 'gateway.example.com',
          port: 9443,
        ),
      );

      await store.saveSettingsSnapshot(snapshot);
      await store.saveGatewayToken('token-secret');
      await store.saveGatewayPassword('password-secret');
      await store.saveVaultToken('vault-secret');
      await store.saveAiGatewayApiKey('ai-gateway-secret');

      final loadedSnapshot = await store.loadSettingsSnapshot();
      final secureRefs = await store.loadSecureRefs();

      expect(loadedSnapshot.accountUsername, 'tester');
      expect(loadedSnapshot.accountWorkspace, 'QA');
      expect(
        loadedSnapshot.codeAgentRuntimeMode,
        CodeAgentRuntimeMode.externalCli,
      );
      expect(loadedSnapshot.codexCliPath, '/opt/homebrew/bin/codex');
      expect(
        loadedSnapshot.assistantNavigationDestinations,
        const <WorkspaceDestination>[
          WorkspaceDestination.aiGateway,
          WorkspaceDestination.secrets,
        ],
      );
      expect(loadedSnapshot.gateway.host, 'gateway.example.com');
      expect(loadedSnapshot.gateway.port, 9443);
      expect(secureRefs['gateway_token'], 'token-secret');
      expect(secureRefs['gateway_password'], 'password-secret');
      expect(secureRefs['vault_token'], 'vault-secret');
      expect(secureRefs['ai_gateway_api_key'], 'ai-gateway-secret');
      expect(SecureConfigStore.maskValue('token-secret'), 'tok••••ret');
      expect(SecureConfigStore.maskValue(''), 'Not set');
    },
  );

  test(
    'SecureConfigStore persists sqlite-backed settings across instances',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-cross-instance-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final databasePath = '${tempDirectory.path}/settings.sqlite3';

      final snapshot = SettingsSnapshot.defaults().copyWith(
        accountUsername: 'sqlite-user',
        accountWorkspace: 'sqlite-workspace',
        gateway: GatewayConnectionProfile.defaults().copyWith(
          host: 'sqlite.example.com',
          port: 443,
        ),
      );
      final entry = SecretAuditEntry(
        timeLabel: '10:00',
        action: 'Updated',
        provider: 'Vault',
        target: 'vault_token',
        module: 'Settings',
        status: 'Success',
      );

      final firstStore = SecureConfigStore(
        databasePathResolver: () async => databasePath,
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      await firstStore.saveSettingsSnapshot(snapshot);
      await firstStore.appendAudit(entry);

      final secondStore = SecureConfigStore(
        databasePathResolver: () async => databasePath,
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final loadedSnapshot = await secondStore.loadSettingsSnapshot();
      final loadedAudit = await secondStore.loadAuditTrail();

      expect(loadedSnapshot.accountUsername, 'sqlite-user');
      expect(loadedSnapshot.accountWorkspace, 'sqlite-workspace');
      expect(loadedSnapshot.gateway.host, 'sqlite.example.com');
      expect(loadedAudit, hasLength(1));
      expect(loadedAudit.first.provider, 'Vault');
      expect(loadedAudit.first.target, 'vault_token');
    },
  );

  test(
    'SecureConfigStore persists multi-agent settings without secrets in snapshot json',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-multi-agent-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final databasePath = '${tempDirectory.path}/settings.sqlite3';
      final store = SecureConfigStore(
        databasePathResolver: () async => databasePath,
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );

      final snapshot = SettingsSnapshot.defaults().copyWith(
        multiAgent: MultiAgentConfig.defaults().copyWith(
          enabled: true,
          autoSync: false,
          framework: MultiAgentFramework.aris,
          arisEnabled: true,
          arisBundleVersion: '2026-03-19-dd663c1',
          arisCompatStatus: 'ready',
          aiGatewayInjectionPolicy: AiGatewayInjectionPolicy.launchScoped,
          architect: const AgentWorkerConfig(
            role: MultiAgentRole.architect,
            cliTool: 'gemini',
            model: 'gemini-2.5-pro',
            enabled: true,
          ),
          managedSkills: const <ManagedSkillEntry>[
            ManagedSkillEntry(
              key: 'calm_compact_workspace_system',
              label: 'Calm Compact Workspace System',
              source: '/Users/test/.codex/skills/calm_compact_workspace_system',
              selected: true,
            ),
          ],
          managedMcpServers: const <ManagedMcpServerEntry>[
            ManagedMcpServerEntry(
              id: 'xworkmate/gateway',
              name: 'XWorkmate Gateway',
              transport: 'stdio',
              command: 'xworkmate-mcp',
              url: '',
              args: <String>['--stdio'],
              envKeys: <String>[],
              enabled: true,
            ),
          ],
        ),
      );

      await store.saveSettingsSnapshot(snapshot);
      final loadedSnapshot = await store.loadSettingsSnapshot();
      final encoded = loadedSnapshot.toJsonString();

      expect(loadedSnapshot.multiAgent.enabled, isTrue);
      expect(loadedSnapshot.multiAgent.autoSync, isFalse);
      expect(loadedSnapshot.multiAgent.framework, MultiAgentFramework.aris);
      expect(loadedSnapshot.multiAgent.arisEnabled, isTrue);
      expect(loadedSnapshot.multiAgent.arisBundleVersion, '2026-03-19-dd663c1');
      expect(loadedSnapshot.multiAgent.arisCompatStatus, 'ready');
      expect(
        loadedSnapshot.multiAgent.aiGatewayInjectionPolicy,
        AiGatewayInjectionPolicy.launchScoped,
      );
      expect(loadedSnapshot.multiAgent.architect.model, 'gemini-2.5-pro');
      expect(loadedSnapshot.multiAgent.managedSkills, hasLength(1));
      expect(loadedSnapshot.multiAgent.managedMcpServers, hasLength(1));
      expect(encoded, contains('"multiAgent"'));
      expect(encoded, isNot(contains('ai-gateway-secret')));
      expect(encoded, isNot(contains('gateway_token')));
    },
  );

  test(
    'SecureConfigStore persists assistant thread records and archived task keys',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-assistant-threads-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final databasePath = '${tempDirectory.path}/settings.sqlite3';
      final store = SecureConfigStore(
        databasePathResolver: () async => databasePath,
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );

      final snapshot = SettingsSnapshot.defaults().copyWith(
        assistantArchivedTaskKeys: const <String>['main'],
        assistantCustomTaskTitles: const <String, String>{'main': '研发任务'},
        assistantLastSessionKey: 'main',
      );
      const records = <AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'main',
          title: '研发任务',
          archived: true,
          executionTarget: AssistantExecutionTarget.remote,
          messageViewMode: AssistantMessageViewMode.raw,
          discoveredSkills: <AssistantThreadSkillEntry>[
            AssistantThreadSkillEntry(
              key: '/tmp/discovered-skill',
              label: 'Discovered Skill',
              description: 'candidate only',
              sourcePath: '/tmp/discovered-skill',
              sourceLabel: 'codex/discovered',
            ),
          ],
          importedSkills: <AssistantThreadSkillEntry>[
            AssistantThreadSkillEntry(
              key: '/tmp/imported-skill',
              label: 'Imported Skill',
              description: 'confirmed import',
              sourcePath: '/tmp/imported-skill',
              sourceLabel: 'workbuddy/imported',
            ),
          ],
          selectedSkillKeys: <String>['/tmp/imported-skill'],
          assistantModelId: 'gpt-5.4-mini',
          gatewayEntryState: 'ai-gateway-only',
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
      await store.saveAssistantThreadRecords(records);

      final reloadedSnapshot = await store.loadSettingsSnapshot();
      final reloadedRecords = await store.loadAssistantThreadRecords();

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
      expect(reloadedRecords.first.discoveredSkills, hasLength(1));
      expect(reloadedRecords.first.importedSkills, hasLength(1));
      expect(reloadedRecords.first.selectedSkillKeys, const <String>[
        '/tmp/imported-skill',
      ]);
      expect(reloadedRecords.first.assistantModelId, 'gpt-5.4-mini');
      expect(reloadedRecords.first.gatewayEntryState, 'ai-gateway-only');
      expect(reloadedRecords.first.messages, hasLength(2));
      expect(reloadedRecords.first.messages.last.text, '第一条回复');
    },
  );

  test('SettingsSnapshot encodes and decodes assistantLastSessionKey', () {
    final snapshot = SettingsSnapshot.defaults().copyWith(
      assistantLastSessionKey: 'draft:session-1',
    );

    final decoded = SettingsSnapshot.fromJsonString(snapshot.toJsonString());

    expect(decoded.assistantLastSessionKey, 'draft:session-1');
  });

  test(
    'AssistantThreadRecord keeps compatibility with legacy json payloads',
    () {
      final decoded = AssistantThreadRecord.fromJson(<String, dynamic>{
        'sessionKey': 'legacy-thread',
        'messages': const <Object>[],
        'updatedAtMs': 1700000000000,
        'title': 'Legacy',
        'archived': false,
        'executionTarget': 'local',
        'messageViewMode': 'rendered',
      });

      expect(decoded.discoveredSkills, isEmpty);
      expect(decoded.importedSkills, isEmpty);
      expect(decoded.selectedSkillKeys, isEmpty);
      expect(decoded.assistantModelId, isEmpty);
      expect(decoded.gatewayEntryState, isNull);
    },
  );

  test(
    'SecureConfigStore restores assistant state from backup when primary storage is missing',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-backup-restore-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final databasePath = '${tempDirectory.path}/settings.sqlite3';
      final store = SecureConfigStore(
        databasePathResolver: () async => databasePath,
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final snapshot = SettingsSnapshot.defaults().copyWith(
        accountUsername: 'backup-user',
        assistantLastSessionKey: 'draft:backup-1',
      );
      const records = <AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'draft:backup-1',
          title: '备份线程',
          archived: false,
          executionTarget: AssistantExecutionTarget.aiGatewayOnly,
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
      await store.saveAssistantThreadRecords(records);

      final database = sqlite.sqlite3.open(databasePath);
      addTearDown(database.dispose);
      database.execute('DELETE FROM config_entries');

      final recoveredStore = SecureConfigStore(
        databasePathResolver: () async => databasePath,
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final recoveredSnapshot = await recoveredStore.loadSettingsSnapshot();
      final recoveredRecords = await recoveredStore
          .loadAssistantThreadRecords();

      expect(recoveredSnapshot.accountUsername, 'backup-user');
      expect(recoveredSnapshot.assistantLastSessionKey, 'draft:backup-1');
      expect(recoveredRecords, hasLength(1));
      expect(recoveredRecords.first.sessionKey, 'draft:backup-1');
      expect(recoveredRecords.first.messages.single.text, 'backup message');
    },
  );

  test(
    'SecureConfigStore clears assistant local state without deleting secure refs',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-clear-local-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final databasePath = '${tempDirectory.path}/settings.sqlite3';
      final store = SecureConfigStore(
        databasePathResolver: () async => databasePath,
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final snapshot = SettingsSnapshot.defaults().copyWith(
        accountUsername: 'clear-me',
        assistantLastSessionKey: 'draft:clear-1',
      );
      const records = <AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'draft:clear-1',
          title: '清理线程',
          archived: false,
          executionTarget: AssistantExecutionTarget.local,
          messageViewMode: AssistantMessageViewMode.rendered,
          updatedAtMs: 1700000000000,
          messages: <GatewayChatMessage>[],
        ),
      ];

      await store.saveSettingsSnapshot(snapshot);
      await store.saveAssistantThreadRecords(records);
      await store.saveGatewayToken('token-secret');

      await store.clearAssistantLocalState();

      final clearedSnapshot = await store.loadSettingsSnapshot();
      final clearedRecords = await store.loadAssistantThreadRecords();

      expect(
        clearedSnapshot.accountUsername,
        SettingsSnapshot.defaults().accountUsername,
      );
      expect(clearedSnapshot.assistantLastSessionKey, isEmpty);
      expect(clearedRecords, isEmpty);
      expect(await store.loadGatewayToken(), 'token-secret');
      expect(
        await File(
          '${tempDirectory.path}/assistant-state-backup.json',
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'SecureConfigStore dispose closes sqlite handle and allows reopening the same database path',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-dispose-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
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

  test(
    'SecureConfigStore clears gateway token without touching snapshot',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = SecureConfigStore();

      await store.saveGatewayToken('token-secret');
      expect(await store.loadGatewayToken(), 'token-secret');

      await store.clearGatewayToken();

      expect(await store.loadGatewayToken(), isNull);
      expect(
        (await store.loadSecureRefs()).containsKey('gateway_token'),
        isFalse,
      );
    },
  );

  test(
    'SecureConfigStore falls back to file-backed device identity and token across instances',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-secure-store-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final identity = const LocalDeviceIdentity(
        deviceId: 'device-123',
        publicKeyBase64Url: 'public-key',
        privateKeyBase64Url: 'private-key',
        createdAtMs: 1700000000000,
      );
      final firstStore = SecureConfigStore(
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      await firstStore.saveDeviceIdentity(identity);
      await firstStore.saveDeviceToken(
        deviceId: identity.deviceId,
        role: 'operator',
        token: 'device-token',
      );

      final secondStore = SecureConfigStore(
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      final reloadedIdentity = await secondStore.loadDeviceIdentity();
      final reloadedToken = await secondStore.loadDeviceToken(
        deviceId: identity.deviceId,
        role: 'operator',
      );

      expect(reloadedIdentity?.deviceId, identity.deviceId);
      expect(reloadedIdentity?.publicKeyBase64Url, identity.publicKeyBase64Url);
      expect(
        reloadedIdentity?.privateKeyBase64Url,
        identity.privateKeyBase64Url,
      );
      expect(reloadedToken, 'device-token');
    },
  );
}
