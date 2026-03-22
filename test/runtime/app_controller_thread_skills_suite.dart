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
    'AppController keeps gateway-only discovered skills as candidates until confirmed',
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
      final workbuddyRoot = Directory('${tempDirectory.path}/workbuddy-skills');
      await _writeSkill(
        codexRoot,
        'idea-discovery',
        skillName: 'Idea Discovery',
        description: 'Discover ideas',
      );
      await _writeSkill(
        workbuddyRoot,
        'release-checks',
        skillName: 'Release Checks',
        description: 'Run release checks',
      );

      final controller = AppController(
        store: SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async =>
              '${tempDirectory.path}/settings.sqlite3',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        ),
        gatewayOnlySkillScanRoots: <String>[
          codexRoot.path,
          codexRoot.path,
          workbuddyRoot.path,
        ],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);

      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.aiGatewayOnly,
      );

      final discoveredBefore = controller.assistantDiscoveredSkillsForSession(
        controller.currentSessionKey,
      );
      expect(discoveredBefore, hasLength(2));
      expect(
        controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
      );

      await controller.confirmImportedSkillsForSession(
        controller.currentSessionKey,
        discoveredBefore.map((item) => item.key).toList(growable: false),
      );

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
        hasLength(2),
      );
      expect(
        controller.assistantSelectedSkillKeysForSession(
          controller.currentSessionKey,
        ),
        hasLength(2),
      );
    },
  );

  test(
    'AppController keeps imported skills and model choices isolated per thread',
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
      await _writeSkill(
        codexRoot,
        'analysis',
        skillName: 'Analysis',
        description: 'Analyze tasks',
      );

      final controller = AppController(
        store: SecureConfigStore(
          enableSecureStorage: false,
          databasePathResolver: () async =>
              '${tempDirectory.path}/settings.sqlite3',
          fallbackDirectoryPathResolver: () async => tempDirectory.path,
        ),
        gatewayOnlySkillScanRoots: <String>[codexRoot.path],
      );
      addTearDown(controller.dispose);
      await _waitFor(() => !controller.initializing);

      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.aiGatewayOnly,
      );
      final firstSessionKey = controller.currentSessionKey;
      final discovered = controller.assistantDiscoveredSkillsForSession(
        firstSessionKey,
      );
      await controller.confirmImportedSkillsForSession(
        firstSessionKey,
        <String>[discovered.single.key],
      );
      await controller.selectAssistantModelForSession(
        firstSessionKey,
        'model-a',
      );

      controller.initializeAssistantThreadContext(
        'draft:thread-2',
        title: 'Thread 2',
        executionTarget: AssistantExecutionTarget.aiGatewayOnly,
        messageViewMode: AssistantMessageViewMode.rendered,
      );
      await controller.switchSession('draft:thread-2');
      await controller.selectAssistantModelForSession(
        controller.currentSessionKey,
        'model-b',
      );

      expect(
        controller.assistantImportedSkillsForSession(
          controller.currentSessionKey,
        ),
        isEmpty,
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
