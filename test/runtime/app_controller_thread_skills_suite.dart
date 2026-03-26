@TestOn('vm')
library;

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';
import 'package:xworkmate/runtime/skill_directory_access.dart';

void main() {
  test(
    'AppController scans shared single-agent public roots on startup and shares them across providers',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-single-agent-shared-skills-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final systemRoot = Directory('${tempDirectory.path}/etc-skills');
      final agentsRoot = Directory('${tempDirectory.path}/agents-skills');
      final customRootA = Directory('${tempDirectory.path}/custom-skills-a');
      final customRootB = Directory('${tempDirectory.path}/custom-skills-b');
      await _writeSkill(
        systemRoot,
        'analysis',
        skillName: 'Analysis',
        description: 'System version should be overridden',
      );
      await _writeSkill(
        agentsRoot,
        'browser',
        skillName: 'Browser Automation',
        description: 'Shared browser skill',
      );
      await _writeSkill(
        customRootA,
        'ppt',
        skillName: 'PPT',
        description: 'Presentation skill',
      );
      await _writeSkill(
        customRootB,
        'analysis',
        skillName: 'Analysis',
        description: 'Custom version wins',
      );
      await _writeSkill(
        customRootB,
        'cicd-audit',
        skillName: 'CICD Audit',
        description: 'Pipeline audit skill',
      );

      final controller = AppController(
        store: await _createStore(tempDirectory.path),
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
          SingleAgentProvider.claude,
        ],
        singleAgentSharedSkillScanRootOverrides: <String>[
          systemRoot.path,
          agentsRoot.path,
          customRootA.path,
          customRootB.path,
        ],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await controller.setSingleAgentProvider(SingleAgentProvider.codex);
      await _waitFor(
        () =>
            controller
                .assistantImportedSkillsForSession(controller.currentSessionKey)
                .length ==
            4,
      );

      final firstSessionKey = controller.currentSessionKey;
      expect(
        controller
            .assistantImportedSkillsForSession(firstSessionKey)
            .map((skill) => skill.label),
        containsAll(const <String>[
          'Analysis',
          'Browser Automation',
          'PPT',
          'CICD Audit',
        ]),
      );
      final analysisSkill = controller
          .assistantImportedSkillsForSession(firstSessionKey)
          .firstWhere((skill) => skill.label == 'Analysis');
      expect(analysisSkill.description, 'Custom version wins');
      expect(analysisSkill.source, 'custom');
      expect(analysisSkill.scope, 'user');

      await controller.toggleAssistantSkillForSession(
        firstSessionKey,
        controller
            .assistantImportedSkillsForSession(firstSessionKey)
            .firstWhere((skill) => skill.label == 'PPT')
            .key,
      );
      expect(
        controller
            .assistantSelectedSkillsForSession(firstSessionKey)
            .map((skill) => skill.label),
        const <String>['PPT'],
      );

      await controller.setSingleAgentProvider(SingleAgentProvider.claude);
      await _waitFor(
        () =>
            controller
                .assistantImportedSkillsForSession(firstSessionKey)
                .length ==
            4,
      );
      expect(
        controller
            .assistantSelectedSkillsForSession(firstSessionKey)
            .map((skill) => skill.label),
        const <String>['PPT'],
      );
    },
  );

  test(
    'AppController hot reloads authorized custom skill directories from settings.yaml',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-skill-directory-hot-reload-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final agentsRoot = Directory('${tempDirectory.path}/agents-skills');
      await _writeSkill(
        agentsRoot,
        'browser',
        skillName: 'Browser',
        description: 'Browser tasks',
      );

      final store = await _createStore(tempDirectory.path);
      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentSharedSkillScanRootOverrides: const <String>[],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .where((skill) => skill.label == 'Browser'),
        isEmpty,
      );

      final updatedSnapshot =
          _singleAgentTestSettings(workspacePath: tempDirectory.path).copyWith(
            authorizedSkillDirectories: <AuthorizedSkillDirectory>[
              AuthorizedSkillDirectory(path: agentsRoot.path),
            ],
          );
      final settingsFile = File('${tempDirectory.path}/config/settings.yaml');
      await settingsFile.writeAsString(
        encodeYamlDocument(updatedSnapshot.toJson()),
        flush: true,
      );

      await _waitFor(
        () => controller.authorizedSkillDirectories
            .map((item) => item.path)
            .contains(agentsRoot.path),
      );
      await _waitFor(
        () => controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .any((skill) => skill.label == 'Browser'),
      );
      expect(
        controller.authorizedSkillDirectories.map((item) => item.path),
        <String>[agentsRoot.path],
      );
    },
  );

  test(
    'AppController resolves preset shared roots against the access service home directory',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-skill-directory-home-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final userHome = Directory('${tempDirectory.path}/real-home');
      final agentsRoot = Directory('${userHome.path}/.agents/skills');
      await _writeSkill(
        agentsRoot,
        'browser',
        skillName: 'Browser',
        description: 'Browser tasks',
      );

      final controller = AppController(
        store: await _createStore(tempDirectory.path),
        skillDirectoryAccessService: _FakeSkillDirectoryAccessService(
          userHomeDirectory: userHome.path,
        ),
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentSharedSkillScanRootOverrides: const <String>[
          '~/.agents/skills',
        ],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await _waitFor(
        () => controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .any((item) => item.label == 'Browser'),
      );

      expect(controller.userHomeDirectory, userHome.path);
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((item) => item.label),
        contains('Browser'),
      );
    },
  );

  test(
    'AppController keeps thread-bound skills isolated and restores them after restart',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-isolation-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final agentsRoot = Directory('${tempDirectory.path}/agents-skills');
      final customRootA = Directory('${tempDirectory.path}/custom-skills-a');
      final customRootB = Directory('${tempDirectory.path}/custom-skills-b');
      await _writeSkill(
        agentsRoot,
        'browser',
        skillName: 'Browser',
        description: 'Browser tasks',
      );
      await _writeSkill(
        customRootA,
        'ppt',
        skillName: 'PPT',
        description: 'Presentation tasks',
      );
      await _writeSkill(
        customRootB,
        'wordx',
        skillName: 'WordX',
        description: 'Document tasks',
      );
      await _writeSkill(
        customRootB,
        'cicd-audit',
        skillName: 'CICD Audit',
        description: 'Pipeline tasks',
      );

      Future<SecureConfigStore> createStore() {
        return _createStore(tempDirectory.path);
      }

      Future<AppController> createController() async {
        return AppController(
          store: await createStore(),
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
            SingleAgentProvider.claude,
          ],
          singleAgentSharedSkillScanRootOverrides: <String>[
            agentsRoot.path,
            customRootA.path,
            customRootB.path,
          ],
        );
      }

      final controller = await createController();
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await _waitFor(
        () =>
            controller
                .assistantImportedSkillsForSession(controller.currentSessionKey)
                .length ==
            4,
      );
      final taskA = controller.currentSessionKey;
      await controller.toggleAssistantSkillForSession(
        taskA,
        controller
            .assistantImportedSkillsForSession(taskA)
            .firstWhere((skill) => skill.label == 'PPT')
            .key,
      );

      controller.initializeAssistantThreadContext(
        'draft:task-b',
        title: 'Task B',
        executionTarget: AssistantExecutionTarget.singleAgent,
        messageViewMode: AssistantMessageViewMode.rendered,
        singleAgentProvider: SingleAgentProvider.claude,
      );
      await controller.switchSession('draft:task-b');
      await _waitFor(
        () =>
            controller
                .assistantImportedSkillsForSession(controller.currentSessionKey)
                .length ==
            4,
      );
      final taskB = controller.currentSessionKey;
      await controller.toggleAssistantSkillForSession(
        taskB,
        controller
            .assistantImportedSkillsForSession(taskB)
            .firstWhere((skill) => skill.label == 'WordX')
            .key,
      );

      controller.initializeAssistantThreadContext(
        'draft:task-c',
        title: 'Task C',
        executionTarget: AssistantExecutionTarget.singleAgent,
        messageViewMode: AssistantMessageViewMode.rendered,
      );
      await controller.switchSession('draft:task-c');
      await _waitFor(
        () =>
            controller
                .assistantImportedSkillsForSession(controller.currentSessionKey)
                .length ==
            4,
      );
      final taskC = controller.currentSessionKey;
      await controller.toggleAssistantSkillForSession(
        taskC,
        controller
            .assistantImportedSkillsForSession(taskC)
            .firstWhere((skill) => skill.label == 'Browser')
            .key,
      );

      expect(
        controller
            .assistantSelectedSkillsForSession(taskA)
            .map((skill) => skill.label),
        const <String>['PPT'],
      );
      expect(
        controller
            .assistantSelectedSkillsForSession(taskB)
            .map((skill) => skill.label),
        const <String>['WordX'],
      );
      expect(
        controller
            .assistantSelectedSkillsForSession(taskC)
            .map((skill) => skill.label),
        const <String>['Browser'],
      );

      controller.dispose();

      final restoredController = await createController();
      addTearDown(restoredController.dispose);
      await _waitFor(() => !restoredController.initializing);
      await restoredController.switchSession(taskA);
      await _waitFor(
        () =>
            restoredController
                .assistantImportedSkillsForSession(taskA)
                .length ==
            4,
      );
      expect(
        restoredController
            .assistantSelectedSkillsForSession(taskA)
            .map((skill) => skill.label),
        const <String>['PPT'],
      );
      await restoredController.switchSession(taskB);
      await _waitFor(
        () =>
            restoredController
                .assistantImportedSkillsForSession(taskB)
                .length ==
            4,
      );
      expect(
        restoredController
            .assistantSelectedSkillsForSession(taskB)
            .map((skill) => skill.label),
        const <String>['WordX'],
      );
      await restoredController.switchSession(taskC);
      await _waitFor(
        () =>
            restoredController
                .assistantImportedSkillsForSession(taskC)
                .length ==
            4,
      );
      expect(
        restoredController
            .assistantSelectedSkillsForSession(taskC)
            .map((skill) => skill.label),
        const <String>['Browser'],
      );
    },
  );

  test(
    'AppController uses thread workspaceRef for repo-local fallback',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-workspace-ref-skills-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final workspaceRoot = Directory('${tempDirectory.path}/workspace');
      await _writeSkill(
        Directory('${workspaceRoot.path}/skills'),
        'workspace-only',
        skillName: 'Workspace Only Skill',
        description: 'Repo-local fallback',
      );
      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async =>
            '${tempDirectory.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
        defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        _singleAgentTestSettings(
          workspacePath: '${tempDirectory.path}/unused-default-workspace',
        ),
      );
      await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'main',
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 1,
          title: '',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          workspaceRef: workspaceRoot.path,
          workspaceRefKind: WorkspaceRefKind.localPath,
        ),
      ]);

      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentSharedSkillScanRootOverrides: const <String>[],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await _waitFor(
        () => controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .any((item) => item.label == 'Workspace Only Skill'),
      );

      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((item) => item.label),
        contains('Workspace Only Skill'),
      );
    },
  );

  test(
    'AppController keeps public roots ahead of repo-local fallback and only fills missing skills',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-global-overrides-repo-local-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final customRoot = Directory(
        '${tempDirectory.path}/custom-shared-skills',
      );
      final workspaceRoot = Directory('${tempDirectory.path}/workspace');
      await _writeSkill(
        customRoot,
        'shared-skill',
        skillName: 'Shared Skill',
        description: 'Global wins',
      );
      await _writeSkill(
        customRoot,
        'global-only',
        skillName: 'Global Only',
        description: 'Only from global',
      );
      await _writeSkill(
        Directory('${workspaceRoot.path}/skills'),
        'shared-skill',
        skillName: 'Shared Skill',
        description: 'Repo-local should not override',
      );
      await _writeSkill(
        Directory('${workspaceRoot.path}/skills'),
        'workspace-only',
        skillName: 'Workspace Only',
        description: 'Only from workspace',
      );

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async =>
            '${tempDirectory.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
        defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        _singleAgentTestSettings(workspacePath: tempDirectory.path),
      );
      await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'main',
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 1,
          title: '',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          workspaceRef: workspaceRoot.path,
          workspaceRefKind: WorkspaceRefKind.localPath,
        ),
      ]);

      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentSharedSkillScanRootOverrides: <String>[customRoot.path],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await _waitFor(
        () =>
            controller
                .assistantImportedSkillsForSession(controller.currentSessionKey)
                .length ==
            3,
      );

      final sharedSkill = controller
          .assistantImportedSkillsForSession(controller.currentSessionKey)
          .firstWhere((item) => item.label == 'Shared Skill');
      expect(sharedSkill.description, 'Global wins');
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((item) => item.label),
        containsAll(const <String>[
          'Shared Skill',
          'Global Only',
          'Workspace Only',
        ]),
      );
    },
  );

  test(
    'AppController scans repo-local skills from workspace skills directory only',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-repo-local-order-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final workspaceRoot = Directory('${tempDirectory.path}/workspace');
      await _writeSkill(
        Directory('${workspaceRoot.path}/skills'),
        'shared-skill',
        skillName: 'Shared Skill',
        description: 'Workspace version wins',
      );
      await _writeSkill(
        Directory('${workspaceRoot.path}/.codex/skills'),
        'legacy-only',
        skillName: 'Legacy Only',
        description: 'Deprecated workspace root should be ignored',
      );

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async =>
            '${tempDirectory.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
        defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        _singleAgentTestSettings(workspacePath: tempDirectory.path),
      );
      await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'main',
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 1,
          title: '',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          workspaceRef: workspaceRoot.path,
          workspaceRefKind: WorkspaceRefKind.localPath,
        ),
      ]);

      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentSharedSkillScanRootOverrides: const <String>[],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await _waitFor(
        () => controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .isNotEmpty,
      );

      final sharedSkill = controller
          .assistantImportedSkillsForSession(controller.currentSessionKey)
          .firstWhere((item) => item.label == 'Shared Skill');
      expect(sharedSkill.description, 'Workspace version wins');
      expect(sharedSkill.source, 'workspace');
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .where((item) => item.label == 'Legacy Only'),
        isEmpty,
      );
    },
  );

  test(
    'AppController merges ACP skills after shared roots and workspace skills',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-acp-skill-merge-',
      );
      final acpServer = await _AcpSkillsStatusServer.start(
        skills: const <Map<String, dynamic>>[
          <String, dynamic>{
            'skillKey': 'acp-shared',
            'name': 'Shared Skill',
            'description': 'ACP should not override shared',
            'source': 'acp',
          },
          <String, dynamic>{
            'skillKey': 'acp-workspace',
            'name': 'Workspace Skill',
            'description': 'ACP should not override workspace',
            'source': 'acp',
          },
          <String, dynamic>{
            'skillKey': 'acp-only',
            'name': 'ACP Only',
            'description': 'Only from ACP',
            'source': 'acp',
          },
        ],
      );
      addTearDown(acpServer.close);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });

      final customRoot = Directory(
        '${tempDirectory.path}/custom-shared-skills',
      );
      final workspaceRoot = Directory('${tempDirectory.path}/workspace');
      await _writeSkill(
        customRoot,
        'shared-skill',
        skillName: 'Shared Skill',
        description: 'Shared root wins',
      );
      await _writeSkill(
        Directory('${workspaceRoot.path}/skills'),
        'workspace-skill',
        skillName: 'Workspace Skill',
        description: 'Workspace wins',
      );

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async =>
            '${tempDirectory.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
        defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        _singleAgentTestSettings(
          workspacePath: tempDirectory.path,
          gatewayPort: acpServer.port,
        ),
      );
      await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'main',
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 1,
          title: '',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          workspaceRef: workspaceRoot.path,
          workspaceRefKind: WorkspaceRefKind.localPath,
        ),
      ]);

      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentSharedSkillScanRootOverrides: <String>[customRoot.path],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await _waitFor(
        () => controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .any((item) => item.label == 'ACP Only'),
      );

      final importedSkills = controller.assistantImportedSkillsForSession(
        controller.currentSessionKey,
      );
      expect(
        importedSkills.map((item) => item.label),
        containsAll(const <String>[
          'Shared Skill',
          'Workspace Skill',
          'ACP Only',
        ]),
      );
      expect(
        importedSkills.firstWhere((item) => item.label == 'Shared Skill'),
        isA<AssistantThreadSkillEntry>()
            .having(
              (item) => item.description,
              'description',
              'Shared root wins',
            )
            .having((item) => item.source, 'source', 'custom'),
      );
      expect(
        importedSkills.firstWhere((item) => item.label == 'Workspace Skill'),
        isA<AssistantThreadSkillEntry>()
            .having((item) => item.description, 'description', 'Workspace wins')
            .having((item) => item.source, 'source', 'workspace'),
      );
      expect(
        importedSkills.firstWhere((item) => item.label == 'ACP Only'),
        isA<AssistantThreadSkillEntry>()
            .having((item) => item.description, 'description', 'Only from ACP')
            .having((item) => item.source, 'source', 'acp'),
      );
    },
  );

  test(
    'AppController clears stale ACP-only skills when ACP refresh fails',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-acp-skill-error-',
      );
      final acpServer = await _AcpSkillsStatusServer.start(
        skills: const <Map<String, dynamic>>[
          <String, dynamic>{
            'skillKey': 'acp-only',
            'name': 'ACP Only',
            'description': 'Only from ACP',
            'source': 'acp',
          },
        ],
      );
      addTearDown(acpServer.close);
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });

      final customRoot = Directory(
        '${tempDirectory.path}/custom-shared-skills',
      );
      await _writeSkill(
        customRoot,
        'local-only',
        skillName: 'Local Only',
        description: 'Only from local scan',
      );

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async =>
            '${tempDirectory.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
        defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        _singleAgentTestSettings(
          workspacePath: tempDirectory.path,
          gatewayPort: acpServer.port,
        ),
      );

      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentSharedSkillScanRootOverrides: <String>[customRoot.path],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await _waitFor(
        () => controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .any((item) => item.label == 'ACP Only'),
      );

      acpServer.skillsError = <String, dynamic>{
        'code': -32001,
        'message': 'skills refresh failed',
      };
      await controller.refreshSingleAgentSkillsForSession(
        controller.currentSessionKey,
      );

      final importedSkills = controller.assistantImportedSkillsForSession(
        controller.currentSessionKey,
      );
      expect(importedSkills.map((item) => item.label), const <String>[
        'Local Only',
      ]);
    },
  );

  test(
    'AppController can return empty skills when neither public nor repo-local roots exist',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-empty-relative-skills-',
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
        databasePathResolver: () async =>
            '${tempDirectory.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
        defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        _singleAgentTestSettings(
          workspacePath: '${tempDirectory.path}/missing-workspace',
        ),
      );
      await store.saveAssistantThreadRecords(<AssistantThreadRecord>[
        AssistantThreadRecord(
          sessionKey: 'main',
          messages: const <GatewayChatMessage>[],
          updatedAtMs: 1,
          title: '',
          archived: false,
          executionTarget: AssistantExecutionTarget.singleAgent,
          messageViewMode: AssistantMessageViewMode.rendered,
          workspaceRef: '${tempDirectory.path}/missing-workspace',
          workspaceRefKind: WorkspaceRefKind.localPath,
        ),
      ]);

      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentSharedSkillScanRootOverrides: const <String>[],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await _waitFor(
        () => controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .isEmpty,
      );

      expect(
        controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );
    },
  );
}

