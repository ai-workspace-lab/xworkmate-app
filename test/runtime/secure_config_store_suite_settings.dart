// ignore_for_file: unused_import, unnecessary_import

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'secure_config_store_suite_core.dart';
import 'secure_config_store_suite_secrets.dart';
import 'secure_config_store_suite_compatibility.dart';
import 'secure_config_store_suite_lifecycle.dart';
import 'secure_config_store_suite_fixtures.dart';

void registerSecureConfigStoreSuiteSettingsTestsInternal() {
  group('Settings storage', () {
    test(
      'SecureConfigStore persists settings and secure refs in test runners',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);

        final snapshot = SettingsSnapshot.defaults().copyWith(
          accountUsername: 'tester',
          accountWorkspace: 'QA',
          codeAgentRuntimeMode: CodeAgentRuntimeMode.externalCli,
          codexCliPath: '/opt/homebrew/bin/codex',
          assistantNavigationDestinations: const <AssistantFocusEntry>[
            AssistantFocusEntry.aiGateway,
            AssistantFocusEntry.secrets,
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
          const <AssistantFocusEntry>[
            AssistantFocusEntry.aiGateway,
            AssistantFocusEntry.secrets,
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
      'SecureConfigStore persists sqlite-backed settings across instances',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-cross-instance-',
        );
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
        expect(
          writeFailures.settings?.message,
          contains('Persistent settings'),
        );
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

        await store.saveTaskThreads(<TaskThread>[
          TaskThread(
            sessionKey: 'draft:memory-only',
            title: 'Memory only',
            archived: false,
            executionTarget: AssistantExecutionTarget.local,
            messageViewMode: AssistantMessageViewMode.rendered,
            updatedAtMs: 1700000000000,
            messages: <GatewayChatMessage>[],
          ),
        ]);

        final loadedRecords = await store.loadTaskThreads();
        final writeFailures = store.persistentWriteFailures;

        expect(loadedRecords, hasLength(1));
        expect(loadedRecords.first.sessionKey, 'draft:memory-only');
        expect(writeFailures.tasks, isNotNull);
        expect(writeFailures.tasks?.scope, PersistentStoreScope.tasks);
        expect(writeFailures.tasks?.operation, 'saveTaskThreads');
        expect(writeFailures.tasks?.message, contains('Persistent task path'));
      },
    );

    test(
      'SecureConfigStore auto-creates an explicit settings directory on first install',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-missing-settings-path-',
        );
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
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-missing-secrets-path-',
        );
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

        expect(
          await Directory('${tempDirectory.path}/secrets').exists(),
          isTrue,
        );
        expect(await store.loadGatewayToken(), 'token-secret');
      },
    );

    test(
      'SecureConfigStore persists across instances using default support root when overrides fail',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-default-support-',
        );
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

    test(
      'SecureConfigStore persists multi-agent settings without secrets in snapshot json',
      () async {
        final tempDirectory = await createTempDirectoryInternal(
          'xworkmate-config-store-multi-agent-',
        );
        final store = createStoreFromTempDirectoryInternal(tempDirectory);

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
        expect(
          loadedSnapshot.multiAgent.arisBundleVersion,
          '2026-03-19-dd663c1',
        );
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
  });
}
