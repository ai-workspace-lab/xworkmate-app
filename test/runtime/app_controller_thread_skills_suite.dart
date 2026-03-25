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
    'AppController maps Single Agent skills by provider with agents as common source',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tempDirectory = await Directory.systemTemp.createTemp(
        'xworkmate-thread-skills-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          try {
            await tempDirectory.delete(recursive: true);
          } catch (_) {}
        }
      });
      final workspaceCodexRoot = Directory(
        '${tempDirectory.path}/workspace/.codex/skills',
      );
      final userCodexRoot = Directory(
        '${tempDirectory.path}/user-codex-skills',
      );
      final userClaudeRoot = Directory(
        '${tempDirectory.path}/user-claude-skills',
      );
      final userAgentsRoot = Directory(
        '${tempDirectory.path}/user-agents-skills',
      );
      await _writeSkill(
        workspaceCodexRoot,
        'idea-discovery',
        skillName: 'Idea Discovery',
        description: 'Workspace skill wins',
      );
      await _writeSkill(
        userCodexRoot,
        'idea-discovery',
        skillName: 'Idea Discovery',
        description: 'User skill should be overridden',
      );
      await _writeSkill(
        userClaudeRoot,
        'incident-review',
        skillName: 'Incident Review',
        description: 'Review incidents',
      );
      await _writeSkill(
        userAgentsRoot,
        'shared-utilities',
        skillName: 'Shared Utilities',
        description: 'Common utilities',
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
          '${tempDirectory.path}/workspace/.codex/skills',
          userCodexRoot.path,
          userClaudeRoot.path,
          userAgentsRoot.path,
        ],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await controller.setSingleAgentProvider(SingleAgentProvider.codex);
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((skill) => skill.label),
        containsAll(const <String>['Idea Discovery', 'Shared Utilities']),
      );
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((skill) => skill.label),
        isNot(contains('Incident Review')),
      );
      expect(
        controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        ),
        hasLength(2),
      );
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .firstWhere((skill) => skill.label == 'Idea Discovery')
            .description,
        'Workspace skill wins',
      );
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .firstWhere((skill) => skill.label == 'Idea Discovery')
            .scope,
        'workspace',
      );
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .firstWhere((skill) => skill.label == 'Shared Utilities')
            .source,
        'agents',
      );
      await controller.toggleAssistantSkillForSession(
        controller.currentSessionKey,
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .firstWhere((skill) => skill.label == 'Idea Discovery')
            .key,
      );
      expect(
        controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        ),
        hasLength(1),
      );

      await controller.setSingleAgentProvider(SingleAgentProvider.claude);
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((skill) => skill.label),
        containsAll(const <String>['Incident Review', 'Shared Utilities']),
      );
      expect(
        controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((skill) => skill.label),
        isNot(contains('Idea Discovery')),
      );

      await controller.setSingleAgentProvider(SingleAgentProvider.auto);
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .map((skill) => skill.label),
        containsAll(const <String>[
          'Idea Discovery',
          'Incident Review',
          'Shared Utilities',
        ]),
      );

      expect(
        controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );
    },
  );

  test('AppController keeps thread-bound skills isolated per thread', () async {
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
    final codexRoot = Directory('${tempDirectory.path}/codex-skills');
    final claudeRoot = Directory('${tempDirectory.path}/claude-skills');
    final agentsRoot = Directory('${tempDirectory.path}/agents-skills');
    await _writeSkill(
      codexRoot,
      'analysis',
      skillName: 'Analysis',
      description: 'Analyze tasks',
    );
    await _writeSkill(
      claudeRoot,
      'review',
      skillName: 'Review',
      description: 'Review tasks',
    );
    await _writeSkill(
      agentsRoot,
      'shared',
      skillName: 'Shared',
      description: 'Shared tasks',
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
        codexRoot.path,
        claudeRoot.path,
        agentsRoot.path,
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
      hasLength(2),
    );
    await controller.toggleAssistantSkillForSession(
      firstSessionKey,
      controller
          .assistantImportedSkillsForSession(firstSessionKey)
          .firstWhere((skill) => skill.label == 'Analysis')
          .key,
    );

    controller.initializeAssistantThreadContext(
      'draft:thread-2',
      title: 'Thread 2',
      executionTarget: AssistantExecutionTarget.singleAgent,
      messageViewMode: AssistantMessageViewMode.rendered,
      singleAgentProvider: SingleAgentProvider.claude,
    );
    await controller.switchSession('draft:thread-2');
    expect(
      controller
          .assistantImportedSkillsForSession(controller.currentSessionKey)
          .map((skill) => skill.label),
      containsAll(const <String>['Review', 'Shared']),
    );
    expect(
      controller.assistantImportedSkillsForSession(
        controller.currentSessionKey,
      ),
      hasLength(2),
    );
    expect(
      controller.assistantSelectedSkillKeysForSession(
        controller.currentSessionKey,
      ),
      isEmpty,
    );
    await controller.switchSession(firstSessionKey);

    expect(
      controller.assistantImportedSkillsForSession(firstSessionKey),
      hasLength(2),
    );
    expect(
      controller
          .assistantImportedSkillsForSession(firstSessionKey)
          .map((skill) => skill.label),
      containsAll(const <String>['Analysis', 'Shared']),
    );
    expect(
      controller.assistantSelectedSkillKeysForSession(firstSessionKey),
      hasLength(1),
    );
  });
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
