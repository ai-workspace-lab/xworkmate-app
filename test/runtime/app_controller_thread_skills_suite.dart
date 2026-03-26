@TestOn('vm')
library;

import 'dart:io';

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
      final codexRoot = Directory('${tempDirectory.path}/codex-skills');
      final workbuddyRoot = Directory('${tempDirectory.path}/workbuddy-skills');
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
        codexRoot,
        'ppt',
        skillName: 'PPT',
        description: 'Presentation skill',
      );
      await _writeSkill(
        workbuddyRoot,
        'analysis',
        skillName: 'Analysis',
        description: 'WorkBuddy version wins',
      );
      await _writeSkill(
        workbuddyRoot,
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
          codexRoot.path,
          workbuddyRoot.path,
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
      expect(analysisSkill.description, 'WorkBuddy version wins');
      expect(analysisSkill.source, 'workbuddy');
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
    'AppController skips preset shared roots without bookmarks when the access service requires authorization',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-skill-directory-macos-preset-unauthorized-',
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
          requiresAuthorizedSharedRoots: true,
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
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .where((item) => item.label == 'Browser'),
        isEmpty,
      );
    },
  );

  test(
    'AppController scans preset shared roots with bookmarks when the access service requires authorization',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-skill-directory-macos-preset-authorized-',
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

      final store = await _createStore(tempDirectory.path);
      await store.saveSettingsSnapshot(
        _singleAgentTestSettings(workspacePath: tempDirectory.path).copyWith(
          authorizedSkillDirectories: <AuthorizedSkillDirectory>[
            AuthorizedSkillDirectory(
              path: agentsRoot.path,
              bookmark: 'bookmark-1',
            ),
          ],
        ),
      );
      final controller = AppController(
        store: store,
        skillDirectoryAccessService: _FakeSkillDirectoryAccessService(
          userHomeDirectory: userHome.path,
          requiresAuthorizedSharedRoots: true,
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

      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((item) => item.label),
        contains('Browser'),
      );
    },
  );

  test(
    'AppController skips custom shared directories without bookmarks when the access service requires authorization',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-skill-directory-macos-custom-unauthorized-',
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
      await _writeSkill(
        customRoot,
        'browser',
        skillName: 'Browser',
        description: 'Browser tasks',
      );

      final store = await _createStore(tempDirectory.path);
      await store.saveSettingsSnapshot(
        _singleAgentTestSettings(workspacePath: tempDirectory.path).copyWith(
          authorizedSkillDirectories: <AuthorizedSkillDirectory>[
            AuthorizedSkillDirectory(path: customRoot.path),
          ],
        ),
      );
      final controller = AppController(
        store: store,
        skillDirectoryAccessService: _FakeSkillDirectoryAccessService(
          userHomeDirectory: tempDirectory.path,
          requiresAuthorizedSharedRoots: true,
        ),
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
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .where((item) => item.label == 'Browser'),
        isEmpty,
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
      final codexRoot = Directory('${tempDirectory.path}/codex-skills');
      final workbuddyRoot = Directory('${tempDirectory.path}/workbuddy-skills');
      await _writeSkill(
        agentsRoot,
        'browser',
        skillName: 'Browser',
        description: 'Browser tasks',
      );
      await _writeSkill(
        codexRoot,
        'ppt',
        skillName: 'PPT',
        description: 'Presentation tasks',
      );
      await _writeSkill(
        workbuddyRoot,
        'wordx',
        skillName: 'WordX',
        description: 'Document tasks',
      );
      await _writeSkill(
        workbuddyRoot,
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
            codexRoot.path,
            workbuddyRoot.path,
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
      final workbuddyRoot = Directory('${tempDirectory.path}/workbuddy-skills');
      final workspaceRoot = Directory('${tempDirectory.path}/workspace');
      await _writeSkill(
        workbuddyRoot,
        'shared-skill',
        skillName: 'Shared Skill',
        description: 'Global wins',
      );
      await _writeSkill(
        workbuddyRoot,
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
        singleAgentSharedSkillScanRootOverrides: <String>[workbuddyRoot.path],
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

SettingsSnapshot _singleAgentTestSettings({required String workspacePath}) {
  final defaults = SettingsSnapshot.defaults();
  return defaults.copyWith(
    gatewayProfiles: replaceGatewayProfileAt(
      replaceGatewayProfileAt(
        defaults.gatewayProfiles,
        kGatewayLocalProfileIndex,
        defaults.primaryLocalGatewayProfile.copyWith(
          host: '127.0.0.1',
          port: 9,
          tls: false,
        ),
      ),
      kGatewayRemoteProfileIndex,
      defaults.primaryRemoteGatewayProfile.copyWith(
        host: '127.0.0.1',
        port: 9,
        tls: false,
      ),
    ),
    assistantExecutionTarget: AssistantExecutionTarget.singleAgent,
    workspacePath: workspacePath,
  );
}

class _FakeSkillDirectoryAccessService implements SkillDirectoryAccessService {
  _FakeSkillDirectoryAccessService({
    required this.userHomeDirectory,
    this.requiresAuthorizedSharedRoots = false,
  });

  final String userHomeDirectory;
  @override
  final bool requiresAuthorizedSharedRoots;

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
