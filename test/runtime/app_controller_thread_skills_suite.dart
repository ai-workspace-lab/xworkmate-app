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
    'AppController loads Single Agent skills from the current thread provider roots',
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
      final codexRoot = Directory('${tempDirectory.path}/codex-skills');
      final claudeRoot = Directory('${tempDirectory.path}/claude-skills');
      await _writeSkill(
        codexRoot,
        'idea-discovery',
        skillName: 'Idea Discovery',
        description: 'Discover ideas',
      );
      await _writeSkill(
        claudeRoot,
        'incident-review',
        skillName: 'Incident Review',
        description: 'Review incidents',
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
        gatewayOnlySkillScanRoots: <String>[
          codexRoot.path,
          claudeRoot.path,
        ],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.singleAgent,
      );
      await controller.setSingleAgentProvider(SingleAgentProvider.codex);

      expect(
        controller.assistantDiscoveredSkillsForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );
      expect(
        controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        ),
        hasLength(1),
      );
      expect(
        controller
            .assistantImportedSkillsForSession(controller.currentSessionKey)
            .single
            .label,
        'Idea Discovery',
      );

      expect(
        controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );
    },
  );

  test(
    'AppController keeps provider-owned imported skills and model choices isolated per thread',
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
      final codexRoot = Directory('${tempDirectory.path}/codex-skills');
      final claudeRoot = Directory('${tempDirectory.path}/claude-skills');
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
        gatewayOnlySkillScanRoots: <String>[codexRoot.path, claudeRoot.path],
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
        hasLength(1),
      );
      await controller.toggleAssistantSkillForSession(
        firstSessionKey,
        controller
            .assistantImportedSkillsForSession(firstSessionKey)
            .single
            .key,
      );
      await controller.selectAssistantModelForSession(
        firstSessionKey,
        'model-a',
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
        controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        ).single.label,
        'Review',
      );
      await controller.selectAssistantModelForSession(
        controller.currentSessionKey,
        'model-b',
      );

      expect(
        controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        ),
        hasLength(1),
      );
      expect(
        controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );
      expect(
        controller.assistantModelForSession(controller.currentSessionKey),
        'model-b',
      );

      await controller.switchSession(firstSessionKey);

      expect(
        controller.assistantImportedSkillsForSession(firstSessionKey),
        hasLength(1),
      );
      expect(
        controller.assistantSelectedSkillKeysForSession(firstSessionKey),
        hasLength(1),
      );
      expect(controller.assistantModelForSession(firstSessionKey), 'model-a');
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
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
