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
