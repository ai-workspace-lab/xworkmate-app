@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  test(
    'AppController shares single-agent skills across providers and applies root precedence',
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
        store: SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async =>
              '${tempDirectory.path}/settings.sqlite3',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        ),
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
          SingleAgentProvider.claude,
        ],
        singleAgentLocalSkillScanRoots: <String>[
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
      final firstSessionKey = controller.currentSessionKey;

      expect(
        controller.assistantImportedSkillsForSession(firstSessionKey),
        hasLength(4),
      );
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
      expect(
        controller.assistantImportedSkillsForSession(firstSessionKey),
        hasLength(4),
      );
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
      expect(
        controller
            .assistantSelectedSkillsForSession(firstSessionKey)
            .map((skill) => skill.label),
        const <String>['PPT'],
      );

      await controller.setSingleAgentProvider(SingleAgentProvider.auto);
      expect(
        controller.assistantImportedSkillsForSession(firstSessionKey),
        hasLength(4),
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

      SecureConfigStore createStore() {
        return SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async =>
              '${tempDirectory.path}/settings.sqlite3',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        );
      }

      AppController createController() {
        return AppController(
          store: createStore(),
          availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
            SingleAgentProvider.claude,
          ],
          singleAgentLocalSkillScanRoots: <String>[
            agentsRoot.path,
            codexRoot.path,
            workbuddyRoot.path,
          ],
        );
      }

      final controller = createController();
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      final taskA = controller.currentSessionKey;
      expect(controller.assistantImportedSkillsForSession(taskA), hasLength(4));
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
      final taskC = controller.currentSessionKey;
      await controller.toggleAssistantSkillForSession(
        taskC,
        controller
            .assistantImportedSkillsForSession(taskC)
            .firstWhere((skill) => skill.label == 'Browser')
            .key,
      );

      controller.initializeAssistantThreadContext(
        'draft:task-d',
        title: 'Task D',
        executionTarget: AssistantExecutionTarget.singleAgent,
        messageViewMode: AssistantMessageViewMode.rendered,
      );
      await controller.switchSession('draft:task-d');
      final taskD = controller.currentSessionKey;
      await controller.toggleAssistantSkillForSession(
        taskD,
        controller
            .assistantImportedSkillsForSession(taskD)
            .firstWhere((skill) => skill.label == 'CICD Audit')
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
      expect(
        controller
            .assistantSelectedSkillsForSession(taskD)
            .map((skill) => skill.label),
        const <String>['CICD Audit'],
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      controller.dispose();

      final restoredController = createController();
      addTearDown(restoredController.dispose);
      await _waitFor(() => !restoredController.initializing);
      await restoredController.switchSession(taskA);
      expect(
        restoredController
            .assistantSelectedSkillsForSession(taskA)
            .map((skill) => skill.label),
        const <String>['PPT'],
      );
      await restoredController.switchSession(taskB);
      expect(
        restoredController
            .assistantSelectedSkillsForSession(taskB)
            .map((skill) => skill.label),
        const <String>['WordX'],
      );
      await restoredController.switchSession(taskC);
      expect(
        restoredController
            .assistantSelectedSkillsForSession(taskC)
            .map((skill) => skill.label),
        const <String>['Browser'],
      );
      await restoredController.switchSession(taskD);
      expect(
        restoredController
            .assistantSelectedSkillsForSession(taskD)
            .map((skill) => skill.label),
        const <String>['CICD Audit'],
      );
    },
  );

  test(
    'AppController persists shared local skills cache and restores it on restart',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-single-agent-skills-cache-',
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

      SecureConfigStore createStore() {
        return SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async =>
              '${tempDirectory.path}/settings.sqlite3',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
          defaultSupportDirectoryPathResolver: () async => tempDirectory.path,
        );
      }

      final firstStore = createStore();
      final controller = AppController(
        store: firstStore,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentLocalSkillScanRoots: <String>[
          agentsRoot.path,
          codexRoot.path,
        ],
      );
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((item) => item.label),
        containsAll(const <String>['Browser', 'PPT']),
      );

      final cacheFile = await firstStore.supportFile(
        'cache/single-agent-local-skills.json',
      );
      expect(cacheFile, isNotNull);
      await _waitFor(() => cacheFile != null && cacheFile.existsSync());
      controller.dispose();

      if (await agentsRoot.exists()) {
        await agentsRoot.delete(recursive: true);
      }
      if (await codexRoot.exists()) {
        await codexRoot.delete(recursive: true);
      }

      final restoredController = AppController(
        store: createStore(),
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentLocalSkillScanRoots: <String>[
          agentsRoot.path,
          codexRoot.path,
        ],
      );
      addTearDown(restoredController.dispose);
      await _waitFor(() => !restoredController.initializing);
      await restoredController.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      expect(
        restoredController
            .assistantImportedSkillsForSession(
              restoredController.currentSessionKey,
            )
            .map((item) => item.label),
        containsAll(const <String>['Browser', 'PPT']),
      );
    },
  );

  test(
    'AppController uses settings.workspacePath as fallback for relative single-agent skill roots',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-workspace-local-skills-',
      );
      final currentWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-empty-current-workspace-',
      );
      final originalCurrentDirectory = Directory.current;
      addTearDown(() async {
        Directory.current = originalCurrentDirectory;
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
        if (await currentWorkspace.exists()) {
          try {
            await currentWorkspace.delete(recursive: true);
          } catch (_) {}
        }
      });
      Directory.current = currentWorkspace.path;

      await _writeSkill(
        Directory('${tempDirectory.path}/.codex/skills'),
        'workspace-only',
        skillName: 'Workspace Only Skill',
        description: 'Default workspace fallback should be discovered',
      );

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        SettingsSnapshot.defaults().copyWith(workspacePath: tempDirectory.path),
      );

      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentLocalSkillScanRoots: const <String>['.codex/skills'],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
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
    'AppController keeps high-priority user roots ahead of workspace fallbacks',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-priority-relative-skills-',
      );
      final currentWorkspace = Directory('${tempDirectory.path}/workspace');
      await currentWorkspace.create(recursive: true);
      final workbuddyRoot = Directory('${tempDirectory.path}/workbuddy-skills');
      await _writeSkill(
        workbuddyRoot,
        'shared-skill',
        skillName: 'Shared Skill',
        description: 'High-priority user root wins',
      );
      await _writeSkill(
        Directory('${currentWorkspace.path}/.codex/skills'),
        'shared-skill',
        skillName: 'Shared Skill',
        description: 'Workspace fallback should not override user roots',
      );

      final originalCurrentDirectory = Directory.current;
      addTearDown(() async {
        Directory.current = originalCurrentDirectory;
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      Directory.current = currentWorkspace.path;

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        SettingsSnapshot.defaults().copyWith(workspacePath: currentWorkspace.path),
      );

      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentLocalSkillScanRoots: <String>[
          workbuddyRoot.path,
          '.codex/skills',
        ],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      final sharedSkill = controller
          .assistantImportedSkillsForSession(controller.currentSessionKey)
          .firstWhere((item) => item.label == 'Shared Skill');
      expect(sharedSkill.description, 'High-priority user root wins');
      expect(sharedSkill.source, 'workbuddy');
    },
  );

  test(
    'AppController prefers current workspace roots over settings.workspacePath fallback',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-current-workspace-skills-',
      );
      final defaultWorkspace = Directory(
        '${tempDirectory.path}/default-workspace',
      );
      final currentWorkspace = Directory(
        '${tempDirectory.path}/current-workspace',
      );
      await currentWorkspace.create(recursive: true);
      await _writeSkill(
        Directory('${defaultWorkspace.path}/.codex/skills'),
        'shared-skill',
        skillName: 'Shared Skill',
        description: 'Default workspace fallback',
      );
      await _writeSkill(
        Directory('${currentWorkspace.path}/.codex/skills'),
        'shared-skill',
        skillName: 'Shared Skill',
        description: 'Current workspace wins',
      );

      final originalCurrentDirectory = Directory.current;
      addTearDown(() async {
        Directory.current = originalCurrentDirectory;
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      Directory.current = currentWorkspace.path;

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        SettingsSnapshot.defaults().copyWith(
          workspacePath: defaultWorkspace.path,
        ),
      );

      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentLocalSkillScanRoots: const <String>['.codex/skills'],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      final sharedSkill = controller
          .assistantImportedSkillsForSession(controller.currentSessionKey)
          .firstWhere((item) => item.label == 'Shared Skill');
      expect(sharedSkill.description, 'Current workspace wins');
    },
  );

  test(
    'AppController can return empty skills when relative roots have no matching workspace roots',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-empty-relative-skills-',
      );
      final emptyWorkspace = await Directory.systemTemp.createTemp(
        'xworkmate-empty-relative-current-workspace-',
      );
      final originalCurrentDirectory = Directory.current;
      addTearDown(() async {
        Directory.current = originalCurrentDirectory;
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
        if (await emptyWorkspace.exists()) {
          try {
            await emptyWorkspace.delete(recursive: true);
          } catch (_) {}
        }
      });
      Directory.current = emptyWorkspace.path;

      final store = SecureConfigStore(
        enableSecureStorage: false,
        databasePathResolver: () async => '${tempDirectory.path}/settings.sqlite3',
        fallbackDirectoryPathResolver: () async => tempDirectory.path,
      );
      await store.initialize();
      await store.saveSettingsSnapshot(
        SettingsSnapshot.defaults().copyWith(
          workspacePath: '',
        ),
      );

      final controller = AppController(
        store: store,
        availableSingleAgentProvidersOverride: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        singleAgentLocalSkillScanRoots: const <String>['.codex/skills'],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );

      expect(
        controller.assistantImportedSkillsForSession(controller.currentSessionKey),
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
