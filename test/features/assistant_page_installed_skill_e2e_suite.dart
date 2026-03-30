@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

import 'assistant_page_suite_support.dart';

void main() {
  group('AssistantPage installed skill E2E harness', () {
    for (final testCase in installedSkillE2ECasesInternal) {
      test(
        'discovers, binds, hands off, and captures ${testCase.skillKey}',
        () async {
          final tempDirectory = await Directory.systemTemp.createTemp(
            'xworkmate-installed-skill-${testCase.skillKey}-',
          );
          addTearDown(() async {
            if (await tempDirectory.exists()) {
              try {
                await tempDirectory.delete(recursive: true);
              } catch (_) {}
            }
          });

          final skillsRoot = Directory(
            '${tempDirectory.path}/installed-skills',
          );
          await seedInstalledSkillE2ERootInternal(skillsRoot);

          final controller = await createInstalledSkillE2EControllerInternal(
            tempDirectory: tempDirectory,
            skillsRoot: skillsRoot,
          );

          final importedSkills = controller.assistantImportedSkillsForSession(
            controller.currentSessionKey,
          );
          final importedLabels = importedSkills
              .map((item) => item.label)
              .toList(growable: false);

          expect(
            importedLabels,
            containsAll(
              installedSkillE2ECasesInternal
                  .map((item) => item.skillLabel)
                  .toList(growable: false),
            ),
          );

          final selectedEntry = importedSkills.firstWhere(
            (item) => item.label == testCase.skillLabel,
          );
          expect(selectedEntry.source, 'custom');
          expect(selectedEntry.scope, 'user');
          expect(selectedEntry.sourcePath, endsWith('SKILL.md'));
          expect(selectedEntry.sourceLabel, isNotEmpty);

          await controller.toggleAssistantSkillForSession(
            controller.currentSessionKey,
            selectedEntry.key,
          );
          expect(
            controller.assistantSelectedSkillKeysForSession(
              controller.currentSessionKey,
            ),
            <String>[selectedEntry.key],
          );

          final sendFuture = controller.sendChatMessage(
            testCase.prompt,
            selectedSkillLabels: <String>[selectedEntry.label],
          );
          await waitForConditionInternal(() => controller.sendCallCount == 1);

          expect(controller.lastPromptInternal, testCase.prompt);
          expect(controller.lastSelectedSkillLabelsInternal, <String>[
            selectedEntry.label,
          ]);
          expect(
            controller.lastWorkspacePathInternal,
            controller.assistantWorkspacePathForSession(
              controller.currentSessionKey,
            ),
          );

          controller.sendGate.complete();
          await sendFuture;

          final snapshot = await controller.loadAssistantArtifactSnapshot();
          expect(snapshot.workspaceKind, WorkspaceRefKind.localPath);
          expect(
            snapshot.fileEntries.map((item) => item.relativePath),
            contains(testCase.outputRelativePath),
          );
          expect(
            snapshot.resultEntries.map((item) => item.relativePath),
            contains(testCase.outputRelativePath),
          );
        },
      );
    }

    test(
      'records deferred media skill coverage explicitly',
      () {
        expect(installedSkillE2EDeferredCoverageInternal, <String>[
          'image-cog',
          'wan-image-video-generation-editting',
          'video-translator',
          'image-resizer',
        ]);
      },
      skip:
          'Deferred until the media skill packs are installed in the test environment.',
    );
  });
}
