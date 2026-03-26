@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

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
        gatewayProfiles: replaceGatewayProfileAt(
          SettingsSnapshot.defaults().gatewayProfiles,
          kGatewayRemoteProfileIndex,
          GatewayConnectionProfile.defaultsRemote().copyWith(
            host: 'gateway.example.com',
            port: 9443,
          ),
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
      expect(
        loadedSnapshot.primaryRemoteGatewayProfile.host,
        'gateway.example.com',
      );
      expect(loadedSnapshot.primaryRemoteGatewayProfile.port, 9443);
      expect(secureRefs['gateway_token'], 'token-secret');
      expect(secureRefs['gateway_password'], 'password-secret');
      expect(secureRefs['vault_token'], 'vault-secret');
      expect(secureRefs['ai_gateway_api_key'], 'ai-gateway-secret');
      expect(SecureConfigStore.maskValue('token-secret'), 'tok••••ret');
      expect(SecureConfigStore.maskValue(''), 'Not set');
    },
  );

  test(
    'SecureConfigStore keeps gateway secrets isolated per profile slot',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-profiles-',
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

      await store.saveGatewayToken(
        'local-token',
        profileIndex: kGatewayLocalProfileIndex,
      );
      await store.saveGatewayToken(
        'remote-token',
        profileIndex: kGatewayRemoteProfileIndex,
      );
      await store.saveGatewayPassword(
        'custom-password',
        profileIndex: kGatewayCustomProfileStartIndex,
      );

      final secureRefs = await store.loadSecureRefs();

      expect(
        await store.loadGatewayToken(profileIndex: kGatewayLocalProfileIndex),
        'local-token',
      );
      expect(
        await store.loadGatewayToken(profileIndex: kGatewayRemoteProfileIndex),
        'remote-token',
      );
      expect(
        await store.loadGatewayPassword(
          profileIndex: kGatewayCustomProfileStartIndex,
        ),
        'custom-password',
      );
      expect(
        secureRefs['gateway_token_$kGatewayLocalProfileIndex'],
        'local-token',
      );
      expect(
        secureRefs['gateway_token_$kGatewayRemoteProfileIndex'],
        'remote-token',
      );
      expect(
        secureRefs['gateway_password_$kGatewayCustomProfileStartIndex'],
        'custom-password',
      );
      expect(await store.loadGatewayToken(), 'remote-token');
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
        gatewayProfiles: replaceGatewayProfileAt(
          SettingsSnapshot.defaults().gatewayProfiles,
          kGatewayRemoteProfileIndex,
          GatewayConnectionProfile.defaultsRemote().copyWith(
            host: 'sqlite.example.com',
            port: 443,
          ),
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
      expect(
        loadedSnapshot.primaryRemoteGatewayProfile.host,
        'sqlite.example.com',
      );
      expect(loadedAudit, hasLength(1));
      expect(loadedAudit.first.provider, 'Vault');
      expect(loadedAudit.first.target, 'vault_token');
    },
  );

  test(
    'SecureConfigStore keeps settings in memory when no durable path is available',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const unavailablePath = '/dev/null/xworkmate/settings.sqlite3';
      final store = SecureConfigStore(
        databasePathResolver: () async => unavailablePath,
        fallbackDirectoryPathResolver: () async =>
            '/dev/null/xworkmate/secrets',
      );
      final snapshot = SettingsSnapshot.defaults().copyWith(
        accountUsername: 'memory-user',
      );

      await store.saveSettingsSnapshot(snapshot);
      final loadedSnapshot = await store.loadSettingsSnapshot();
      final writeFailures = store.persistentWriteFailures;
      final reloadedSnapshot = await SecureConfigStore(
        databasePathResolver: () async => unavailablePath,
        fallbackDirectoryPathResolver: () async =>
            '/dev/null/xworkmate/secrets',
      ).loadSettingsSnapshot();

      expect(loadedSnapshot.accountUsername, 'memory-user');
      expect(writeFailures.settings, isNotNull);
      expect(writeFailures.settings?.scope, PersistentStoreScope.settings);
      expect(writeFailures.settings?.operation, 'saveSettingsSnapshot');
      expect(writeFailures.settings?.message, contains('Persistent settings'));
      expect(
        reloadedSnapshot.accountUsername,
        SettingsSnapshot.defaults().accountUsername,
      );
    },
  );

  test(
    'SecureConfigStore exposes an explicit tasks write failure when durable task storage is unavailable',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const unavailablePath = '/dev/null/xworkmate/settings.sqlite3';
      final store = SecureConfigStore(
        databasePathResolver: () async => unavailablePath,
        fallbackDirectoryPathResolver: () async =>
            '/dev/null/xworkmate/secrets',
      );

      await store.saveAssistantThreadRecords(const <AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'draft:memory-only',
          title: 'Memory only',
          archived: false,
          executionTarget: AssistantExecutionTarget.local,
          messageViewMode: AssistantMessageViewMode.rendered,
          updatedAtMs: 1700000000000,
          messages: <GatewayChatMessage>[],
        ),
      ]);

      final loadedRecords = await store.loadAssistantThreadRecords();
      final writeFailures = store.persistentWriteFailures;

      expect(loadedRecords, hasLength(1));
      expect(loadedRecords.first.sessionKey, 'draft:memory-only');
      expect(writeFailures.tasks, isNotNull);
      expect(writeFailures.tasks?.scope, PersistentStoreScope.tasks);
      expect(writeFailures.tasks?.operation, 'saveAssistantThreadRecords');
      expect(writeFailures.tasks?.message, contains('Persistent task path'));
    },
  );

  test(
    'SecureConfigStore auto-creates an explicit settings directory on first install',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-missing-settings-path-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final existingSecretsDirectory = Directory(
        '${tempDirectory.path}/secrets',
      );
      await existingSecretsDirectory.create(recursive: true);
      final explicitSettingsPath =
          '${tempDirectory.path}/settings/${SettingsStore.databaseFileName}';

      final store = SecureConfigStore(
        databasePathResolver: () async => explicitSettingsPath,
        fallbackDirectoryPathResolver: () async =>
            existingSecretsDirectory.path,
      );

      final snapshot = await store.loadSettingsSnapshot();

      expect(
        snapshot.accountUsername,
        SettingsSnapshot.defaults().accountUsername,
      );
      expect(
        await Directory('${tempDirectory.path}/settings/config').exists(),
        isTrue,
      );
      expect(
        await File(
          '${tempDirectory.path}/settings/config/settings.yaml',
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'SecureConfigStore auto-creates an explicit secrets directory on first install',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-missing-secrets-path-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final existingSettingsDirectory = Directory(
        '${tempDirectory.path}/settings',
      );
      await existingSettingsDirectory.create(recursive: true);

      final store = SecureConfigStore(
        databasePathResolver: () async =>
            '${existingSettingsDirectory.path}/${SettingsStore.databaseFileName}',
        fallbackDirectoryPathResolver: () async =>
            '${tempDirectory.path}/secrets',
      );

      await store.saveGatewayToken('token-secret');

      expect(await Directory('${tempDirectory.path}/secrets').exists(), isTrue);
      expect(await store.loadGatewayToken(), 'token-secret');
    },
  );

  test(
    'SecureConfigStore persists across instances using default support root when overrides fail',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-default-support-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final defaultSupportRoot =
          '${tempDirectory.path}/plus.svc.xworkmate/xworkmate';

      final firstStore = SecureConfigStore(
        databasePathResolver: () async =>
            throw StateError('primary unavailable'),
        fallbackDirectoryPathResolver: () async =>
            throw StateError('fallback unavailable'),
        defaultSupportDirectoryPathResolver: () async => defaultSupportRoot,
      );
      final snapshot = SettingsSnapshot.defaults().copyWith(
        accountUsername: 'fallback-user',
      );
      await firstStore.saveSettingsSnapshot(snapshot);
      await firstStore.saveGatewayToken('fallback-token');

      final secondStore = SecureConfigStore(
        databasePathResolver: () async =>
            throw StateError('primary unavailable'),
        fallbackDirectoryPathResolver: () async =>
            throw StateError('fallback unavailable'),
        defaultSupportDirectoryPathResolver: () async => defaultSupportRoot,
      );

      final loadedSnapshot = await secondStore.loadSettingsSnapshot();
      final loadedToken = await secondStore.loadGatewayToken();
      final settingsFile = File('$defaultSupportRoot/config/settings.yaml');
      final secretDirectory = Directory('$defaultSupportRoot/secrets');

      expect(await settingsFile.exists(), isTrue);
      expect(await secretDirectory.exists(), isTrue);
      expect(loadedSnapshot.accountUsername, 'fallback-user');
      expect(loadedToken, 'fallback-token');
    },
  );

  test('SecureConfigStore writes secrets into the fixed secret path', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final tempDirectory = await Directory.systemTemp.createTemp(
      'xworkmate-config-store-secret-path-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final store = SecureConfigStore(
      fallbackDirectoryPathResolver: () async =>
          '${tempDirectory.path}/secrets',
    );

    await store.saveGatewayToken('token-secret');
    await store.saveGatewayPassword('password-secret');
    await store.saveAiGatewayApiKey('ai-gateway-secret');

    expect(await store.loadGatewayToken(), 'token-secret');
    expect(await store.loadGatewayPassword(), 'password-secret');
    expect(await store.loadAiGatewayApiKey(), 'ai-gateway-secret');
    final secretDirectory = Directory('${tempDirectory.path}/secrets');
    final secretFiles = await secretDirectory
        .list()
        .where((entity) => entity is File)
        .toList();
    expect(secretFiles, hasLength(3));
    expect(
      secretFiles.every((entity) => entity.path.endsWith('.secret')),
      isTrue,
    );
    expect(store.persistentWriteFailures.secrets, isNull);
    if (!Platform.isWindows) {
      expect((await secretDirectory.stat()).modeString(), 'rwx------');
      for (final entity in secretFiles) {
        expect((await entity.stat()).modeString(), 'rw-------');
      }
    }
  });

  test(
    'SecureConfigStore exposes an explicit secrets write failure when durable secret storage is unavailable',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-secrets-memory-fallback-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final store = SecureConfigStore(
        databasePathResolver: () async => tempDirectory.path,
        fallbackDirectoryPathResolver: () async =>
            '/dev/null/xworkmate/secrets',
      );

      await store.saveGatewayToken('token-secret');

      expect(await store.loadGatewayToken(), 'token-secret');
      expect(store.persistentWriteFailures.secrets, isNotNull);
      expect(
        store.persistentWriteFailures.secrets?.scope,
        PersistentStoreScope.secrets,
      );
      expect(store.persistentWriteFailures.secrets?.operation, 'writeSecret');
      expect(
        store.persistentWriteFailures.secrets?.message,
        contains('Persistent secret'),
      );

      final reloadedStore = SecureConfigStore(
        databasePathResolver: () async => tempDirectory.path,
        fallbackDirectoryPathResolver: () async =>
            '/dev/null/xworkmate/secrets',
      );
      expect(await reloadedStore.loadGatewayToken(), isNull);
    },
  );

  test(
    'SecureConfigStore ignores legacy local-state files and keeps them untouched',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-local-state-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final databasePath = '${tempDirectory.path}/settings.sqlite3';
      final settingsFile = File('${tempDirectory.path}/settings-snapshot.json');
      final threadsFile = File('${tempDirectory.path}/assistant-threads.json');
      await settingsFile.writeAsString('{"accountUsername":"local-user"}');
      await threadsFile.writeAsString('[]');

      final firstStore = SecureConfigStore(
        databasePathResolver: () async => databasePath,
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
          updatedAtMs: 1700000000000,
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
        ),
      ];
      SharedPreferences.setMockInitialValues(<String, Object>{
        'xworkmate.settings.snapshot': legacySnapshot.toJsonString(),
        'xworkmate.assistant.threads': jsonEncode(
          legacyRecords.map((item) => item.toJson()).toList(growable: false),
        ),
      });
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-legacy-migrate-',
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
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-ignore-stray-files-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
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
              source:
                  '/Users/test/.agents/skills/calm_compact_workspace_system',
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
    expect(decoded.authorizedSkillDirectories.first.bookmark, 'bookmark-data');
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
    'SecureConfigStore restart keeps database state and legacy session files untouched',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-durable-restore-',
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
      await store.saveAssistantThreadRecords(records);
      final settingsFile = File('${tempDirectory.path}/settings-snapshot.json');
      final threadsFile = File('${tempDirectory.path}/assistant-threads.json');
      await settingsFile.writeAsString('legacy-settings-snapshot', flush: true);
      await threadsFile.writeAsString('legacy-assistant-threads', flush: true);

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
      expect(await settingsFile.readAsString(), 'legacy-settings-snapshot');
      expect(await threadsFile.readAsString(), 'legacy-assistant-threads');
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
        await File('${tempDirectory.path}/settings-snapshot.json').exists(),
        isFalse,
      );
      expect(
        await File('${tempDirectory.path}/assistant-threads.json').exists(),
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
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-config-store-clear-token-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final store = SecureConfigStore(
        databasePathResolver: () async =>
            '${tempDirectory.path}/${SettingsStore.databaseFileName}',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );

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