Future<void> _writeSkill(
  Directory root,
  String folderName, {
  required String description,
  required String skillName,
}) async {
  final directory = Directory('${root.path}/$folderName');
  await directory.create(recursive: true);
  await File(
    '${directory.path}/SKILL.md',
  ).writeAsString('---\nname: $skillName\ndescription: $description\n---\n');
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<SecureConfigStore> _createStore(String rootPath) async {
  final store = SecureConfigStore(
    enableSecureStorage: false,
    databasePathResolver: () async => '$rootPath/settings.sqlite3',
    fallbackDirectoryPathResolver: () async => rootPath,
    defaultSupportDirectoryPathResolver: () async => rootPath,
  );
  await store.initialize();
  await store.saveSettingsSnapshot(
    _singleAgentTestSettings(workspacePath: rootPath),
  );
  return store;
}

SettingsSnapshot _singleAgentTestSettings({
  required String workspacePath,
  int gatewayPort = 9,
}) {
  final defaults = SettingsSnapshot.defaults();
  return defaults.copyWith(
    gatewayProfiles: replaceGatewayProfileAt(
      replaceGatewayProfileAt(
        defaults.gatewayProfiles,
        kGatewayLocalProfileIndex,
        defaults.primaryLocalGatewayProfile.copyWith(
          host: '127.0.0.1',
          port: gatewayPort,
          tls: false,
        ),
      ),
      kGatewayRemoteProfileIndex,
      defaults.primaryRemoteGatewayProfile.copyWith(
        host: '127.0.0.1',
        port: gatewayPort,
        tls: false,
      ),
    ),
    assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
    workspacePath: workspacePath,
  );
}

class _FakeSkillDirectoryAccessService implements SkillDirectoryAccessService {
  _FakeSkillDirectoryAccessService({required this.userHomeDirectory});

  final String userHomeDirectory;

  @override
  bool get isSupported => true;

  @override
  Future<String> resolveUserHomeDirectory() async {
    return userHomeDirectory;
  }

  @override
  Future<List<AuthorizedSkillDirectory>> authorizeDirectories({
    List<String> suggestedPaths = const <String>[],
  }) async {
    return const <AuthorizedSkillDirectory>[];
  }

  @override
  Future<AuthorizedSkillDirectory?> authorizeDirectory({
    String suggestedPath = '',
  }) async {
    final normalized = normalizeAuthorizedSkillDirectoryPath(suggestedPath);
    if (normalized.isEmpty) {
      return null;
    }
    return AuthorizedSkillDirectory(path: normalized);
  }

  @override
  Future<SkillDirectoryAccessHandle?> openDirectory(
    AuthorizedSkillDirectory directory,
  ) async {
    final normalized = normalizeAuthorizedSkillDirectoryPath(directory.path);
    if (normalized.isEmpty) {
      return null;
    }
    return SkillDirectoryAccessHandle(path: normalized, onClose: () async {});
  }
}

class _AcpSkillsStatusServer {
  _AcpSkillsStatusServer._(this._server, {required this.skills});

  final HttpServer _server;
  List<Map<String, dynamic>> skills;
  Map<String, dynamic>? skillsError;

  int get port => _server.port;

  static Future<_AcpSkillsStatusServer> start({
    required List<Map<String, dynamic>> skills,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _AcpSkillsStatusServer._(
      server,
      skills: skills.map((item) => Map<String, dynamic>.from(item)).toList(),
    );
    unawaited(fake._listen());
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _listen() async {
    await for (final request in _server) {
      if (request.uri.path == '/acp/rpc' && request.method == 'POST') {
        await _handleRpc(request);
        continue;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  Future<void> _handleRpc(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final envelope = jsonDecode(body) as Map<String, dynamic>;
    final id = envelope['id'];
    final method = envelope['method']?.toString().trim() ?? '';

    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      'text/event-stream',
    );
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

    switch (method) {
      case 'acp.capabilities':
        await _writeSse(request, <String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{
            'singleAgent': true,
            'multiAgent': true,
            'providers': const <String>['codex'],
            'capabilities': <String, dynamic>{
              'single_agent': true,
              'multi_agent': true,
              'providers': const <String>['codex'],
            },
          },
        });
        return;
      case 'skills.status':
        if (skillsError != null) {
          await _writeSse(request, <String, dynamic>{
            'jsonrpc': '2.0',
            'id': id,
            'error': skillsError,
          });
          return;
        }
        await _writeSse(request, <String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{'skills': skills},
        });
        return;
      default:
        await _writeSse(request, <String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32601,
            'message': 'unknown method: $method',
          },
        });
    }
  }

  Future<void> _writeSse(
    HttpRequest request,
    Map<String, dynamic> payload,
  ) async {
    request.response.write('data: ${jsonEncode(payload)}\n\n');
    await request.response.flush();
    await request.response.close();
  }
}
